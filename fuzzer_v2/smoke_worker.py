#!/usr/bin/env python3
"""Check a persistent v2 worker against a known original-harness hash."""

from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from fuzzer_v2.campaign import Case  # noqa: E402
from fuzzer_v2.worker import WorkerError, WorkerProcess  # noqa: E402

KNOWN_SEED_ZERO_64_SHA256 = (
    "764e62ce3d1de727b66d414a1521f9a8c5b01d21082b74f3191cbe7a0c5fb308"
)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", required=True, help="full persistent worker command")
    parser.add_argument("--timeout", type=float, default=60.0)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if args.timeout <= 0:
        print("error: --timeout must be positive", file=sys.stderr)
        return 2
    cases = (
        Case(0, "known:seed-zero", "smoke", 0, 64, 64, 64),
        Case(1, "control:minimum", "smoke", 12345, 16, 16, 16),
        Case(2, "known:seed-zero-repeat", "smoke", 0, 64, 64, 64),
    )
    with tempfile.TemporaryDirectory(prefix="classic-fuzz-v2-smoke-") as root:
        root_path = Path(root)
        worker = WorkerProcess(args.worker, 0, "smoke", root_path / "stderr.txt")
        try:
            worker.start(args.timeout)
            digests = []
            for case in cases:
                result = worker.generate_to_file(case, root_path / "blocks", args.timeout)
                digests.append(result.sha256.hex())
        except WorkerError as error:
            print(f"error: {error}", file=sys.stderr)
            worker.terminate()
            return 2
        finally:
            worker.shutdown()
    if digests[0] != KNOWN_SEED_ZERO_64_SHA256:
        print(f"error: unexpected first known hash: {digests[0]}", file=sys.stderr)
        return 1
    if digests[2] != KNOWN_SEED_ZERO_64_SHA256:
        print(f"error: unexpected repeated known hash: {digests[2]}", file=sys.stderr)
        return 1
    print("persistent worker known-hash and state-isolation check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
