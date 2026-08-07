# v6 12-hour differential burn-in — 192c / 384t

This is the compact repository record for the completed persistent
Java-original versus `cl-wlgen` differential burn-in on a dedicated
192c / 384t host.
The campaign ran 384 persistent comparison lanes: each case generated one
world with each oracle and compared every block byte-for-byte.

## Result

- Status: complete (`exit_code=0`)
- Random-phase budget: 43,200 seconds (12 hours)
- Total runtime: 43,290.8 seconds
- Replay RNG seed: `7361593810424616585`
- Cases: 17,322,644 total — 15 fixed, 17,322,629 random
- Exact matches: 17,322,644
- Mismatches: 0
- Oracle errors: 0
- Blocks compared: 29,355,813,556,224
- Differing blocks: 0
- Mean throughput: 400.147 cases/sec and 678,108,217 blocks/sec

The 100% result is differential agreement with the original Java oracle, not
an independent proof of either implementation's correctness.

## Provenance

- Campaign run ID: `3376021a-f0c3-404c-9ab1-b324ddcd6be9`
- Campaign started: 2026-08-07T04:25:03Z
- Campaign finished: 2026-08-07T16:26:55Z
- Worker lanes: 384 (192 physical cores / 384 logical threads)
- Original JAR SHA-256:
  `06b15435d2b4bcfa032f9ddc9feefd20c62609eaa68b46ec59bacd097e87fb55`
- `cl-wlgen` SHA-256:
  `05443e4817a325ed0f5c6aca029aac3c13f6699fe23d83cf81e3d0bc8acd6e3a`
- Harness image ID:
  `sha256:c26523f4ca59509a1c170bf63b7d51f9b72b1bdae67b92f4ff455e65b84c817e`
- Spec content SHA-256:
  `7b9ba13992aa437f74fb530fd939e442d1ac5e06f0ee1538c5ba5a53e8e16d19`
- Container logging was disabled with `--log-driver=none`; otherwise Docker's
  default JSON logger would duplicate the binary oracle stream to disk.

The spec content SHA-256 is the SHA-256 of the exact bytes in the canonical
[`spec/spec-manifest.sha256`](../../../spec/spec-manifest.sha256). That
manifest contains one SHA-256 line per repository-relative source or
configuration file under `spec/`, excluding the lock manifest itself, sorted
with the `C` locale. It locks the spec content independently of branch names
or later commits.

## SQLite artifact

The complete campaign database is deliberately not tracked here: it is
4,623,380,480 bytes (about 4.31 GiB). It is retained as an external artifact;
use the run ID and checksum below to locate or verify a later archive copy.

SHA-256:

```text
dd6770dd9440c211637f2dfa7578053e11dd8da6bfab4f9fc742eb2564599546
```

`result.txt` is tracked here and has SHA-256
`bacdac21ef85d9a154abe96b613aa53b25ed2da368cdbd827a64d5442df2f39e`.
