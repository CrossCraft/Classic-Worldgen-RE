# Clean differential handoff for Human 2 — v3 residual

This package contains compact final-field compatibility evidence and one-way
clean-stage checksums. It contains no raw block arrays, stage dumps, PRNG
states, heightmaps, decompiled material, or implementation source.

## Provenance

- v3 differential report: `results/spec-v3-impl-v3/fuzz-2026-08-05.jsonl`
- Handoff workspace/result commit: `14d5ed49a470c660893db5db4c7e20cf1a0dfb6c`
- Behavioral specification revision exercised by v3: `12a6cd57198bcb35c77419f287384e01e215607a`
- Clean oracle used for the primary-stage checksums:
  `d9e55ba2d43714ff62bc98a74e02c5a0f8c30b63`
- Harness image rebuilt for the primary final-field reproduction:
  `sha256:eb7e2e2ae41475b54b612c3fcefa85ea0e00d18301ac5a8f38fb1c4a5cb2f6a9`
- Reproduced: 2026-08-05
- Array layout: `x + width * (z + depth * y)`
- Difference arrows below are `original JAR -> clean oracle`.

The stage-checksum oracle reproduces the v3 primary clean final SHA-256 exactly.
The image identity was not recorded in the original v3 result file; the listed
image is the locally rebuilt image that reproduced the recorded original final
SHA-256.

## Campaign result

The 600-second v3 run used replay RNG seed `20260805` and covered 623 final
fields: 14 fixed cases and 609 random cases. It produced 622 exact matches,
one mismatch, and no oracle errors while comparing 993,894,400 blocks. The
single mismatch contains six cells, for volume-weighted agreement of
`99.999999%`.

The published v2-to-v3 specification delta corrects the keep/skip predicate
for tree-canopy corner cells in `Spec.Level.CanopyPlacement`. The v2 campaign
had 185 mismatches; v3's single residual is consistent with that correction
having addressed the earlier tree-shaped discrepancy in this corpus. It is not
evidence that all untested inputs converge or that the remaining issue shares a
tree cause.

## Primary counterexample

- Fuzz source label: `random:261`
- Seed: `-5759849079018667514`
- Dimensions: `512 x 16 x 512` (4,194,304 blocks)
- Original SHA-256: `d0ad4513f16723b6d08ca659d4a06d0dabb49ed75f4b14bbdc25fce6251e4ea4`
- Clean-oracle SHA-256: `4d9f20bb3a75b7d7471f4a90ea85997764f0d1a6be8b79b1d8542b77a63d3b35`
- Agreement: 4,194,298 / 4,194,304 blocks (`99.999857%`)

The six differences are three vertical two-cell pairs. The three affected
horizontal positions are `(125,275)`, `(126,275)`, and `(125,276)`; the fourth
cell of that `2 x 2` horizontal square is unchanged.

| Position `(x, z)` | `y = 0`, original -> clean | `y = 1`, original -> clean |
| --- | --- | --- |
| `(125, 275)` | `12 -> 10` | `0 -> 12` |
| `(126, 275)` | `12 -> 10` | `0 -> 12` |
| `(125, 276)` | `12 -> 10` | `0 -> 12` |

The complete difference bounding box is `x = 125..126`, `y = 0..1`,
`z = 275..276`. Material-pair totals are `12 -> 10` x3 and `0 -> 12` x3.
Under the current material declarations, these are sand, flowing lava, and air
respectively. The compact pattern is consistent with the same three sand cells
being selected at adjacent vertical levels; it does not alone establish which
stage or formula first diverges.

## Current-spec focal point

The residual is directly relevant to three declarations in `Spec/Terrain.lean`:

- `soiledTerrainSemantics` assigns flowing lava at `y = 0`.
- `clampedSurfaceHeightLower` requires every valid clamped surface height to be
  at least `1`.
- `surfacedTerrainSemantics` changes only the cell at
  `surfaceHeight dimensions elevationNoise x z`.

