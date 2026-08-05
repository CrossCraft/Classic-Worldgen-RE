"""SQLite persistence for resumable fuzzer-v2 campaigns."""

from __future__ import annotations

import dataclasses
import json
import sqlite3
import time
import uuid
from collections.abc import Iterator
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .campaign import Case

SCHEMA_VERSION = 1
DATABASE_NAME = "campaign.sqlite"


class CampaignStorageError(RuntimeError):
    """Raised when a campaign directory cannot safely be opened."""


@dataclasses.dataclass(frozen=True)
class StoredRun:
    run_id: str
    status: str
    config: dict[str, Any]
    random_elapsed_seconds: float


@dataclasses.dataclass(frozen=True)
class CaseResult:
    case: Case
    lane: int
    seconds: float
    a_seconds: float | None
    b_seconds: float | None
    outcome: str
    differing: int | None = None
    first_offset: int | None = None
    first_x: int | None = None
    first_y: int | None = None
    first_z: int | None = None
    first_a: int | None = None
    first_b: int | None = None
    a_sha256: bytes | None = None
    b_sha256: bytes | None = None
    error_a: str | None = None
    error_b: str | None = None


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def database_path(campaign_dir: Path) -> Path:
    return campaign_dir / DATABASE_NAME


class CampaignStore:
    """One SQLite writer, owned exclusively by the fuzzer coordinator."""

    def __init__(self, path: Path, connection: sqlite3.Connection, run: StoredRun):
        self.path = path
        self.connection = connection
        self.run = run
        self._pending_results: list[tuple[object, ...]] = []
        self._pending_events: list[tuple[object, ...]] = []
        self._last_flush = time.monotonic()
        self._session_id: int | None = None
        self._session_started = time.monotonic()

    @classmethod
    def create(cls, campaign_dir: Path, config: dict[str, Any]) -> "CampaignStore":
        campaign_dir.mkdir(parents=True, exist_ok=True)
        path = database_path(campaign_dir)
        if path.exists():
            raise CampaignStorageError(
                f"campaign database already exists: {path}; use --resume"
            )
        connection = _connect(path)
        _create_schema(connection)
        run_id = str(uuid.uuid4())
        now = utc_now()
        encoded = _canonical_json(config)
        connection.execute(
            """
            INSERT INTO runs (
                run_id, schema_version, status, config_json, created_at, updated_at,
                random_elapsed_seconds
            ) VALUES (?, ?, 'running', ?, ?, ?, 0.0)
            """,
            (run_id, SCHEMA_VERSION, encoded, now, now),
        )
        connection.commit()
        run = StoredRun(run_id, "running", config, 0.0)
        store = cls(path, connection, run)
        store._open_session("new")
        return store

    @classmethod
    def resume(cls, campaign_dir: Path, config: dict[str, Any]) -> "CampaignStore":
        path = database_path(campaign_dir)
        if not path.is_file():
            raise CampaignStorageError(f"campaign database not found: {path}")
        connection = _connect(path)
        _create_schema(connection)
        row = connection.execute(
            """
            SELECT run_id, status, config_json, random_elapsed_seconds
            FROM runs
            ORDER BY created_at DESC
            LIMIT 1
            """
        ).fetchone()
        if row is None:
            raise CampaignStorageError(f"campaign database has no run: {path}")
        stored_config = json.loads(row[2])
        _validate_resume_config(stored_config, config)
        if row[1] == "complete":
            raise CampaignStorageError("campaign is already complete")
        if row[1] == "failed":
            raise CampaignStorageError("failed campaigns cannot be resumed")
        failure = connection.execute(
            """
            SELECT 1 FROM case_results
            WHERE run_id = ? AND outcome != 'match'
            LIMIT 1
            """,
            (row[0],),
        ).fetchone()
        if failure is not None:
            raise CampaignStorageError(
                "campaign contains a non-match and cannot be resumed"
            )
        terminal_failure = connection.execute(
            """
            SELECT 1 FROM events
            WHERE run_id = ? AND kind = 'failed'
            LIMIT 1
            """,
            (row[0],),
        ).fetchone()
        if terminal_failure is not None:
            raise CampaignStorageError("campaign contains a terminal failure event")
        run = StoredRun(row[0], "running", stored_config, float(row[3]))
        connection.execute(
            "UPDATE runs SET status = 'running', updated_at = ? WHERE run_id = ?",
            (utc_now(), run.run_id),
        )
        connection.commit()
        store = cls(path, connection, run)
        store._open_session("resume")
        return store

    @classmethod
    def existing_config(cls, campaign_dir: Path) -> dict[str, Any]:
        """Read immutable run configuration before building a resume invocation."""

        path = database_path(campaign_dir)
        if not path.is_file():
            raise CampaignStorageError(f"campaign database not found: {path}")
        connection = _connect(path)
        try:
            row = connection.execute(
                "SELECT config_json FROM runs ORDER BY created_at DESC LIMIT 1"
            ).fetchone()
        finally:
            connection.close()
        if row is None:
            raise CampaignStorageError(f"campaign database has no run: {path}")
        return json.loads(row[0])

    def _open_session(self, reason: str) -> None:
        cursor = self.connection.execute(
            """
            INSERT INTO sessions (run_id, started_at, reason)
            VALUES (?, ?, ?)
            """,
            (self.run.run_id, utc_now(), reason),
        )
        self.connection.commit()
        self._session_id = int(cursor.lastrowid)
        self._session_started = time.monotonic()

    def add_event(self, kind: str, detail: str) -> None:
        self._pending_events.append((self.run.run_id, utc_now(), kind, detail))

    def add_result(self, result: CaseResult) -> None:
        case = result.case
        if result.outcome not in {"match", "mismatch", "error"}:
            raise ValueError(f"unknown outcome: {result.outcome}")
        if result.outcome == "match" and (
            result.a_sha256 is not None or result.b_sha256 is not None
        ):
            raise ValueError("compact match rows must not persist SHA-256 values")
        self._pending_results.append(
            (
                self.run.run_id,
                case.sequence,
                case.phase,
                case.random_index,
                case.label,
                case.seed,
                case.width,
                case.height,
                case.depth,
                case.volume,
                result.lane,
                result.seconds,
                result.a_seconds,
                result.b_seconds,
                result.outcome,
                result.differing,
                result.first_offset,
                result.first_x,
                result.first_y,
                result.first_z,
                result.first_a,
                result.first_b,
                result.a_sha256,
                result.b_sha256,
                result.error_a,
                result.error_b,
            )
        )

    def should_flush(self) -> bool:
        return len(self._pending_results) >= 1_000 or (
            self._pending_results and time.monotonic() - self._last_flush >= 1.0
        )

    def flush(self, random_elapsed_seconds: float, force: bool = False) -> None:
        if not force and not self.should_flush() and not self._pending_events:
            return
        if self._pending_results:
            self.connection.executemany(
                """
                INSERT INTO case_results (
                    run_id, case_sequence, phase, random_index, label, seed,
                    width, height, depth, volume, lane, seconds, a_seconds,
                    b_seconds, outcome, differing, first_offset, first_x,
                    first_y, first_z, first_a, first_b, a_sha256, b_sha256,
                    error_a, error_b
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                          ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                self._pending_results,
            )
        if self._pending_events:
            self.connection.executemany(
                """
                INSERT INTO events (run_id, recorded_at, kind, detail)
                VALUES (?, ?, ?, ?)
                """,
                self._pending_events,
            )
        self.connection.execute(
            """
            UPDATE runs
            SET random_elapsed_seconds = ?, updated_at = ?
            WHERE run_id = ?
            """,
            (random_elapsed_seconds, utc_now(), self.run.run_id),
        )
        self.connection.commit()
        self.run = dataclasses.replace(
            self.run, random_elapsed_seconds=random_elapsed_seconds
        )
        self._pending_results.clear()
        self._pending_events.clear()
        self._last_flush = time.monotonic()

    def finish(
        self,
        status: str,
        random_elapsed_seconds: float,
        detail: str | None = None,
    ) -> None:
        if status not in {"complete", "failed", "interrupted"}:
            raise ValueError(f"invalid terminal campaign status: {status}")
        if detail is not None:
            self.add_event(status, detail)
        self.flush(random_elapsed_seconds, force=True)
        session_elapsed = time.monotonic() - self._session_started
        if self._session_id is not None:
            self.connection.execute(
                """
                UPDATE sessions
                SET ended_at = ?, elapsed_seconds = ?
                WHERE session_id = ?
                """,
                (utc_now(), session_elapsed, self._session_id),
            )
        self.connection.execute(
            """
            UPDATE runs
            SET status = ?, updated_at = ?, ended_at = ?
            WHERE run_id = ?
            """,
            (status, utc_now(), utc_now(), self.run.run_id),
        )
        self.connection.commit()
        self.run = dataclasses.replace(
            self.run,
            status=status,
            random_elapsed_seconds=random_elapsed_seconds,
        )

    def completed_fixed_sequences(self) -> set[int]:
        rows = self.connection.execute(
            """
            SELECT case_sequence
            FROM case_results
            WHERE run_id = ? AND phase = 'fixed' AND outcome = 'match'
            """,
            (self.run.run_id,),
        )
        return {int(row[0]) for row in rows}

    def missing_random_indices(self, upper: int) -> Iterator[int]:
        """Yield missing random indices in a bounded interval without a giant set."""

        expected = 1
        rows = self.connection.execute(
            """
            SELECT random_index
            FROM case_results
            WHERE run_id = ? AND phase = 'random' AND random_index <= ?
            ORDER BY random_index
            """,
            (self.run.run_id, upper),
        )
        for (actual_raw,) in rows:
            actual = int(actual_raw)
            while expected < actual:
                yield expected
                expected += 1
            if expected == actual:
                expected += 1
        while expected <= upper:
            yield expected
            expected += 1

    def maximum_random_index(self) -> int:
        row = self.connection.execute(
            """
            SELECT COALESCE(MAX(random_index), 0)
            FROM case_results
            WHERE run_id = ? AND phase = 'random'
            """,
            (self.run.run_id,),
        ).fetchone()
        return int(row[0])

    def close(self) -> None:
        try:
            self.connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        finally:
            self.connection.close()


def _connect(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(path)
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute("PRAGMA journal_mode = WAL")
    connection.execute("PRAGMA synchronous = NORMAL")
    return connection


def _create_schema(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        CREATE TABLE IF NOT EXISTS runs (
            run_id TEXT PRIMARY KEY,
            schema_version INTEGER NOT NULL,
            status TEXT NOT NULL,
            config_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            ended_at TEXT,
            random_elapsed_seconds REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS sessions (
            session_id INTEGER PRIMARY KEY,
            run_id TEXT NOT NULL REFERENCES runs(run_id),
            started_at TEXT NOT NULL,
            ended_at TEXT,
            elapsed_seconds REAL,
            reason TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS case_results (
            run_id TEXT NOT NULL REFERENCES runs(run_id),
            case_sequence INTEGER NOT NULL,
            phase TEXT NOT NULL,
            random_index INTEGER,
            label TEXT NOT NULL,
            seed INTEGER NOT NULL,
            width INTEGER NOT NULL,
            height INTEGER NOT NULL,
            depth INTEGER NOT NULL,
            volume INTEGER NOT NULL,
            lane INTEGER NOT NULL,
            seconds REAL NOT NULL,
            a_seconds REAL,
            b_seconds REAL,
            outcome TEXT NOT NULL,
            differing INTEGER,
            first_offset INTEGER,
            first_x INTEGER,
            first_y INTEGER,
            first_z INTEGER,
            first_a INTEGER,
            first_b INTEGER,
            a_sha256 BLOB,
            b_sha256 BLOB,
            error_a TEXT,
            error_b TEXT,
            PRIMARY KEY (run_id, case_sequence),
            CHECK (outcome IN ('match', 'mismatch', 'error'))
        );

        CREATE INDEX IF NOT EXISTS case_results_random_index
        ON case_results (run_id, phase, random_index);

        CREATE TABLE IF NOT EXISTS events (
            event_id INTEGER PRIMARY KEY,
            run_id TEXT NOT NULL REFERENCES runs(run_id),
            recorded_at TEXT NOT NULL,
            kind TEXT NOT NULL,
            detail TEXT NOT NULL
        );
        """
    )
    connection.commit()


def _canonical_json(value: dict[str, Any]) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def _validate_resume_config(stored: dict[str, Any], supplied: dict[str, Any]) -> None:
    # Host observations are intentionally not part of reproducibility identity.
    ignored = {"host_cpu_count", "process_cpu_count", "scratch_dir"}
    left = {key: value for key, value in stored.items() if key not in ignored}
    right = {key: value for key, value in supplied.items() if key not in ignored}
    if _canonical_json(left) != _canonical_json(right):
        raise CampaignStorageError(
            "resume configuration differs from the existing campaign"
        )
