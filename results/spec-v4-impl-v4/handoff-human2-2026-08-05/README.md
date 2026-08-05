# Clean differential handoff for Human 2 — v4 residual

This package contains compact final-field compatibility evidence and one-way
clean-stage checksums. It contains no raw block arrays, stage dumps, PRNG
states, heightmaps, decompiled material, or implementation source.

## Provenance

- v4 persistent differential report:
  `results/spec-v4-impl-v4/fuzz-v2-2026-08-05-32c-5m/campaign.sqlite`
- Campaign run ID: `30e9c67a-4040-4f9a-a3b8-2f17ceb96737`
- Handoff workspace/result commit: `2ff460b89ad46b9086b6098d697d201d03243919`
- Behavioral specification revision exercised by v4:
  `42c1a1b21215988166e852cf36d05d156d632afb`
- Clean oracle used for final-field reproduction and stage checksums:
  `5c36a1bfda25505a9de122b90923a9b6b42d9a38`
- Harness image used for final-field reproduction:
  `sha256:eeffeb5451ea91d31c85357a2205fed7393ff1a60dcaeaa406f9eb680eee38eb`
- Original JAR SHA-256:
  `06b15435d2b4bcfa032f9ddc9feefd20c62609eaa68b46ec59bacd097e87fb55`
- Reproduced: 2026-08-05
- Array layout: `x + width * (z + depth * y)`
- Difference arrows below are `original JAR -> clean oracle`.

The stored campaign uses generator version `sha256-counter-v1`, protocol
version 2, replay RNG seed `20260805`, and fixed-corpus digest
`fbb00c2aea27d7c36d6a09ba40a618e3d70412e27ba3d19cb793b528e6708adb`.

## Campaign result

The v4 fuzzer-v2 run used 32 persistent worker lanes and had a 300-second
random-phase budget. It stopped on the first mismatch after 56.0 seconds of
wall time (43.754 seconds of recorded random-phase elapsed time), so it is
finite compatibility evidence, not a completed five-minute campaign.

It recorded 1,530 final fields: 15 fixed and 1,515 random. Of those, 1,529
matched exactly, one mismatched, and none had oracle errors. The run compared
2,461,790,208 blocks with 44 differing blocks, yielding `99.999998%`
volume-weighted agreement. The mismatch field has `99.998951%` agreement.

The v4 specification revision generalized notifying placement of falling
materials during tree growth. The residual's final shape is relevant to that
revision, but it does not establish its cause or its first divergent stage.
Follow the stage hashes before revising any declaration.

## Primary counterexample

- Fuzz source label: `random:1396`
- Seed: `-486299723741911703`
- Dimensions: `512 x 32 x 256` (4,194,304 blocks)
- Original SHA-256:
  `fd6707e443852803e3592ab29830fe3865f2f1421cf910c8ce7f16d92ef6e0f9`
- Clean-oracle SHA-256:
  `17e34e465a1a8c3220c52bdedc3a84436ba76280b3ff84ac1a456d95f9c5723a`
- Agreement: 4,194,260 / 4,194,304 blocks (`99.998951%`)

All 44 differences are inside `x = 212..220`, `y = 9..15`, and
`z = 137..143`. The material-pair totals are `12 -> 0` x22 and `0 -> 12`
x22: sand and air respectively. Thus the difference is material-count
balanced: its 22 original-side sand cells lie above `y = 15`, while its 22
clean-side sand cells lie at `y = 15`. The first difference is at `(220, 9,
142)`, offset `1252572`,
`12 -> 0`.

This compact pattern is compatible with a falling-material update being
delivered in one field but not the other. It does not prove that a tree
notification, a fall-destination rule, or even the tree stage is the root
cause: divergent private state can first become block-visible later.

The complete 44-cell record, material-pair totals, and bounding box are in
`cases.jsonl`.

## Controls

All seven other random campaign cases with the primary's exact dimensions
match after independent final-field reproduction:

