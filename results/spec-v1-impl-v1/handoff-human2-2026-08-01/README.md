# Clean differential handoff for Human 2

This package contains final-field compatibility evidence only. It contains no
raw block arrays, stage dumps, PRNG states, heightmaps, decompiled material, or
implementation source.

## Versions

- Black-box harness repository: `46350472a3ab48a86f74324d26970c70ebf573b8`
- Clean Zig oracle repository: `93570409a45699958aaddfddf9a1366bfb7f08a`
- Harness image: `sha256:eb7e2e2ae41475b54b612c3fcefa85ea0e00d18301ac5a8f38fb1c4a5cb2f6a9`
- Reproduced: 2026-08-01
- Array layout: `x + width * (z + depth * y)`
- Difference arrows below are `original JAR -> clean oracle`.

## Convergence status

This is a late-stage convergence task, not a missing-generation-stage task.
The clean oracle implements the complete pipeline and the earlier 162-world
campaign compared 239,198,208 blocks with `99.776582%` volume-weighted
agreement. It produced 38 byte-identical worlds, and most failures were highly
localized. The primary counterexample below differs at only two cells.

The evidence therefore points toward a narrow specification or numeric-semantics
correction rather than a broad algorithm rewrite. Human 2 should prefer the
smallest general rule that explains the original-side traces and supplied
controls. “Narrow” describes the observed divergence; the exact cause and patch
size remain to be established by stage-local analysis.

## Primary counterexample

- Seed: `7313591729938680258`
- Dimensions: `32 x 16 x 64` (32,768 blocks)
- Original SHA-256: `848787a1d46c1b52a465cc5fd7555219d46272ae82fb0a6be6c906ed7949eaef`
- Clean-oracle SHA-256: `c0ee1c8d213e8703bc3d4af9cf50d6fce57fe05cda1aba6bd59aaa394e710396`
- Agreement: 32,766 / 32,768 blocks (`99.993896%`)
- Exact differences:
  - offset `13886`, coordinate `(30, 6, 49)`: `13 -> 2`
  - offset `15934`, coordinate `(30, 7, 49)`: `9 -> 0`

The complete difference is one vertically adjacent pair in one column. The
original material-count delta relative to the clean oracle is `+1` block 13,
`+1` block 9, `-1` block 2, and `-1` block 0; every other material count is
equal.

An independent same-shape control matches exactly:

- Seed: `7108235392311238540`
- Dimensions: `32 x 16 x 64`
- Shared SHA-256: `2037aec3bbe8f8d1be0cb83dfddfb0d44d747e38c0f7d6b4bf38ddb0970ef32e`

## Dimension controls for the primary seed

The original and clean oracle match exactly for:

| Dimensions | Shared SHA-256 |
| --- | --- |
| `16 x 16 x 64` | `e9f0389d80b18b742ffa0e24b7c39774c9d4859406e4ebeec985056bee2280b6` |
| `32 x 16 x 32` | `516c13d5947d154a81a558791cdb054fe2528f25fc20498b489edd07981ff8c4` |
| `64 x 16 x 32` | `174eee2cae088d310576a3236705c6d0b49173f26f3bdefad0b4c4a39d93b799` |

At `32 x 32 x 64`, exactly two blocks differ in the same `(x,z) = (30,49)`
column, shifted upward by eight cells:

- offset `30270`, coordinate `(30, 14, 49)`: `13 -> 12`
- offset `32318`, coordinate `(30, 15, 49)`: `9 -> 0`
- Original SHA-256: `83afced2eb4c67236ff59257b7f4a487b8995ab36ca05bb93d399df9333ee3fc`
- Clean-oracle SHA-256: `8a0878ee0d17953b33ca394bd99f67e0925d30eeda56e32b08e6a8db62180678`

This final-field evidence makes a dimension/height-dependent terrain or
surface threshold a useful first investigation target, but it does not prove
which stage first diverges.

Two larger dimension variants also mismatch and are retained in `cases.jsonl`
for replay. They are secondary because later-stage amplification makes them
less diagnostic than the two-cell examples.

## Minimum-shape fuzz probe

A deterministic probe generated 32 seeds with Python `random.Random(0xC1EA5EED)`
at `16 x 16 x 16`. All 32 original fields matched the clean oracle exactly,
with no oracle errors. The seed sequence is in `minimum-probe-seeds.txt`.

This is evidence about this finite probe only, not a claim that all minimum-size
worlds match.

## Clean-side diagnostic context

The clean implementation notes identify several relevant open points:

- `CWG-002`: exact binary32 rounding points may matter in terrain, cave, ore,
  and lava calculations.
- `CWG-004`: the specification does not select an exact Java-compatible
  binary64 sine implementation, which could affect caves or ores.
- `CWG-005`: a declaration-by-declaration clean-side audit found no obvious
  pass-order, stream, draw-order, traversal, material, or expression-order
  discrepancy. It specifically requests an earliest-stage approved vector.
- `CWG-006`: the clean oracle exposes twelve read-only block-field boundaries
  for differential diagnosis.

The clean oracle's SHA-256 at each `CWG-006` boundary for the primary case is
provided in `oracle-stage-sha256.txt`. Each digest covers exactly 32,768 bytes;
the package does not include those bytes. The last-stage digest equals the
clean final-field digest.

`CWG-003` already verifies flood traversal against the current declarative
specification, so flood ordering is a lower-priority hypothesis unless the
private original-side stage comparison first diverges there. `CWG-001` concerns
dimensions outside this small counterexample and is not currently implicated.

## Requested dirty-side analysis

1. Reproduce the primary original hash using the black-box harness.
2. Instrument the original privately at the twelve named stage boundaries and
   compare local stage hashes with `oracle-stage-sha256.txt`. Report the first
   divergent boundary; do not publish either side's stage arrays.
3. Audit the corresponding mathematical declarations. If `00_soil` is already
   different, prioritize noise, terrain height/erosion, strata, and numeric
   conversion points. If divergence begins at caves or an ore pass, prioritize
   trajectory arithmetic and `binary64Sine`. If it begins at `08_surface`,
   prioritize surface-height and material-classification semantics.
4. Check why doubling height moves the pair from `y = 6,7` to `y = 14,15`
   while preserving `(x,z)` and a two-cell difference.
5. Publish only a mathematical specification correction or clarification and
   a compact finding. Keep original-side stage arrays and analysis artifacts in
   `dirty/`.

The clean implementation should not be inspected to resolve this report. A
final-field mismatch is a request to clarify or correct the specification, not
permission to derive behavior from the clean implementation.

## Files

- `cases.jsonl`: machine-readable primary, control, and dimension-probe results.
- `minimum-probe-seeds.txt`: deterministic all-match minimum-world seed list.
- `oracle-stage-sha256.txt`: one-way clean-oracle stage checksums for the
  primary case; no intermediate arrays.
