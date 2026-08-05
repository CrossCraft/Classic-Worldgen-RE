# Classic Worldgen RE

A two-author clean-room effort to produce a byte-identical specification and
pure reference implementation of Minecraft Classic (c0.30-era) world
generation.

The project treats the original server as a black box: a signed 64-bit seed and
level dimensions go in, and the generated block array comes out. The eventual
oracle will reproduce that array without containing or depending on Mojang code.

## Project status

- **Harness:** operational
- **Formal specification:** v4 exercised by the latest convergence campaign
- **Legacy differential fuzzer:** operational, with a replayable fixed corpus
  and JSONL reports
- **Burn-in fuzzer v2:** persistent workers, CPU-parallel lanes, SQLite
  campaigns, and generated summaries
- **Reference oracle:** v4 exercised against the black-box oracle
- **Accuracy claim:** 100% agreement in the latest bounded campaign; long-term
  validation is still pending
- **Next phase:** 12-hour long-term differential analysis on the target host

## The experiment

The initial v1 specification was produced in approximately 90 minutes of
active work by a human-supervised LLM agent loop. Subsequent convergence
revisions were driven by differential results while preserving the clean-room
boundary. The wider project uses two human supervisors and separate agent
loops to explore whether formal, non-executable specifications, strict
information boundaries, and human review can make agent-assisted clean-room
reverse engineering both rapid and independently reproducible.

The agents are used to preserve specialization rather than collapse the two
roles into a source-rewriting pipeline: one agent loop studies and formalizes
the original generator, while the other implements from the published
specification without receiving the original analysis material. The loops 
are ran by two different humans so no spillover knowledge exists.

## Goals

- Document the generator as a precise mathematical specification.
- Implement that specification in a pure language such as Haskell.
- Compare the reference implementation against the original generator across a
  large seed corpus.
- Publish reproducible hashes and compact mismatch reports, never original code
  or intermediate generation data.

Byte-for-byte compatibility matters because small differences in random-number
consumption, floating-point evaluation, noise construction, bounds handling, or
integer conversion can change the final world.

## Differential results

The latest bounded campaign, v4, ran for 600 seconds with replay RNG seed
`20260805`. It covered 633 cases — 15 fixed edge, shape, and regression cases
plus 618 random cases — and compared 1,018,912,768 blocks. All 633 cases
matched exactly, with zero mismatches and zero oracle errors. The full
[human-readable summary](results/spec-v4-impl-v4/result.txt),
[JSONL campaign report](results/spec-v4-impl-v4/fuzz-2026-08-05.jsonl), and
[fixed-corpus report](results/spec-v4-impl-v4/fixed-corpus-2026-08-05.jsonl)
are checked in for replay and review.

This is evidence of convergence on the exercised corpus, not a proof of
equivalence for every valid seed and dimension combination. The next phase is
long-term differential analysis, which has not yet run. It will extend testing
across independent replay seeds and dimensions, retain compact reports and
failure records, and repeatedly include the fixed regression corpus.

## Long-term burn-in (v2)

[`fuzzer_v2/`](fuzzer_v2/README.md) is a strict fork of the original JSONL
fuzzer for long-lived, multi-core campaigns. It starts a persistent worker for
each oracle in every lane, sends raw block arrays through a framed binary
protocol, and records compact per-case facts in a SQLite campaign database.
The legacy `fuzzer/` interface and all published JSONL reports remain intact.

The v2 runner defaults to all schedulable logical CPUs (384 on the target
host), while generating oracle A and oracle B sequentially within each lane so
that this is also the maximum number of active world generations. A campaign
must explicitly choose either a duration or exact random-case budget; it stops
on the first mismatch or worker error and writes a deterministic `result.txt`.

```sh
python3 fuzzer_v2/fuzzer.py \
  --campaign-dir results/v2-burnin \
  --duration 12h --jobs 384 \
  --oracle-a-worker 'ORIGINAL_WORKER_COMMAND' \
  --oracle-b-worker 'REFERENCE_WORKER_COMMAND'
```

See [`fuzzer_v2/ORACLE.md`](fuzzer_v2/ORACLE.md) for the persistent worker
contract and `just worker-smoke` for an original-versus-original protocol
smoke test.

## Clean-room model

The work and authorship are split between two independent roles:

- **Harness and oracle:** Maintains this repository, operates the original JAR
  only through the black-box harness, and implements the reference oracle solely
  from the published specification.
- **Analysis and specification:** Privately studies the original generator and
  publishes only a self-contained mathematical specification. This role does not
  write the reference implementation.

Only the specification, independent oracle code, test vectors, and compact
failure records cross that boundary. Decompiled sources, instrumented binaries,
stage dumps, and analysis logs do not belong in this repository.

Each role is staffed by one human driving an AI agent loop: two people total,
each directing an LLM agent that does the hands-on work (harness operation and
oracle implementation on one side, reverse engineering and formalization on
the other) under human oversight. The boundary above is enforced by keeping
the two agent loops separate and letting only the published artifacts cross.

The harness required limited reverse-engineering of the original server solely 
to locate the seed and dimension injection points and to extract the final 
block array. The reference oracle is implemented exclusively from the published
mathematical specification and does not incorporate any knowledge of the 
original generation algorithm obtained during harness construction.

This separation also permits third parties with no exposure to the original JAR
or harness internals to produce independently clean implementations from the
published specification.