| Source label | Seed | Shared SHA-256 |
| --- | ---: | --- |
| `random:288` | `-8453671577739035615` | `0ad27ccf638155b41a419dc8b4af15202941d3319259c4a324a6bf9fc89414a6` |
| `random:370` | `2482827119618832744` | `bcdab1820f0ab37f1aed1202c075ff7a03c7d036e1c060020ec0a4ea5b570395` |
| `random:731` | `951415749596436621` | `9b48302694405f7c40b46e8bb7d0ff55a41c27e1ef4210d9779d8ba311ea86a0` |
| `random:936` | `-7765956029709489057` | `034d112a5df9798718e566b79d095e6d565af4901f5c2241619e6e43833ea300` |
| `random:1156` | `5003935218026383510` | `2d0fd09a3527c02c783f07665e9f7f5d8314b32dbb207bdec7a1824188efbdcc` |
| `random:1162` | `5571695012812640521` | `638874e4e2b25354234149cdf4c4bf4e2de28a61952e01af7af6eb35e4d59e4e` |
| `random:1197` | `5200496305978968986` | `b926f302bfc919fdff30ce06e8b74dbe867369f0ee0ce4e6bf529df353f2e3e2e` |

Every fixed-corpus case matched in the campaign. Two retained controls cover
the previous residual and a larger fixed shape:

| Source label | Seed | Dimensions | Shared SHA-256 |
| --- | ---: | --- | --- |
| `regression:v3` | `-5759849079018667514` | `512 x 16 x 512` | `d0ad4513f16723b6d08ca659d4a06d0dabb49ed75f4b14bbdc25fce6251e4ea4` |
| `shape:512x128x512` | `12345` | `512 x 128 x 512` | `85020bcafbad4067ce6510b10180a3738e86437c3bc6d2c5b39c27458abb3f00` |

The controls constrain this residual but do not identify a threshold, a tree,
or a formula. They are retained in `cases.jsonl` for direct replay.

## Clean-side diagnostic context

`oracle-stage-sha256.txt` gives the clean field SHA-256 at the twelve existing
logical boundaries for the primary case. Every digest covers exactly 4,194,304
bytes in the stated array layout; no stage arrays are included. The
`11_trees.blocks` digest equals the primary clean final hash.

Matching through a boundary localizes block-visible agreement only. In
particular, matching through `10_mushrooms.blocks` does not prove equality of
unpublished generator state or a terrain condition whose first visible effect
is in a tree placement.

## Requested original-side analysis and correction

1. Reproduce the primary original final SHA-256 with the black-box harness.
2. Privately capture exactly the twelve named block-field boundaries and
   compare their SHA-256 values with `oracle-stage-sha256.txt`. Do not publish
   either side's arrays or private traces.
3. Follow the first divergent boundary rather than the final materials:
   - If any boundary through `10_mushrooms.blocks` first differs, investigate
     that actual stage and treat the final sand pattern as downstream evidence.
   - If `00_soil.blocks` first differs, prioritize terrain, numeric conversion,
     and initial material placement before a tree-specific theory.
   - If `11_trees.blocks` first differs after all earlier fields match,
     privately audit the v4 notification semantics: lattice bounds, the stated
     neighbor order, reactive sand/gravel recognition, passable materials,
     fall destination, update ordering, and notifications from tree base,
     canopy, and trunk placement. Determine which original-side rule explains
     the 22-cell sand relocation while preserving the controls.
4. Validate a general rule against the primary, all seven same-shape controls,
   the matching v3 regression, and the fixed large-shape control. Do not add a
   seed-, coordinate-, or dimension-specific exception.
5. Publish only the smallest complete mathematical clarification in `spec/`
   after private original-side evidence establishes the rule. Then request a
   fresh differential run that includes the primary and retained controls.

The clean implementation should not be inspected to resolve this report. A
final-field mismatch is a request for a mathematical specification correction
or clarification, not permission to derive behavior from the implementation.

## Files

- `cases.jsonl`: machine-readable primary and control final-field records.
- `oracle-stage-sha256.txt`: one-way clean-oracle checksums for the primary
  field at the twelve logical boundaries.
