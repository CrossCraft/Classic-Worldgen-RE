#!/usr/bin/env python3
"""Python driver for controlled Minecraft Classic server 1.10 worldgen."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


class HarnessError(RuntimeError):
    pass


def bridge_path() -> Path:
    configured = os.environ.get("CLASSIC_HARNESS_BRIDGE")
    if configured:
        return Path(configured)
    container_path = Path("/opt/classic-harness/classic-harness.jar")
    if container_path.is_file():
        return container_path
    return Path(__file__).resolve().parent / "build/classic-harness.jar"


class ClassicHarness:
    """Own a temporary output workspace and drive one-shot JVM workers."""

    def __init__(self, classic_jar: Path):
        self.classic_jar = classic_jar.resolve()
        self.bridge = bridge_path().resolve()
        self._temporary: tempfile.TemporaryDirectory[str] | None = None
        self._root: Path | None = None
        self._class_path: str | None = None

    def __enter__(self) -> "ClassicHarness":
        if not self.classic_jar.is_file():
            raise HarnessError(f"classic JAR not found: {self.classic_jar}")
        if not self.bridge.is_file():
            raise HarnessError(
                f"Java bridge not found: {self.bridge}; build the Docker image first"
            )

        self._temporary = tempfile.TemporaryDirectory(prefix="classic-worldgen-")
        self._root = Path(self._temporary.name)
        self._class_path = os.pathsep.join((str(self.bridge), str(self.classic_jar)))
        return self

    def __exit__(self, *_: object) -> None:
        if self._temporary is not None:
            self._temporary.cleanup()

    def generate(
        self, seed: int, width: int, height: int, depth: int
    ) -> bytes:
        if self._root is None or self._class_path is None:
            raise HarnessError("ClassicHarness must be used as a context manager")

        output = self._root / "level.blocks"
        process = subprocess.run(
            [
                "java",
                f"-javaagent:{self.bridge}",
                "-cp",
                self._class_path,
                "org.crosscraft.classicworldgen.ClassicHarness",
                str(seed),
                str(width),
                str(height),
                str(depth),
                str(output),
            ],
            cwd=self._root,
            text=True,
            capture_output=True,
            check=False,
        )

        if process.returncode:
            detail = process.stderr.strip()
            message = f"Java bridge exited with status {process.returncode}"
            raise HarnessError(f"{message}: {detail}" if detail else message)
        if not output.is_file():
            raise HarnessError("Java bridge did not produce a block array")

        blocks = output.read_bytes()
        expected = width * height * depth
        if len(blocks) != expected:
            raise HarnessError(
                f"Level exposed {len(blocks)} blocks; expected {expected}"
            )
        return blocks


def generate(
    seed: int,
    classic_jar: Path,
    width: int,
    height: int,
    depth: int,
    verify: bool = False,
) -> bytes:
    with ClassicHarness(classic_jar) as harness:
        blocks = harness.generate(seed, width, height, depth)
        if verify:
            if blocks != harness.generate(seed, width, height, depth):
                raise HarnessError("same seed produced different block arrays")
            control_seed = -(1 << 63) if seed == (1 << 63) - 1 else seed + 1
            if blocks == harness.generate(control_seed, width, height, depth):
                raise HarnessError("adjacent seed produced the same block array")
    return blocks


def describe(
    seed: int, width: int, height: int, depth: int, blocks: bytes
) -> dict[str, object]:
    return {
        "seed": seed,
        "width": width,
        "height": height,
        "depth": depth,
        "sha256": hashlib.sha256(blocks).hexdigest(),
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate and verify a seeded Classic server 1.10 Level."
    )
    parser.add_argument("--seed", required=True, type=int)
    parser.add_argument("--width", type=int, default=256)
    parser.add_argument("--height", type=int, default=256)
    parser.add_argument("--depth", type=int, default=64)
    parser.add_argument(
        "--jar", type=Path, default=Path("/harness/classic.jar"),
        help="path to the user-supplied classic.jar",
    )
    parser.add_argument(
        "--blocks-out", type=Path,
        help="optionally write the first generated Level's raw byte array",
    )
    parser.add_argument(
        "--verify", action="store_true",
        help="also check same-seed repeatability and an adjacent-seed control",
    )
    args = parser.parse_args(argv)
    if not -(1 << 63) <= args.seed < (1 << 63):
        parser.error("--seed must fit a signed Java long")
    for name in ("width", "height", "depth"):
        value = getattr(args, name)
        if value < 16 or value & (value - 1):
            parser.error(f"--{name} must be a power of two and at least 16")
    if args.width * args.height * args.depth > (1 << 31) - 1:
        parser.error("level volume exceeds Java's maximum array length")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        blocks = generate(
            args.seed,
            args.jar,
            args.width,
            args.height,
            args.depth,
            verify=args.verify,
        )
        if args.blocks_out is not None:
            args.blocks_out.write_bytes(blocks)
    except (HarnessError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    result = describe(args.seed, args.width, args.height, args.depth, blocks)
    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