Taken together, those declarations prevent the specified surface pass from
selecting `y = 0`. If private stage comparison shows that the first
block-visible divergence is `08_surface.blocks`, the observed downward shift
is a focused test of the lower surface-height/clamping semantics. The likely
specification issue is not yet proven: an earlier unobserved height-field or
state discrepancy can first become block-visible at the surface pass, and an
earlier fluid-stage divergence must take priority if the checksums show one.

Do not merely relax `clampedSurfaceHeightLower` from `1` to `0`. Establish the
original's complete lower-end behavior: whether the selected surface height can
be zero, whether the surface pass uses a distinct unclamped quantity, and the
exact behavior for every out-of-range terrain height. The present declaration
set gives an interior identity and bounds, but does not itself fully specify
the endpoint mapping.

## Controls

Two independent same-shape v3 cases match exactly:

| Fuzz source label | Seed | Dimensions | Shared SHA-256 |
| --- | ---: | --- | --- |
| `random:102` | `-6514491914777089334` | `512 x 16 x 512` | `1e8fb78cecb8e77b9030480fe5439c131bad0f249085e0e83b9ae0aaa4500e0a` |
| `random:509` | `2851503966509221893` | `512 x 16 x 512` | `65e0deced86f1202d224610f03876774483257925d4a7dc7b9bc54cf0c0df8bf` |

The fixed large-shape case also matches exactly:

| Seed | Dimensions | Shared SHA-256 |
| ---: | --- | --- |
| `12345` | `512 x 128 x 512` | `85020bcafbad4067ce6510b10180a3738e86437c3bc6d2c5b39c27458abb3f00` |

These controls constrain the residual but do not establish a general threshold
or isolate a formula. They are retained in `cases.jsonl` for direct replay.

## Clean-side diagnostic context

`oracle-stage-sha256.txt` gives the clean field SHA-256 at the twelve existing
logical boundaries for the primary case. Every digest covers exactly 4,194,304
bytes in the stated array layout; no stage arrays are included. The
`11_trees.blocks` digest equals the primary clean final hash.

Matching hashes through a boundary localize block-visible agreement only. In
particular, matching through `07_lava.blocks` does not prove equality of an
unpublished elevation value or random state that is first consumed by the
surface pass.

## Requested original-side analysis and correction

1. Reproduce the primary original final SHA-256 with the black-box harness.
2. Privately capture exactly the twelve named block-field boundaries and
   compare their SHA-256 values with `oracle-stage-sha256.txt`. Do not publish
   either side's arrays or private traces.
3. Follow the first divergent boundary rather than the final pattern:
   - If `00_soil.blocks` differs, audit terrain elevation, the lower clamp, and
     integer/numeric conversion semantics before treating the sand pair as a
     surface-only error.
   - If any water or lava boundary first differs, audit the corresponding
     source, reachability, reaction, and mutation timing first.
   - If `00_soil` through `07_lava` match and `08_surface` first differs,
     privately inspect the three listed columns: the raw terrain height,
     selected surface height, clamp endpoint, above-cell test, and sand
     threshold. Determine why the original selects `y = 0` while the clean
     result selects `y = 1` at precisely those three positions.
   - If the first mismatch is after `08_surface`, investigate that actual
     mutation path; do not infer a surface-height correction solely from the
     final materials.
4. Publish the smallest complete mathematical clarification in
   `Spec/Terrain.lean`, likely involving `clampedSurfaceHeight` and/or
   `surfacedTerrain`, only after original-side evidence establishes the rule.
   The correction must be general, not coordinate-, seed-, or dimension-based.
5. Validate the rule privately against the primary and both same-shape controls.
   Then ask the implementation side to rerun the primary, the controls, and a
   fresh differential campaign before declaring convergence.

The clean implementation should not be inspected to resolve this report. A
final-field mismatch is a request for a mathematical specification correction
or clarification, not permission to derive behavior from the implementation.

## Files

- `cases.jsonl`: machine-readable primary and control final-field records.
- `oracle-stage-sha256.txt`: one-way clean-oracle checksums for the primary
  field at the twelve logical boundaries.
