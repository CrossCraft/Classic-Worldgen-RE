# Classic-Worldgen-RE

Clean-room reverse engineering effort aimed at producing a **byte-identical** mathematical specification and pure reference implementation of Minecraft Classic (c0.30-era) world generation.

The goal is a deterministic `seed -> block array` oracle that matches the original generator exactly, expressed in clean mathematical language and a pure implementation (e.g. Haskell or equivalent), without distributing any original Mojang bytecode or decompiled sources.

## Motivation

Existing reimplementations (including ClassiCube's documented algorithm) are believed to be close but not guaranteed byte-identical. Differences typically appear in:

- Exact `java.util.Random` consumption order
- Floating-point evaluation order and intermediate precision
- Noise table construction and gradient selection
- Bounds checks and edge handling inside cave/ore/plant placement
- Array layout and integer truncation behaviour

A verified pure oracle enables independent reimplementations, archival research, and deterministic testing.

## Clean-Room Methodology

The project deliberately separates two roles to keep the final artifacts clean:

### Human 1 - Harness, Verification & Oracle Implementation (this repository)
- Designs and maintains the black-box harness
- Builds the Docker environment
- Implements minimal seed injection into the original `Random` (reflection or targeted bytecode rewrite of the construction site only)
- Extracts the final block byte array from the generated level
- Owns the differential fuzzer
- **Implements the Haskell reference oracle** purely from the mathematical specification written by Human 2
- Never reads or reasons about the generation algorithm itself beyond what the specification states -- never sees the original jar, decompiled sources, or stage dumps (noise, caves, ores, flooding, plants, etc.)

### Human 2 - Algorithm Analysis & Specification (private)
- Works with the original jar under controlled conditions
- Performs decompilation and deep analysis
- Produces the pure mathematical specification -- **this is Human 2's only public output**
- The specification must be extremely detailed and self-contained: the exact sequence of `java.util.Random` calls (in order, with argument values), the precise floating-point expressions (including every intermediate operation, literal, and cast), and the complete order of operations -- sufficient for Human 1 to implement a byte-identical oracle without ever seeing any original code
- Never implements or edits the reference oracle -- only updates the specification when a mismatch is diagnosed
- May temporarily instrument the harness for stage dumps (heightmap, post-carve, etc.)
- **Never publishes** decompiled sources, instrumented jars, stage dumps, or AI conversation logs that contain original code

This arrangement is true clean-rooming: the person who reads the original code (Human 2) writes only mathematics, and the person who writes the implementation (Human 1) has never seen the original code.

Only the following cross the boundary into the public repository:

- Pure mathematical description (authored by Human 2)
- Clean reference oracle source (implemented by Human 1 from the specification alone)
- Public test vectors and failure records (seed + sizes + hashes)
- The harness and fuzzer

## Architecture

```
+---------------------+         +----------------------+
|  Black-box Harness  |         |   Pure Oracle        |
|  (original jar +    |         |   (Haskell / pure    |
|   seed injection)   |         |    implementation)   |
+---------+-----------+         +----------+-----------+
          |                                |
          |  block[]                       |  block[]
          +------------+-------------------+
                       v
              +-----------------+
              | Differential    |
              | Fuzzer          |
              +--------+--------+
                       |
                       v on mismatch
              publish (seed, size, hashes)
                       |
                       v
          Human 2 diagnoses & updates
          the mathematical specification
                       |
                       v
          Human 1 updates the oracle
              to match the new spec
```

Human 1 owns the harness, the differential fuzzer, and the Haskell oracle implementation

Human 2 owns the RE and updates only the mathematical specification; Human 1 keeps the oracle in sync with it

### Harness responsibilities
- Accept `(seed: long, width, depth)`
- Force the original generator's `Random` to start with that seed
- Run generation
- Extract the raw block byte array from the resulting level file
- Emit a stable hash (and optionally the full array for small maps)

### Fuzzer workflow
1. Generate a stream of seeds (uniform random + adversarial edge cases).
2. Run both the black-box harness and the pure oracle.
3. On any byte-array mismatch, publish a compact failure record containing only the seed, dimensions, and hashes / first differing offset.
4. Human 2 pulls the seed, diagnoses privately, and lands a fix to the mathematical specification.
5. Human 1 updates the Haskell oracle to match the revised specification -- without learning anything about the original beyond what the spec states.
6. Re-test the failing seed plus a fresh batch.
7. Continue until a long soak (target: 24 hours wall-clock with zero mismatches) is achieved.

Human 1 can also run the fuzzer independently; communication is limited to "here is a failing seed" / "here is an updated specification".

## Environment

Everything targets Linux and is intended to run inside Docker for reproducibility and isolation.

The public image contains:
- A pinned JDK (Temurin 17 or 11)
- Minimal utilities needed for gzip / extraction
- The harness entry points and fuzzer
- **No** classic.jar (users must supply their own legally obtained copy)

Human 2 maintains a private extension of the same base image that adds decompilers and temporary instrumentation. Those layers are never published.

## What lives in this repository

- Dockerfiles and harness source (seed injection + block extraction)
- Differential fuzzer
- Public test corpus (known-good seed -> hash pairs)
- Pure mathematical specification (once available)
- Clean reference oracle source
- Failure records and soak-test logs

## What does **not** live in this repository

- Any original Mojang jar or class files
- Decompiled Java sources
- Instrumentations that dump intermediate generation stages
- AI prompts or logs containing original code
- Patches that modify generation logic rather than just Random construction

## Legal & Intent

This is a clean-room research effort focused on interoperability and archival understanding of an old, freely distributed client.

Users must supply their own copy of the relevant Classic jar. This repository does not distribute copyrighted binaries or decompiled sources. The published artifacts are intended to be independent clean-room results.

## Status

Early infrastructure phase.

- [ ] Public Docker harness with controllable seed injection
- [ ] Reliable block-array extraction
- [ ] Differential fuzzer skeleton
- [ ] First pure mathematical draft + reference oracle
- [ ] Continuous soak testing

## Getting started

1. Obtain a legitimate copy of the Classic client/server jar you wish to target. The jar is **never** baked into the image -- it is mounted at runtime.

2. Build the harness image:

   ```sh
   docker build -t classic-worldgen-re .
   ```

3. Mount the jar and run the harness with a chosen seed and size:

   ```sh
   docker run --rm \
     -v /path/to/classic.jar:/harness/classic.jar:ro \
     -v "$PWD/out:/harness/out" \
     classic-worldgen-re \
     python3 run_harness.py --seed 12345 --width 256 --depth 64
   ```

   (Harness CLI still under construction -- `run_harness.py` is currently a placeholder.)

4. Once a pure oracle is published, run the fuzzer against it.

---

Questions, failing seeds, or specification updates should be handled through the project's issue tracker or private channels between the two roles as appropriate. The public history should remain free of original code.
