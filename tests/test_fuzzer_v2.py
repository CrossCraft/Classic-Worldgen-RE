from __future__ import annotations

import contextlib
import shlex
import sqlite3
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest import mock

from fuzzer_v2 import campaign
from fuzzer_v2 import fuzzer
from fuzzer_v2.storage import CampaignStore, CaseResult, database_path
from fuzzer_v2.summarize import render_summary
from fuzzer_v2.worker import WorkerPair


FAKE_WORKER = r'''
import sys
import time

mode = sys.argv[1]
output = sys.stdout.buffer
input_stream = sys.stdin.buffer
if mode == "bad-ready":
    output.write(b"READY 99\n")
    output.flush()
    raise SystemExit(0)
output.write(b"READY 2\n")
output.flush()
for line in input_stream:
    if line == b"QUIT\n":
        output.write(b"BYE\n")
        output.flush()
        break
    fields = line.decode("ascii").strip().split()
    _, request_id, seed, width, height, depth = fields
    if mode == "fail":
        sys.stderr.write("synthetic failure\n")
        sys.stderr.flush()
        output.write(("FAIL " + request_id + "\n").encode("ascii"))
        output.flush()
        continue
    if mode == "slow":
        time.sleep(0.2)
    volume = int(width) * int(height) * int(depth)
    if mode == "bad-count":
        output.write(("OK " + request_id + " " + str(volume + 1) + "\n").encode("ascii"))
        output.flush()
        continue
    block = int(seed) & 255
    data = bytearray([block]) * volume
    if mode == "mismatch":
        data[0] ^= 1
    output.write(("OK " + request_id + " " + str(volume) + "\n").encode("ascii"))
    output.write(data)
    output.flush()
'''


def tiny_fixed_cases() -> list[campaign.Case]:
    return [
        campaign.Case(0, "fixed:a", "fixed", 1, 16, 16, 16),
        campaign.Case(1, "fixed:b", "fixed", -1, 16, 16, 16),
    ]


def tiny_random_case(rng_seed: int, index: int) -> campaign.Case:
    return campaign.Case(
        2 + index - 1,
        f"random:{index}",
        "random",
        rng_seed + index,
        16,
        16,
        16,
        index,
    )


