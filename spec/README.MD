# Spec rules

This directory is the only clean deliverable of Role 2. It contains a formal
mathematical specification of Minecraft Classic world generation in Lean 4.
It must never contain anything resembling an evaluable world generator.

## Toolchain

- Lean 4, pinned by `lean-toolchain` (`leanprover/lean4:v4.32.2`). The same
  toolchain is installed in the harness Docker image.
- No external dependencies. No Mathlib, no Batteries.
- Build only via `just spec-build` from the repository root.

## What may appear in a `.lean` file

Permitted declarations:

- `axiom` — the rules themselves.
- `opaque` — primitive constants whose values are fixed but not computable
  here.
- `structure` / `inductive` — types only.
- `theorem` / `lemma` — properties of the axioms. While formalization is in
  progress a theorem may close with `sorry`; the build stays green with
  warnings.

Forbidden:

- `def`, `abbrev`, `instance`, or any declaration with computational content.
- `#eval`, `#reduce`, or any evaluation directive.
- Anything that reduces to a computable seed→level function.
- Comments of any kind: no `--`, no `/- -/`. Explanation belongs in
  `dirty/NOTES.md`, never in the spec.

## Naming

- Declarations are named after the mathematical object or its role in the
  generation pipeline (e.g. `multiplier`, `heightScale`, `beachThreshold`).
- Never reuse identifiers from the original program — no class, method, or
  field names, and no paraphrases that track them one-to-one. The private
  mapping from original identifiers to spec names lives in `dirty/NOTES.md`.
- Publicly documented Java standard library API names (e.g. `nextInt`,
  `nextBits` of `java.util.Random`) are acceptable: they denote published
  behavior, treated here as mathematical operations.
- File and namespace organization follows the mathematical pipeline
  (seed → noise → heightmap → ...), never the original program's class
  structure or call graph.

## Layout

- One file per pipeline stage under `Spec/` (e.g. `Spec/Random.lean`,
  `Spec/Noise.lean`).
- The root module `Spec.lean` imports every stage file and nothing else.
- `lakefile.lean` defines a single library `Spec`; it is build configuration,
  not specification.