## Harness

The current harness supports the Minecraft Classic server 1.10 JAR shape. A
narrow Java agent injects the requested seed and dimensions while classes load;
it rejects JARs whose expected patch sites do not match. The supplied JAR is
mounted read-only and is never copied into the image or modified on disk.

The Java bridge returns the generated `byte[]`. Python handles subprocess
isolation, optional repeatability checks, raw extraction, hashing, and JSON
output. A verification run checks both a repeated seed and the adjacent seed as
a control.

## Requirements

- Docker
- A legally obtained compatible Classic server JAR
- Optional: [`just`](https://github.com/casey/just) for the convenience recipes

The JAR is not included. Place it at `./classic.jar` or configure another path
with `CLASSIC_JAR`.

## Usage

Build the image and generate a world:

```sh
just build
just run 12345
```

Dimensions are ordered as width, vertical height, and horizontal depth. They
default to `256 64 256` and can be supplied after the seed:

```sh
just run 12345 128 64 128
```

Each dimension must be a power of two and at least 16. The total volume must fit
in a Java array. A successful run emits one JSON object:

```json
{"seed":12345,"width":256,"height":64,"depth":256,"sha256":"823a2139e9a41e0b00c617eb5050ae73d4899f2275a3ec29a99a67eccb1a7f0a"}
```

Other useful recipes are:

```sh
just verify 12345                 # Check repeatability and an adjacent seed
just composition 12345           # Count block IDs and sanity-check materials
just extract 12345 level.blocks  # Write the raw block array under ./out
just smoke                       # Build and run the default verification
just test                        # Run the Python unit tests in the image
just                             # List every recipe
```

`just composition` defaults to seed `12345`. Its JSON includes every block ID
present (with its symbolic name, count, and percentage), plus combined water,
dirt, stone, grass, logs, leaves, lava, and ore groups. It exits unsuccessfully
when those groups fall outside deliberately broad, dimension-normalized bounds.

The recipes recognize these environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CLASSIC_JAR` | `./classic.jar` | Source JAR mounted read-only at runtime |
| `CLASSIC_HARNESS_IMAGE` | `classic-worldgen-re` | Docker image name |
| `CLASSIC_OUT_DIR` | `./out` | Raw extraction directory |

To use Docker directly:

```sh
docker build -t classic-worldgen-re .
docker run --rm \
  --mount type=bind,source=/absolute/path/to/classic.jar,target=/harness/classic.jar,readonly \
  classic-worldgen-re --seed 12345
```

## Roadmap

- [x] Dockerized black-box harness with controlled seed injection
- [x] Raw block-array extraction and repeatability verification
- [x] Mathematical specification of the full generation pipeline (Lean 4)
- [x] Differential fuzzer with a fixed corpus and replayable JSONL reports
- [x] Persistent SQLite-backed v2 burn-in fuzzer and original-worker smoke test
- [x] Reference oracle exercised from the published specification
- [x] Published v1–v4 differential reports and fixed corpus
- [ ] Long-term differential analysis / soak testing

## Specification

The specification covers the full generation pipeline. `spec/` holds its Lean
4 formalization, one module per stage:

- `Spec/Random.lean` — the 48-bit LCG state, seed initialization, and the
  derived semantics of bounded and unbounded draws
- `Spec/Noise.lean` — the shuffled permutation, fade curve, gradient
  interpolation, and octave summation
- `Spec/Terrain.lean` — the elevation heightfield, strata placement, and
  sea-level filling
- `Spec/Carve.lean` — cave count, trajectories, and shape rules
- `Spec/Ore.lean` — coal, iron, and gold vein counts, depth ranges, and
  growth
- `Spec/Level.lean` — surface passes, flowers, mushrooms, trees, and the
  end-to-end pipeline ordering

It contains only axioms, opaque constants, type declarations, and property
theorems -- no evaluable code, no comments -- and builds green via
`just spec-build` with no outstanding `sorry`s. The authoring rules are in
`spec/README.MD`. The specification is intentionally non-executable: it is the
formal communication boundary between the analysis author and implementation
author. Ambiguities discovered while implementing and fuzzing are resolved by
revising the specification, not by exposing the implementation author to the
original generator.

## Agent loop

Role 2 (analysis and specification) runs as an LLM agent loop with user
oversight:

- `prompt/AGENTS.md` is the agent's system prompt: the Role-2 identity, hard
  rules (never commit/push/PR; all work left unstaged), and the working loop.
- `prompt/GOALS.md` holds the staged roadmap. Each stage is a ready-to-paste
  `/goal` block; the user assigns one stage at a time.
- `dirty/` is the agent's git-ignored workspace for RE artifacts, dumps, and
  running notes (`dirty/NOTES.md`). Nothing in it can be committed.
- `spec/` is the only clean deliverable: Lean 4 axioms, opaque constants, and
  property theorems -- no evaluable code, no comments. The full rule set is in
  `spec/README.MD`.

The harness image ships a pinned Lean toolchain (installed via elan in the
Dockerfile, matching `spec/lean-toolchain`). Spec recipes:

```sh
just spec-build  # Build the Lean spec in the harness image
just spec-shell  # Interactive shell in the image with spec/ mounted
```

## Legal

This repository is intended for interoperability and archival research. It does
not distribute Minecraft binaries, decompiled sources, or other copyrighted game
assets. Users must supply their own compatible JAR.