class FuzzerV2Test(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.worker = root / "worker.py"
        self.worker.write_text(textwrap.dedent(FAKE_WORKER), encoding="utf-8")
        self.root = root

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def command(self, mode: str) -> str:
        return f"{shlex.quote(sys.executable)} {shlex.quote(str(self.worker))} {mode}"

    @contextlib.contextmanager
    def tiny_corpus(self):
        with mock.patch.object(campaign, "fixed_cases", tiny_fixed_cases), mock.patch.object(
            fuzzer, "fixed_cases", tiny_fixed_cases
        ), mock.patch.object(fuzzer, "random_case", tiny_random_case):
            yield

    def test_counter_cases_are_independent_and_in_domain(self):
        first = campaign.random_case(123, 7)
        self.assertEqual(first, campaign.random_case(123, 7))
        self.assertNotEqual(first, campaign.random_case(123, 8))
        self.assertGreaterEqual(first.width, 16)
        self.assertTrue(first.width & (first.width - 1) == 0)

    def test_exact_campaign_persists_compact_match_rows_and_summary(self):
        campaign_dir = self.root / "campaign"
        with self.tiny_corpus():
            status = fuzzer.main(
                [
                    "--campaign-dir", str(campaign_dir),
                    "--oracle-a-worker", self.command("normal"),
                    "--oracle-b-worker", self.command("normal"),
                    "--random-cases", "3",
                    "--rng-seed", "99",
                    "--jobs", "2",
                ]
            )
        self.assertEqual(status, 0)
        database = database_path(campaign_dir)
        with sqlite3.connect(database) as connection:
            status_row = connection.execute("SELECT status FROM runs").fetchone()
            result_count = connection.execute("SELECT COUNT(*) FROM case_results").fetchone()
            hashes = connection.execute(
                "SELECT a_sha256, b_sha256 FROM case_results WHERE outcome = 'match'"
            ).fetchall()
        self.assertEqual(status_row, ("complete",))
        self.assertEqual(result_count, (5,))
        self.assertTrue(all(row == (None, None) for row in hashes))
        text = (campaign_dir / "result.txt").read_text(encoding="utf-8")
        self.assertIn("Exact matches: 5", text)
        self.assertIn("Every completed case matched exactly", text)

    def test_mismatch_fails_fast_and_keeps_diagnostics(self):
        campaign_dir = self.root / "mismatch"
        with self.tiny_corpus():
            status = fuzzer.main(
                [
                    "--campaign-dir", str(campaign_dir),
                    "--oracle-a-worker", self.command("normal"),
                    "--oracle-b-worker", self.command("mismatch"),
                    "--random-cases", "2",
                    "--rng-seed", "99",
                    "--jobs", "1",
                ]
            )
        self.assertEqual(status, 1)
        with sqlite3.connect(database_path(campaign_dir)) as connection:
            row = connection.execute(
                "SELECT outcome, differing, first_x, first_y, first_z, a_sha256, b_sha256 "
                "FROM case_results"
            ).fetchone()
            run = connection.execute("SELECT status FROM runs").fetchone()
        self.assertEqual(row[:5], ("mismatch", 1, 0, 0, 0))
        self.assertIsNotNone(row[5])
        self.assertIsNotNone(row[6])
        self.assertEqual(run, ("failed",))
        self.assertIn("First mismatch", render_summary(database_path(campaign_dir)))

    def test_protocol_error_is_recorded_as_campaign_error(self):
        campaign_dir = self.root / "protocol-error"
        with self.tiny_corpus():
            status = fuzzer.main(
                [
                    "--campaign-dir", str(campaign_dir),
                    "--oracle-a-worker", self.command("bad-count"),
                    "--oracle-b-worker", self.command("normal"),
                    "--random-cases", "0",
                    "--rng-seed", "99",
                    "--jobs", "1",
                ]
            )
        self.assertEqual(status, 2)
        with sqlite3.connect(database_path(campaign_dir)) as connection:
            row = connection.execute(
                "SELECT outcome, error_a FROM case_results"
            ).fetchone()
        self.assertEqual(row[0], "error")
        self.assertIn("declared", row[1])

    def test_timeout_is_recorded_as_an_oracle_error(self):
        campaign_dir = self.root / "timeout"
        with self.tiny_corpus():
            status = fuzzer.main(
                [
                    "--campaign-dir", str(campaign_dir),
                    "--oracle-a-worker", self.command("slow"),
                    "--oracle-b-worker", self.command("normal"),
                    "--random-cases", "0",
                    "--rng-seed", "99",
                    "--jobs", "1",
                    "--oracle-timeout", "0.01",
                ]
            )
        self.assertEqual(status, 2)
        with sqlite3.connect(database_path(campaign_dir)) as connection:
            error = connection.execute(
                "SELECT error_a FROM case_results"
            ).fetchone()[0]
        self.assertIn("timed out", error)

    def test_invalid_ready_header_fails_before_cases_run(self):
        campaign_dir = self.root / "bad-ready"
        with self.tiny_corpus():
            status = fuzzer.main(
                [
                    "--campaign-dir", str(campaign_dir),
                    "--oracle-a-worker", self.command("bad-ready"),
                    "--oracle-b-worker", self.command("normal"),
                    "--random-cases", "0",
                    "--rng-seed", "99",
                    "--jobs", "1",
                ]
            )
        self.assertEqual(status, 2)
        text = (campaign_dir / "result.txt").read_text(encoding="utf-8")
        self.assertIn("Campaign failed", text)

    def test_runner_resumes_missing_cases_from_an_interrupted_campaign(self):
        campaign_dir = self.root / "resume"
        args = fuzzer.parse_args(
            [
                "--campaign-dir", str(campaign_dir),
                "--oracle-a-worker", self.command("normal"),
                "--oracle-b-worker", self.command("normal"),
                "--random-cases", "2",
                "--rng-seed", "99",
                "--jobs", "1",
            ]
        )
        with self.tiny_corpus():
            config = fuzzer.campaign_config(args, 99)
            store = CampaignStore.create(campaign_dir, config)
            store.add_result(
                CaseResult(
                    tiny_fixed_cases()[0], 0, 0.01, 0.005, 0.005, "match"
                )
            )
            store.finish("interrupted", 0.0, "test interruption")
            store.close()
            status = fuzzer.main(
                [
                    "--campaign-dir", str(campaign_dir),
                    "--oracle-a-worker", self.command("normal"),
                    "--oracle-b-worker", self.command("normal"),
                    "--random-cases", "2",
                    "--rng-seed", "99",
                    "--jobs", "1",
                    "--resume",
                ]
            )
        self.assertEqual(status, 0)
        with sqlite3.connect(database_path(campaign_dir)) as connection:
            rows = connection.execute(
                "SELECT case_sequence FROM case_results ORDER BY case_sequence"
            ).fetchall()
            final_status = connection.execute("SELECT status FROM runs").fetchone()
        self.assertEqual(rows, [(0,), (1,), (2,), (3,)])
        self.assertEqual(final_status, ("complete",))

    def test_worker_reports_bad_count_without_hanging(self):
        pair = WorkerPair(0, self.command("normal"), self.command("bad-count"))
        try:
            pair.start(2.0)
            result = pair.run(tiny_fixed_cases()[0], 2.0)
        finally:
            pair.close(force=True)
        self.assertEqual(result.outcome, "error")
        self.assertIn("declared", result.error_b or "")


if __name__ == "__main__":
    unittest.main()
