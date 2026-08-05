# Clean differential handoff for Human 2

This package contains final-field compatibility evidence only. It contains no
raw block arrays, stage dumps, PRNG states, heightmaps, decompiled material, or
implementation source.

## Versions

- Black-box harness repository: `4265d4d4d1b7c914e06733c0008ccd76e95b13e4`
- Clean Zig oracle repository: `9a004fee1489c9dc5eb04e9bee8d08e935dc9167`
- Harness image: `sha256:eb7e2e2ae41475b54b612c3fcefa85ea0e00d18301ac5a8f38fb1c4a5cb2f6a9`
- Reproduced: 2026-08-05
- Array layout: `x + width * (z + depth * y)`
- Difference arrows below are `original JAR -> clean oracle`.

## Convergence status

The corrected v2 corpus contains 270 final-field cases: 14 fixed and 256
random. It compared 508,317,696 blocks with 99.828822% volume-weighted
agreement, producing 85 byte-identical worlds, 185 mismatches, and no oracle
errors. This improves on the earlier v1 campaign's 99.776582% volume-weighted
agreement, but it does not establish that all remaining mismatches share one
cause.

The primary case below was selected because it has only 16 different cells.
It is a focused diagnostic target, not a claim that it represents every v2
failure. Its final-field shape is compatible with a small late-stage mutation,
but final-field evidence alone cannot identify the first divergent stage.

## Primary counterexample

- Fuzz source label: `random:46`
- Seed: `4340555035370659350`
- Dimensions: `256 x 16 x 16` (65,536 blocks)
- Original SHA-256: `71d5811eb4c4b0fdca11add752c89f9f2484717ddf2f2c67f32a4b79d25eacc9`
- Clean-oracle SHA-256: `831943b147600a6a88236db67626e59b710586eac65aac8bc3f238a8bd617965`
- Agreement: 65,520 / 65,536 blocks (`99.975586%`)

All 16 differences lie in `x = 6..10`, `y = 11..14`, and `z = 7..11`.
Their material-pair totals are `0 -> 18` ×11, `2 -> 18` ×1, and `18 -> 0`
×4.

| Coordinate | Original -> clean |
| --- | --- |
| `(6, 11, 7)` | `2 -> 18` |
| `(10, 11, 7)` | `0 -> 18` |
| `(6, 11, 11)` | `0 -> 18` |
| `(10, 11, 11)` | `18 -> 0` |
| `(6, 12, 7)` | `18 -> 0` |
| `(10, 12, 7)` | `18 -> 0` |
| `(6, 12, 11)` | `0 -> 18` |
| `(10, 12, 11)` | `0 -> 18` |
| `(7, 13, 8)` | `0 -> 18` |
| `(9, 13, 8)` | `0 -> 18` |
| `(7, 13, 10)` | `0 -> 18` |
| `(9, 13, 10)` | `18 -> 0` |
| `(7, 14, 8)` | `0 -> 18` |
| `(9, 14, 8)` | `0 -> 18` |
| `(7, 14, 10)` | `0 -> 18` |
| `(9, 14, 10)` | `0 -> 18` |

## Controls and dimension probes

An independent same-shape control matches exactly:

- Fuzz source label: `random:195`
- Seed: `5985647233902920428`
- Dimensions: `256 x 16 x 16`
- Shared SHA-256: `351e74eab29d0d485b622dfc0a40e9694498da6a18982e4038d1ec3594ab4f76`

For the primary seed, these smaller-width variants also match exactly:

| Dimensions | Shared SHA-256 |
| --- | --- |
| `16 x 16 x 16` | `7f99bc1b7dee418b677dcd34830efc660f453d57ccecc9f1a7e41e1737d1cd20` |
| `32 x 16 x 16` | `b627cf8b22e8dc86c09a0ee15c69f90a603e17ef4aea00cca11cfaf8e9e7e4c8` |
| `64 x 16 x 16` | `61f5b3612ec52e9b9d3b9ddf908c45a5ad6d6b001c06dea371b3885cb1b927a8` |
| `128 x 16 x 16` | `a8a8e8942d5591d68ab17fe5db9717efcbfa4d285244544b85900d285adc541a` |

The primary `256 x 16 x 16` field then differs by 16 cells. At
`512 x 16 x 16`, 75 cells differ, with a bounding box of `x = 321..372`,
`y = 11..14`, `z = 0..14`. Two axis changes are retained as secondary
mismatches in `cases.jsonl`:

- `256 x 32 x 16`: 186 differences, bounding box `x = 171..205`,
  `y = 16..30`, `z = 0..15`.
- `256 x 16 x 32`: 188 differences, bounding box `x = 172..208`,
  `y = 10..14`, `z = 0..18`.

Dimension changes can alter the generated field and the random stream, so the
probes constrain the behavior but do not by themselves identify a formula or
pass.

## Minimum-shape fuzz probe

The deterministic 32-seed probe in `minimum-probe-seeds.txt` was rerun at
`16 x 16 x 16`. All 32 original final fields matched the clean oracle exactly,
with no oracle errors. This is evidence about this finite probe only, not a
claim that all minimum-size worlds match.

## Clean-side diagnostic context

The clean oracle exposes twelve read-only final-field boundaries. Its SHA-256
digest at each boundary for the primary case is in
`oracle-stage-sha256.txt`. Every digest covers exactly 65,536 bytes; the
package does not include those bytes. The `11_trees.blocks` digest equals the
clean final-field digest above.

These hashes allow private original-side localization without transferring
intermediate arrays. A mismatch at a boundary is localization evidence, not
proof that the named pass is the root cause: unobserved earlier numeric state
or random-state divergence may first become block-visible later.

## Requested dirty-side analysis

1. Reproduce the primary original final hash using the black-box harness.
2. Instrument the original privately at the twelve named stage boundaries and
   compare local stage hashes with `oracle-stage-sha256.txt`. Report the first
   divergent boundary; do not publish either side's stage arrays.
3. If the fields match through `10_mushrooms.blocks` and first differ at
   `11_trees.blocks`, audit the mathematical tree-placement semantics: attempt
   count, random draws, eligibility predicates, coordinate traversal, and
   mutation timing. Treat the compact final patch as a hypothesis generator,
   not as proof of a tree-stage cause.
4. If an earlier boundary is different, investigate that stage first and treat
   the final patch as downstream amplification. Do not force the evidence into
   the late-stage hypothesis.
5. Check the exact same-shape control, the matching width ladder through
   `128 x 16 x 16`, the primary `256 x 16 x 16` mismatch, and the
   `512 x 16 x 16` variant. The height and depth variants are secondary
   confirmation cases.
6. Publish only a mathematical specification correction or clarification and
   a compact finding. Keep original-side stage arrays and analysis artifacts in
   `dirty/`.

The clean implementation should not be inspected to resolve this report. A
final-field mismatch is a request to clarify or correct the specification, not
permission to derive behavior from the clean implementation.

## Files

- `cases.jsonl`: machine-readable primary, control, and dimension-probe
  results.
- `minimum-probe-seeds.txt`: deterministic all-match minimum-world seed list.
- `oracle-stage-sha256.txt`: one-way clean-oracle stage checksums for the
  primary case; no intermediate arrays.
