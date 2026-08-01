# Classic Worldgen RE

A clean-room effort to produce a byte-identical specification and pure reference
implementation of Minecraft Classic (c0.30-era) world generation.

The project treats the original server as a black box: a signed 64-bit seed and
level dimensions go in, and the generated block array comes out. The eventual
oracle will reproduce that array without containing or depending on Mojang code.

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

## Clean-room model

The work is split between two independent roles:

- **Harness and oracle:** Maintains this repository, operates the original JAR
  only through the black-box harness, and implements the reference oracle solely
  from the published specification.
- **Analysis and specification:** Privately studies the original generator and
  publishes only a self-contained mathematical specification. This role does not
  write the reference implementation.

Only the specification, independent oracle code, test vectors, and compact
failure records cross that boundary. Decompiled sources, instrumented binaries,
stage dumps, and analysis logs do not belong in this repository.

The harness required limited reverse-engineering of the original server solely to locate the seed and dimension injection points and to extract the final block array. The reference oracle is implemented exclusively from the published mathematical specification and does not incorporate any knowledge of the original generation algorithm obtained during harness construction.

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
- [ ] Differential fuzzer
- [ ] Mathematical specification and pure reference oracle
- [ ] Published test corpus and continuous soak testing

## Legal

This repository is intended for interoperability and archival research. It does
not distribute Minecraft binaries, decompiled sources, or other copyrighted game
assets. Users must supply their own compatible JAR.
