# Fuzzer v2

This is the persistent, parallel burn-in successor to the legacy JSONL fuzzer.
It intentionally has no runtime dependency on `fuzzer/`; old campaigns remain
replayable with the old tool.

Each lane holds one long-lived worker for each oracle, but generates oracle A
then oracle B sequentially. Thus `--jobs 384` uses at most 384 active world
generations while retaining 384 worker pairs. The runner creates a SQLite
campaign database and a generated `result.txt` in the requested campaign
directory.

Run an exact deterministic campaign:

```sh
python3 fuzzer_v2/fuzzer.py \
  --campaign-dir results/v2-smoke \
  --random-cases 10000 --rng-seed 20260805 --jobs 384 \
  --oracle-a-worker 'ORIGINAL_WORKER_COMMAND' \
  --oracle-b-worker 'REFERENCE_WORKER_COMMAND'
```

Run a twelve-hour soak instead:

```sh
python3 fuzzer_v2/fuzzer.py \
  --campaign-dir results/v2-burnin \
  --duration 12h --jobs 384 \
  --oracle-a-worker 'ORIGINAL_WORKER_COMMAND' \
  --oracle-b-worker 'REFERENCE_WORKER_COMMAND'
```

`--jobs` defaults to the process's schedulable logical CPU count. Startup is
staged at 32 lanes by default; use `--startup-parallelism` only when the host
can safely launch more workers at once. Each lane keeps one reusable comparison
file; set `--scratch-dir` to a fast local filesystem rather than a constrained
or memory-backed `/tmp` when running hundreds of lanes.

The runner stops on the first mismatch or oracle/infrastructure error, records
the terminal state, and writes `result.txt`. Interrupted campaigns can resume
with the same immutable arguments plus `--resume`; random cases are derived
independently from the campaign RNG seed and index.

Render a summary again after inspection or a resumed run:

```sh
python3 fuzzer_v2/summarize.py results/v2-burnin/campaign.sqlite \
  --output results/v2-burnin/result.txt
```

See [ORACLE.md](ORACLE.md) for the worker framing contract.

`fuzzer_v2/smoke_worker.py --worker 'COMMAND'` checks a persistent worker's
known seed-zero hash before and after an intervening request. `just
worker-smoke` runs that check and the full fixed corpus against two workers.
