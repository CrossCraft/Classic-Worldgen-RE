# Role 2 — Goal Stages

Standing rules:

- Exactly one stage is active at a time. The user assigns it via `/goal`.
- Stage order follows the presumed c0.30 generation pipeline; revise the
  stages if reverse engineering reveals a different order.
- Every stage ends with `just spec-build` green, `dirty/NOTES.md` updated,
  and all changes unstaged.

Copy the block for the assigned stage into `/goal`.

---

## Stage 0 — Harness instrumentation

```
/goal Instrument the Java harness to capture intermediate generation values
(raw java.util.Random draws, noise octave inputs/outputs, and other internal
formula inputs) into dirty/dumps/ as JSON or binary dumps per seed.
Completion: `just run 12345` (or a dedicated flag) produces a dump file under
dirty/dumps/, and `just smoke` still passes. All changes left unstaged.
```

## Stage 1 — PRNG spec

```
/goal Formalize Java's java.util.Random in spec/Spec/Random.lean as axioms
and property theorems: the 48-bit LCG state, seed unscrambling (seed XOR
multiplier, masked), next(bits), and the derived semantics of nextInt (with
and without bound), nextFloat, and nextDouble. No evaluable code, no
comments. Completion: `just spec-build` is green.
```

## Stage 2 — Noise spec

```
/goal Formalize the generator's noise construction in spec/Spec/Noise.lean:
the permutation/hash derived from Random, the fade curve, gradient selection
and interpolation, and octave summation (frequency doubling, amplitude
halving), matching the dumps captured in Stage 0. Axioms and property
theorems only. Completion: `just spec-build` is green and dirty/NOTES.md
records how the axioms were validated against dumps.
```

## Stage 3 — Heightfield & base terrain

```
/goal Formalize elevation and base terrain in spec/Spec/Terrain.lean: how
noise octaves combine into the heightfield, stone/dirt/grass vertical
placement, and water/lava filling to sea level. Axioms and property theorems
only. Completion: `just spec-build` is green; stated properties are
consistent with `just composition` output for at least three seeds.
```

## Stage 4 — Carving & ores

```
/goal Formalize cave carving and resource distribution in spec/Spec/Carve.lean
and spec/Spec/Ore.lean: cave count, trajectory, radius and shape rules; ore
vein counts, size, and depth distribution; gravel and sand pockets. Axioms
and property theorems only. Completion: `just spec-build` is green; vein
counts and depth ranges match harness dumps for at least three seeds.
```

## Stage 5 — Surface, plants & assembly

```
/goal Formalize the remaining passes and full pipeline ordering in
spec/Spec/Level.lean: grass spreading, flowers and mushrooms, tree placement
attempts and shape, and the axiomatized end-to-end pipeline order from seed
to final block array. Completion: `just spec-build` is green; the axiom set
covers every block ID reported by `just composition` across a multi-seed
corpus, with cross-checks recorded in dirty/NOTES.md.
```
