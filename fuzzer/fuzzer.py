#!/usr/bin/env python3
"""Differential fuzzer for Classic worldgen oracles.

Drives two oracles through the CLI contract in fuzzer/ORACLE.md: first a
fixed corpus of edge cases, then random cases until a wall-clock deadline.
After every case it reports a match, a mismatch (with similarity stats), or
an oracle error, and ends with a campaign summary.

Oracle commands are templates; the placeholders {seed}, {width}, {height},
{depth}, and {out} are filled in per case. Exit status: 0 when every case
matched, 1 when mismatches were found, 2 when any oracle run errored.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import random
import shlex
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import TextIO

ROOT = Path(__file__).resolve().parent.parent

LONG_MIN, LONG_MAX = -(1 << 63), (1 << 63) - 1
HORIZONTAL_EXPONENTS = range(4, 10)  # width/depth 16..512
HEIGHT_EXPONENTS = range(4, 8)  # height 16..128

# Cheap 64^3 shape for the seed sweep: LCG boundaries, zero, sign flips, and
# the known-good harness seed.
EDGE_DIMS = (64, 64, 64)
EDGE_SEEDS = [
    0,
    1,
    -1,
    12345,
    (1 << 31) - 1,
    -(1 << 31),
    1 << 48,
    LONG_MAX,
    LONG_MIN,
]

# Dimension shapes probed with one fixed seed: minimum level, slivers, and
# the standard Classic size.
SHAPE_CASES = [
    (16, 16, 16),
    (16, 64, 16),
    (256, 16, 256),
    (256, 64, 256),
    (512, 128, 512),
]
SHAPE_SEED = 12345


@dataclasses.dataclass(frozen=True)
class Case:
    label: str
    seed: int
    width: int
    height: int
    depth: int

    @property
    def volume(self) -> int:
        return self.width * self.height * self.depth


def default_harness_command() -> str:
    return (
        f"python3 {ROOT / 'run_harness.py'} --jar {ROOT / 'classic.jar'}"
        " --seed {seed} --width {width} --height {height} --depth {depth}"
        " --blocks-out {out}"
    )


def fixed_cases() -> list[Case]:
    cases = [
        Case(f"edge-seed:{seed}", seed, *EDGE_DIMS) for seed in EDGE_SEEDS
    ]
    cases += [
        Case(f"shape:{w}x{h}x{d}", SHAPE_SEED, w, h, d)
        for w, h, d in SHAPE_CASES
    ]
    return cases


def random_case(rng: random.Random, index: int) -> Case:
    return Case(
        f"random:{index}",
        rng.randrange(LONG_MIN, LONG_MAX + 1),
        1 << rng.choice(HORIZONTAL_EXPONENTS),
        1 << rng.choice(HEIGHT_EXPONENTS),
        1 << rng.choice(HORIZONTAL_EXPONENTS),
    )


def run_oracle(
    template: str, case: Case, out_path: Path, timeout: float
) -> tuple[bytes | None, str | None]:
    argv = [
        token.format(
            seed=case.seed,
            width=case.width,
            height=case.height,
            depth=case.depth,
            out=str(out_path),
        )
        for token in shlex.split(template)
    ]
    try:
        process = subprocess.run(
            argv, capture_output=True, text=True, timeout=timeout
        )
    except subprocess.TimeoutExpired:
        return None, f"oracle timed out after {timeout}s"
    except OSError as error:
        return None, f"oracle failed to launch: {error}"

    if process.returncode != 0:
        detail = process.stderr.strip()[-400:]
        return None, f"oracle exited {process.returncode}: {detail}"
    if not out_path.is_file():
        return None, "oracle wrote no output file"

    blocks = out_path.read_bytes()
    if len(blocks) != case.volume:
        return None, (
            f"oracle wrote {len(blocks)} bytes, expected {case.volume}"
        )
    return blocks, None


def mismatch_stats(
    a: bytes, b: bytes, case: Case
) -> dict[str, object]:
    first = None
    differing = 0
    for offset, (byte_a, byte_b) in enumerate(zip(a, b)):
        if byte_a != byte_b:
            differing += 1
            if first is None:
                first = offset
    assert first is not None and differing > 0

    row = case.width
    slab = row * case.depth
    y, rest = divmod(first, slab)
    z, x = divmod(rest, row)
    return {
        "differing": differing,
        "agree_percent": round(100.0 * (len(a) - differing) / len(a), 6),
        "first_offset": first,
        "first_coord": {"x": x, "y": y, "z": z},
        "first_blocks": {"a": a[first], "b": b[first]},
    }


def parse_duration(text: str) -> float:
    units = {"s": 1, "m": 60, "h": 3600}
    suffix = text[-1]
    if suffix in units:
        return float(text[:-1]) * units[suffix]
    return float(text)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--oracle-a", default=default_harness_command(),
        help="command template for oracle A (default: the JAR harness)",
    )
    parser.add_argument(
        "--oracle-b", required=True,
        help="command template for oracle B (e.g. the reference oracle);"
             " pass the same command twice for a determinism smoke test",
    )
    parser.add_argument(
        "--duration", type=parse_duration, default=600.0, metavar="SECONDS|Nm|Nh",
        help="wall-clock budget for the random phase (default 10m);"
             " the fixed corpus always runs to completion first",
    )
    parser.add_argument(
        "--rng-seed", type=int,
        help="seed for the fuzzer's own case generator"
             " (default: random; printed at startup for replay)",
    )
    parser.add_argument(
        "--oracle-timeout", type=float, default=600.0, metavar="SECONDS",
        help="per-invocation oracle timeout (default 600)",
    )
    parser.add_argument(
        "--report", type=Path,
        help="append one JSON record per case to this file",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)

    rng_seed = args.rng_seed
    if rng_seed is None:
        rng_seed = random.SystemRandom().randrange(1 << 63)
    rng = random.Random(rng_seed)
    deadline = time.monotonic() + args.duration

    print(f"fuzzer rng seed: {rng_seed}")
    print(f"oracle A: {args.oracle_a}")
    print(f"oracle B: {args.oracle_b}")

    report_file: TextIO | None = None
    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        report_file = args.report.open("a", encoding="utf-8")

    counts = {"match": 0, "mismatch": 0, "error": 0}
    findings: list[dict[str, object]] = []
    started = time.monotonic()

    def run(case: Case) -> None:
        with tempfile.TemporaryDirectory(prefix="classic-fuzz-") as work:
            workdir = Path(work)
            case_started = time.monotonic()
            blocks_a, error_a = run_oracle(
                args.oracle_a, case, workdir / "a.blocks", args.oracle_timeout
            )
            blocks_b, error_b = run_oracle(
                args.oracle_b, case, workdir / "b.blocks", args.oracle_timeout
            )
            elapsed = time.monotonic() - case_started

        dims = f"{case.width}x{case.height}x{case.depth}"
        record: dict[str, object] = {
            "label": case.label,
            "seed": case.seed,
            "width": case.width,
            "height": case.height,
            "depth": case.depth,
            "seconds": round(elapsed, 3),
        }

        if error_a is not None or error_b is not None:
            outcome = "error"
            record["errors"] = {"a": error_a, "b": error_b}
            line = f"ERROR   {case.label} seed={case.seed} {dims}"
            if error_a is not None:
                line += f"\n  A: {error_a}"
            if error_b is not None:
                line += f"\n  B: {error_b}"
        else:
            assert blocks_a is not None and blocks_b is not None
            record["sha256"] = {
                "a": hashlib.sha256(blocks_a).hexdigest(),
                "b": hashlib.sha256(blocks_b).hexdigest(),
            }
            if blocks_a == blocks_b:
                outcome = "match"
                line = (
                    f"MATCH   {case.label} seed={case.seed} {dims}"
                    f" ({elapsed:.1f}s)"
                )
            else:
                outcome = "mismatch"
                stats = mismatch_stats(blocks_a, blocks_b, case)
                record["mismatch"] = stats
                coord = stats["first_coord"]
                line = (
                    f"MISMATCH {case.label} seed={case.seed} {dims}"
                    f" differing={stats['differing']}/{case.volume}"
                    f" agree={stats['agree_percent']}%"
                    f" first=(x={coord['x']},y={coord['y']},z={coord['z']})"
                    f"@{stats['first_offset']}"
                    f" a={stats['first_blocks']['a']}"
                    f" b={stats['first_blocks']['b']}"
                    f" ({elapsed:.1f}s)"
                )

        record["outcome"] = outcome
        counts[outcome] += 1
        if outcome != "match":
            findings.append(record)
        print(line, flush=True)
        if report_file is not None:
            report_file.write(json.dumps(record) + "\n")
            report_file.flush()

    for case in fixed_cases():
        run(case)
    print(f"fixed corpus done; random phase until {args.duration:g}s elapse")

    index = 0
    while time.monotonic() < deadline:
        index += 1
        run(random_case(rng, index))

    total = sum(counts.values())
    elapsed = time.monotonic() - started
    print(f"== summary: {total} cases in {elapsed:.0f}s"
          f" (rng seed {rng_seed}) ==")
    print(f"matches: {counts['match']}, mismatches: {counts['mismatch']},"
          f" oracle errors: {counts['error']}")
    for record in findings:
        print(f"  {record['outcome'].upper()}: seed={record['seed']}"
              f" {record['width']}x{record['height']}x{record['depth']}"
              f" [{record['label']}]")

    if report_file is not None:
        report_file.close()
    if counts["error"]:
        return 2
    return 1 if counts["mismatch"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
