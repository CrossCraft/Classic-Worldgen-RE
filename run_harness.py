#!/usr/bin/env python3
"""Python driver for controlled Minecraft Classic server 1.10 worldgen."""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


class HarnessError(RuntimeError):
    pass


BLOCK_NAMES = {
    0: "air",
    1: "stone",
    2: "grass",
    3: "dirt",
    4: "cobblestone",
    5: "planks",
    6: "sapling",
    7: "bedrock",
    8: "flowing_water",
    9: "still_water",
    10: "flowing_lava",
    11: "still_lava",
    12: "sand",
    13: "gravel",
    14: "gold_ore",
    15: "iron_ore",
    16: "coal_ore",
    17: "log",
    18: "leaves",
    19: "sponge",
    20: "glass",
    21: "red_wool",
    22: "orange_wool",
    23: "yellow_wool",
    24: "chartreuse_wool",
    25: "green_wool",
    26: "spring_green_wool",
    27: "cyan_wool",
    28: "capri_wool",
    29: "ultramarine_wool",
    30: "purple_wool",
    31: "violet_wool",
    32: "magenta_wool",
    33: "rose_wool",
    34: "dark_gray_wool",
    35: "light_gray_wool",
    36: "white_wool",
    37: "flower_1",
    38: "flower_2",
    39: "mushroom_1",
    40: "mushroom_2",
    41: "gold",
    42: "iron",
    43: "double_slab",
    44: "slab",
    45: "brick",
    46: "tnt",
    47: "bookshelf",
    48: "mossy_rocks",
    49: "obsidian",
}

COMPOSITION_GROUPS = {
    "water": (8, 9),
    "dirt": (3,),
    "stone": (1,),
    "grass": (2,),
    "logs": (17,),
    "leaves": (18,),
    "lava": (10, 11),
    "ore": (14, 15, 16),
}

# Bulk materials are normalized by level volume. Surface materials and lava
# layers are normalized by horizontal column count so custom heights remain
# comparable. These intentionally broad bounds are corruption/regression
# checks, not claims about a seed's exact terrain distribution.
PLAUSIBILITY_RULES = {
    "water": ("volume", 0.0005, 0.20),
    "dirt": ("horizontal_columns", 0.20, 8.0),
    "stone": ("volume", 0.05, 0.75),
    "grass": ("horizontal_columns", 0.05, 1.10),
    "logs": ("horizontal_columns", 0.001, 0.20),
    "leaves": ("horizontal_columns", 0.01, 1.50),
    "lava": ("horizontal_columns", 0.25, 5.0),
    "ore": ("volume", 0.001, 0.08),
}


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


def describe_composition(blocks: bytes) -> dict[str, object]:
    counts = Counter(blocks)
    total = len(blocks)

    block_counts = [
        {
            "id": block_id,
            "name": BLOCK_NAMES.get(block_id, "unknown"),
            "count": count,
            "percent": round(100.0 * count / total, 6),
        }
        for block_id, count in sorted(counts.items())
    ]
    groups = {
        name: {
            "ids": list(block_ids),
            "count": sum(counts[block_id] for block_id in block_ids),
            "percent": round(
                100.0 * sum(counts[block_id] for block_id in block_ids) / total,
                6,
            ),
        }
        for name, block_ids in COMPOSITION_GROUPS.items()
    }
    return {"total": total, "blocks": block_counts, "groups": groups}


def check_composition(
    width: int, height: int, depth: int, blocks: bytes
) -> dict[str, object]:
    counts = Counter(blocks)
    denominators = {
        "volume": width * height * depth,
        "horizontal_columns": width * depth,
    }
    checks = []
    for name, (basis, minimum, maximum) in PLAUSIBILITY_RULES.items():
        block_ids = COMPOSITION_GROUPS[name]
        count = sum(counts[block_id] for block_id in block_ids)
        normalized = count / denominators[basis]

        # Tiny maps may plausibly have no exposed grass, trees, or generated ore.
        small_surface = width * depth < 4096
        small_volume = width * height * depth < 262144
        optional_on_tiny_map = (
            name in ("grass", "logs", "leaves") and small_surface
        ) or (name == "ore" and small_volume)
        effective_minimum = 0.0 if optional_on_tiny_map else minimum
        checks.append(
            {
                "group": name,
                "ids": list(block_ids),
                "count": count,
                "basis": basis,
                "normalized": round(normalized, 8),
                "minimum": effective_minimum,
                "maximum": maximum,
                "ok": effective_minimum <= normalized <= maximum,
            }
        )
    return {"ok": all(check["ok"] for check in checks), "checks": checks}


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate and verify a seeded Classic server 1.10 Level."
    )
    parser.add_argument("--seed", required=True, type=int)
    parser.add_argument("--width", type=int, default=256)
    parser.add_argument("--height", type=int, default=64)
    parser.add_argument("--depth", type=int, default=256)
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
    parser.add_argument(
        "--composition", action="store_true",
        help="include counts and percentages for every block ID present",
    )
    parser.add_argument(
        "--check-composition", action="store_true",
        help="fail if key material quantities are outside broad plausible bounds",
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
    if args.composition or args.check_composition:
        result["composition"] = describe_composition(blocks)
    if args.check_composition:
        plausibility = check_composition(
            args.width, args.height, args.depth, blocks
        )
        result["plausibility"] = plausibility
    print(json.dumps(result, separators=(",", ":")))
    if args.check_composition and not plausibility["ok"]:
        print("error: implausible block composition", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
