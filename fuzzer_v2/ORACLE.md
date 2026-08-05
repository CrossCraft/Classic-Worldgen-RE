# Persistent worker oracle contract (v2)

`fuzzer_v2/` is a separate long-running fuzzing system. It does not alter the
one-shot CLI in `fuzzer/ORACLE.md`.

## Lifecycle

The runner starts one process for each oracle in each worker lane. The command
is supplied verbatim through `--oracle-a-worker` or `--oracle-b-worker`; an
optional `{worker}` placeholder expands to the zero-based lane number. A worker
must process requests serially and must not write ordinary logs to stdout.

The worker receives ASCII control lines on stdin and emits ASCII headers plus
raw block bytes on stdout. Standard error is reserved for human diagnostics.
Every control line is terminated by a single LF (`\n`), with fields separated by
one ASCII space.

```text
worker -> runner: READY 2
runner -> worker: CASE ID SEED WIDTH HEIGHT DEPTH
worker -> runner: OK ID BYTE_COUNT
worker -> runner: BYTE_COUNT raw bytes
runner -> worker: QUIT
worker -> runner: BYE
```

`ID` is a nonnegative decimal request identifier. It is echoed unchanged.
Exactly one `CASE` may be in flight per worker. On a recoverable request error,
the worker writes `FAIL ID` and a diagnostic to stderr. The v2 runner treats a
failure, malformed header, premature EOF, unexpected byte count, timeout, or
worker exit as a campaign-fatal oracle error.

The worker must flush `READY`, `OK`, `FAIL`, and `BYE` before waiting for more
input. Its stdout contains no banner, JSON, logging, ANSI escape sequence, or
other data outside this framing.

## Inputs and result bytes

The seed and dimension domain is identical to v1:

| Field | Requirement |
| --- | --- |
| `SEED` | signed 64-bit integer |
| `WIDTH`, `HEIGHT`, `DEPTH` | power of two, at least 16 |
| volume | `WIDTH * HEIGHT * DEPTH <= 2^31 - 1` |

An `OK` response's byte count must equal the volume. The immediately following
raw bytes are one unsigned block ID per cell in layout
`x + width * (z + depth * y)`. The runner compares every byte and never stores
raw output in its result database.

For every request, a worker must behave like a fresh v1 invocation with the
same five inputs. It may reuse its process, loaded code, and immutable caches,
but may not leak mutable generation state between requests.

## Included original-JAR worker

The Docker image builds
`org.crosscraft.classicworldgen.PersistentClassicHarness`, which implements this
protocol. It is intentionally a new class; the existing Python and one-shot
Java harness remain v1-only.

An original-worker launch template is:

```sh
docker run --rm -i \
  --mount type=bind,source=/absolute/path/to/classic.jar,target=/harness/classic.jar,readonly \
  --entrypoint java classic-worldgen-re \
  -javaagent:/opt/classic-harness/classic-harness.jar \
  -cp /opt/classic-harness/classic-harness.jar:/harness/classic.jar \
  org.crosscraft.classicworldgen.PersistentClassicHarness --serve
```

Do not add `-t`: a terminal can transform the binary payload. Operators may add
Docker CPU and memory limits appropriate to their host.
