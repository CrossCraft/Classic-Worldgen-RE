"""Deterministic v2 campaign inputs and shared campaign constants."""

from __future__ import annotations

import dataclasses
import hashlib
import json
from collections.abc import Iterator

LONG_MIN, LONG_MAX = -(1 << 63), (1 << 63) - 1
HORIZONTAL_EXPONENTS = range(4, 10)  # width/depth 16..512
HEIGHT_EXPONENTS = range(4, 8)  # height 16..128

PROTOCOL_VERSION = 2
CASE_GENERATOR_VERSION = "sha256-counter-v1"
FIXED_CORPUS_VERSION = 1

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

SHAPE_CASES = [
    (16, 16, 16),
    (16, 64, 16),
    (256, 16, 256),
    (256, 64, 256),
    (512, 128, 512),
]
SHAPE_SEED = 12345
FIXED_CASE_COUNT = len(EDGE_SEEDS) + len(SHAPE_CASES) + 1

V3_FAILURE = (
    "regression:v3",
    -5759849079018667514,
    512,
    16,
    512,
)


@dataclasses.dataclass(frozen=True)
class Case:
    """One source-addressable world-generation request."""

    sequence: int
    label: str
    phase: str
    seed: int
    width: int
    height: int
    depth: int
    random_index: int | None = None

    @property
    def volume(self) -> int:
        return self.width * self.height * self.depth


def fixed_cases() -> list[Case]:
    """Return the v2 copy of the legacy 15-case fixed corpus."""

    plain: list[tuple[str, int, int, int, int]] = [
        (f"edge-seed:{seed}", seed, *EDGE_DIMS) for seed in EDGE_SEEDS
    ]
    plain.extend(
        (f"shape:{width}x{height}x{depth}", SHAPE_SEED, width, height, depth)
        for width, height, depth in SHAPE_CASES
    )
    plain.append(V3_FAILURE)
    return [
        Case(
            sequence=index,
            label=label,
            phase="fixed",
            seed=seed,
            width=width,
            height=height,
            depth=depth,
        )
        for index, (label, seed, width, height, depth) in enumerate(plain)
    ]


def fixed_corpus_sha256() -> str:
    """Fingerprint the corpus so resumed runs cannot silently change it."""

    rows = [dataclasses.asdict(case) for case in fixed_cases()]
    payload = json.dumps(rows, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(payload).hexdigest()


class _DigestBytes:
    """A small deterministic byte stream derived from a case counter."""

    def __init__(self, rng_seed: int, index: int):
        self._seed = str(rng_seed).encode("ascii")
        self._index = str(index).encode("ascii")
        self._block = 0
        self._buffer = bytearray()

    def bytes(self, count: int) -> bytes:
        while len(self._buffer) < count:
            material = b"\0".join(
                (
                    b"classic-worldgen-fuzzer-v2",
                    CASE_GENERATOR_VERSION.encode("ascii"),
                    self._seed,
                    self._index,
                    str(self._block).encode("ascii"),
                )
            )
            self._buffer.extend(hashlib.sha256(material).digest())
            self._block += 1
        result = bytes(self._buffer[:count])
        del self._buffer[:count]
        return result

    def randbelow(self, upper: int) -> int:
        if upper <= 0 or upper > 256:
            raise ValueError("upper must be in 1..256")
        limit = 256 - (256 % upper)
        while True:
            value = self.bytes(1)[0]
            if value < limit:
                return value % upper


def random_case(rng_seed: int, index: int) -> Case:
    """Derive random case ``index`` without relying on mutable RNG state."""

    if index < 1:
        raise ValueError("random case index must be positive")
    source = _DigestBytes(rng_seed, index)
    seed = int.from_bytes(source.bytes(8), "big", signed=True)
    width = 1 << (HORIZONTAL_EXPONENTS.start + source.randbelow(len(HORIZONTAL_EXPONENTS)))
    height = 1 << (HEIGHT_EXPONENTS.start + source.randbelow(len(HEIGHT_EXPONENTS)))
    depth = 1 << (HORIZONTAL_EXPONENTS.start + source.randbelow(len(HORIZONTAL_EXPONENTS)))
    return Case(
        sequence=FIXED_CASE_COUNT + index - 1,
        label=f"random:{index}",
        phase="random",
        random_index=index,
        seed=seed,
        width=width,
        height=height,
        depth=depth,
    )


def cases_for_random_indices(rng_seed: int, indices: Iterator[int]) -> Iterator[Case]:
    for index in indices:
        yield random_case(rng_seed, index)
