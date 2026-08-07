# Clean differential handoff for Human 2 — v5 residual

This package contains compact final-field compatibility evidence and one-way
clean-stage checksums. It contains no raw block arrays, stage dumps, PRNG
states, heightmaps, decompiled material, or implementation source.

## Provenance

- v5 persistent differential report:
  `results/spec-v5-impl-v5/fuzz-v2-2026-08-06-32c-5m/campaign.sqlite`
- Campaign run ID: `b2303b83-a928-42cf-9952-acf79e2840ac`
- Handoff workspace/result commit: `286ef311de5005606fc6a435028e893dce1f9b7b`
- Behavioral specification revision exercised by v5:
  `34c00e6f4bbd6d047c5104766c0b1a9251d0aa3c`
- Clean oracle used for final-field reproduction and stage checksums:
  `7ca26d8002c9593de328f4e204f0e5a8a379166a`
- Harness image used for final-field reproduction:
  `sha256:eeffeb5451ea91d31c85357a2205fed7393ff1a60dcaeaa406f9eb680eee38eb`
- Original JAR SHA-256:
  `06b15435d2b4bcfa032f9ddc9feefd20c62609eaa68b46ec59bacd097e87fb55`
- Reproduced: 2026-08-06
- Array layout: `x + width * (z + depth * y)`
- Difference arrows below are `original JAR -> clean oracle`.

The stored campaign uses generator version `sha256-counter-v1`, protocol
version 2, replay RNG seed `20260805`, and fixed-corpus digest
`fbb00c2aea27d7c36d6a09ba40a618e3d70412e27ba3d19cb793b528e6708adb`.

## Campaign result

The v5 fuzzer-v2 run used 32 persistent worker lanes and had a 300-second
random-phase budget. It stopped on the first mismatch after 90.7 seconds of
wall time (77.291 seconds of recorded random-phase elapsed time), so it is
finite compatibility evidence, not a completed five-minute campaign.

It recorded 2,906 final fields: 15 fixed and 2,891 random. Of those, 2,905
matched exactly, one mismatched, and none had oracle errors. The run compared
4,715,991,040 blocks with two differing blocks, yielding `99.999999958%`
volume-weighted agreement. The mismatch field has `99.999994%` agreement.
The fuzzer's six-decimal summary rounds the volume-weighted figure to
`100.000000%`.

The v5 specification revision establishes that a non-air placement into air
delivers axis-neighbor notifications. The residual's two flowing-water to
still-water transitions are relevant to observable mutation semantics, but do
not establish their cause, the first divergent stage, or a tree connection.
Follow the stage hashes before revising any declaration.

## Primary counterexample

- Fuzz source label: `random:2519`
- Seed: `-8582786655062038843`
- Dimensions: `512 x 128 x 512` (33,554,432 blocks)
- Original SHA-256:
  `0311cda8bc1a595090fd9f2ab6354645f6cec446ee6724f2b770e2c6b59c8da4`
- Clean-oracle SHA-256:
  `67cfe9da2eb4d60d4ea8e46f7a990121a1242778f6d5cf498c806302c814ca8a`
- Agreement: 33,554,430 / 33,554,432 blocks (`99.999994%`)

Both differences are at `y = 63`, `z = 308`, and `x = 453..454`. Each is
`8 -> 9`: flowing water to still water. The first difference is at
`(453, 63, 308)`, offset `16673221`. The complete two-cell record,
material-pair total, and bounding box are in `cases.jsonl`.

This compact final pattern is compatible with a difference in source placement,
water conversion, notification delivery, or an earlier state that becomes
block-visible later. It proves none of those theories. In particular, a
water-state pair does not identify a water-stage cause without the boundary
checksums.

## Controls

All fourteen other random campaign cases with the primary's exact dimensions
match after independent final-field reproduction:

