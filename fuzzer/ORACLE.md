# Oracle CLI contract

The differential fuzzer drives two generators through one uniform interface:

- the original JAR, via the black-box harness (`run_harness.py`), and
- the reference oracle, implemented purely from `spec/`.

Anything that satisfies this contract can be plugged in as a fuzz target. The
contract is deliberately a subset of what `run_harness.py` already provides,
so the original-JAR side needs no adapter.

## Invocation

```sh
oracle --seed SEED --width W --height H --depth D --blocks-out PATH
```

All five flags are required.

| Flag | Type | Constraints |
| --- | --- | --- |
| `--seed` | signed 64-bit integer | must fit a Java `long` |
| `--width` | integer | power of two, at least 16 |
| `--height` | integer | power of two, at least 16 |
| `--depth` | integer | power of two, at least 16 |
| `--blocks-out` | file path | created or overwritten by the oracle |

`width * height * depth` must not exceed 2^31 − 1 (Java's maximum array
length). These constraints mirror `run_harness.py`'s validation exactly; the
fuzzer never generates inputs outside this domain.

## Output format

On success the file at `PATH` contains exactly `width * height * depth`
bytes: one unsigned byte per block, the block ID (0–49). The byte at offset

```
x + width * (z + depth * y)
```

holds the block at coordinates `(x, y, z)`, with `y` vertical (`0` at the
bottom of the level). This is the layout of the original `Level.blocks`
array, which the harness already dumps verbatim, so `just extract` output
conforms to this contract today.

The raw array is the only output the fuzzer compares. Two oracles agree on an
input if and only if their files are byte-identical; the offset of the first
mismatch maps back to `(x, y, z)` via the formula above.

## Exit codes and streams

- `0` — success; the output file is complete.
- `1` — generation or runtime failure; a human-readable message goes to
  stderr.
- `2` — invalid arguments (the argparse/getopt convention).

On a non-zero exit the fuzzer discards whatever the oracle wrote. stdout is
unspecified and the fuzzer ignores it — `run_harness.py` prints its JSON
summary there, which is fine, but no target may rely on stdout being read.

## Determinism

For identical arguments an oracle must produce a byte-identical file, across
repeated invocations, processes, and machines. World generation may depend
only on the five inputs above: no ambient randomness, wall-clock time,
locale, or environment state beyond documented variables.

## Why a file, not stdout

Level arrays run from 16 KiB to just under 2 GiB. A file keeps the interface
trivial for implementations in any language (the Java harness already does
`Files.write`), lets the fuzzer hash or diff without holding the level in
memory twice, and keeps stdout free for diagnostics. The fuzzer hands each
invocation a fresh path inside its own workspace.

## Conformance

- Original JAR: `python3 run_harness.py --seed S --width W --height H --depth D
  --blocks-out P` (inside the harness image, with `classic.jar` mounted)
  satisfies this contract as-is.
- Reference oracle: expose the same flags and file semantics in whatever
  language it is written in.

## Non-goals

- One process per level. JVM startup makes the original side slow; a batch or
  long-lived server mode is a possible later extension, not part of v1.
- No intermediate generation data crosses this interface. Dumps stay in
  `dirty/` on the analysis side; the fuzzer sees only final block arrays.