| Source label | Seed | Shared SHA-256 |
| --- | ---: | --- |
| `random:316` | `-3630163334818087112` | `c86f8c163f285f976f02c7b782b1087e11247df0f0f72f2a72013a38f1e39284` |
| `random:530` | `-532555655530160895` | `abd353206038aca92eebad302e8e914327f54d3f0c2da98433305250388b69d8` |
| `random:768` | `7098449994346949500` | `e7e3cdf2e8487fe9c753691bc5f3b510075564c568ca0410aef53a6d0827c36a` |
| `random:791` | `-6894755787069084568` | `5c66fde24727f1a241dd5e85f41439144c787d39c222e8de0b61ebc3f328a8b6` |
| `random:912` | `1353863354273449212` | `b3c379e05b2b491bf169245b01b3843400f5b18f8d558d02631e9a27536b32a6` |
| `random:1292` | `-168785751923401411` | `e18818c398885fc69fb08e45f085560d0009e87ae20f8ef9ebc7b3f6c87d4f90` |
| `random:1398` | `4200743752265103596` | `60ba581cf81c88c567d867da3f88bc849e0d682217c8473037f985846e50fe63` |
| `random:1723` | `5826253211324590000` | `bc3b8ac1c6097f11f9baa751fb870949175976a90bf39d628f82afb1c1b3a8db` |
| `random:1927` | `7348205493147265700` | `7fcacb7b84fe570d46c931f7628c7ecaec9f2ee330ee5e10b554e2b968237f52` |
| `random:1932` | `6333744131665969294` | `e7b238bbb802c5108d9aafaa7dcfe671394358fcdd88f93cab578dc662c5daff` |
| `random:2027` | `-1089607889929291041` | `4f8392a150ad94aa0e7a373fa1da625648f2621de5a80e30fae48ee2bc3a5d85` |
| `random:2309` | `-4693082445771546` | `7570ba072c541a2e1b61cbb490b11d6fc256f708f6609e739b985d550c27f0af` |
| `random:2349` | `3855673719764931429` | `2448786f259600a84c03ac054a21109e1b72ba38fa46b49f7cba6769120178b5` |
| `random:2480` | `-2707918288600355752` | `3d15b4479c878db38a976bb0ad6572ed1605723831cbafc8ff0752b78c233c54` |

Every fixed-corpus case matched in the campaign. Three retained controls cover
the previous v4 residual, the v3 regression, and the fixed large shape:

| Source label | Seed | Dimensions | Shared SHA-256 |
| --- | ---: | --- | --- |
| `random:1396` | `-486299723741911703` | `512 x 32 x 256` | `fd6707e443852803e3592ab29830fe3865f2f1421cf910c8ce7f16d92ef6e0f9` |
| `regression:v3` | `-5759849079018667514` | `512 x 16 x 512` | `d0ad4513f16723b6d08ca659d4a06d0dabb49ed75f4b14bbdc25fce6251e4ea4` |
| `shape:512x128x512` | `12345` | `512 x 128 x 512` | `85020bcafbad4067ce6510b10180a3738e86437c3bc6d2c5b39c27458abb3f00` |

The controls constrain the residual but do not identify a condition, a pass, or
a formula. They are retained in `cases.jsonl` for direct replay.

## Clean-side diagnostic context

`oracle-stage-sha256.txt` gives the clean field SHA-256 at the twelve existing
logical boundaries for the primary case. Every digest covers exactly
33,554,432 bytes in the stated array layout; no stage arrays are included. The
`11_trees.blocks` digest equals the primary clean final hash.

Matching through a boundary localizes block-visible agreement only. In
particular, matching through `04_gold.blocks` does not prove equality of
unpublished random state or terrain conditions that are first consumed by a
later fluid, surface, flora, or tree pass.

## Requested original-side analysis and correction

1. Reproduce the primary original final SHA-256 with the black-box harness.
2. Privately capture exactly the twelve named block-field boundaries and
   compare their SHA-256 values with `oracle-stage-sha256.txt`. Do not publish
   either side's arrays or private traces.
3. Follow the first divergent boundary rather than the final material pair:
   - If `00_soil.blocks` first differs, prioritize terrain, numeric conversion,
     and initial material placement.
   - If a cave or ore boundary first differs, investigate its trajectory,
     random-state, and conversion semantics before fluid hypotheses.
   - If `05_boundary_water.blocks`, `06_inland_water.blocks`, or
     `07_lava.blocks` first differs, audit the actual source order,
     reachability, flowing/still conversion, reaction, overwrite, and
     notification timing in that stage.
   - If a later surface, flora, or tree boundary first differs, investigate
     that actual stage. If only `11_trees.blocks` differs, privately audit the
     v5 changed-placement and axis-neighbor notification semantics alongside
     tree placement order; do not infer that this water pair proves a tree
     cause.
4. Validate a general rule against the primary, all fourteen same-shape
   controls, the matching v4 residual, the matching v3 regression, and the
   fixed large-shape control. Do not add a seed-, coordinate-, or
   dimension-specific exception.
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
