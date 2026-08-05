#!/usr/bin/env python3
"""Render a human-readable summary from a fuzzer-v2 SQLite campaign."""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
import tempfile
from pathlib import Path
from typing import Any


def _connect(path: Path) -> sqlite3.Connection:
    if not path.is_file():
        raise ValueError(f"SQLite campaign database not found: {path}")
    connection = sqlite3.connect(path)
    connection.row_factory = sqlite3.Row
    return connection


def _run_row(connection: sqlite3.Connection, run_id: str | None) -> sqlite3.Row:
    if run_id is None:
        row = connection.execute(
            "SELECT * FROM runs ORDER BY created_at DESC LIMIT 1"
        ).fetchone()
    else:
        row = connection.execute(
            "SELECT * FROM runs WHERE run_id = ?", (run_id,)
        ).fetchone()
    if row is None:
        raise ValueError("no matching campaign run in SQLite database")
    return row


def _median_accuracy(connection: sqlite3.Connection, run_id: str, count: int) -> float:
    if count == 0:
        return 0.0
    if count == 1:
        offsets = (0,)
    elif count % 2:
        offsets = (count // 2,)
    else:
        offsets = (count // 2 - 1, count // 2)
    expression = (
        "100.0 * (volume - CASE WHEN outcome = 'mismatch' "
        "THEN differing ELSE 0 END) / volume"
    )
    values = []
    for offset in offsets:
        row = connection.execute(
            f"""
            SELECT {expression} AS accuracy
            FROM case_results
            WHERE run_id = ? AND outcome IN ('match', 'mismatch')
            ORDER BY accuracy
            LIMIT 1 OFFSET ?
            """,
            (run_id, offset),
        ).fetchone()
        assert row is not None
        values.append(float(row["accuracy"]))
    return sum(values) / len(values)


def _percent(value: float | None) -> str:
    return f"{value:.6f}%" if value is not None else "N/A"


def render_summary(database: Path, run_id: str | None = None) -> str:
    """Return a deterministic checked-in-style summary for one SQLite run."""

    connection = _connect(database)
    try:
        run = _run_row(connection, run_id)
        config: dict[str, Any] = json.loads(run["config_json"])
        aggregate = connection.execute(
            """
            SELECT
                COUNT(*) AS total,
                SUM(CASE WHEN phase = 'fixed' THEN 1 ELSE 0 END) AS fixed_total,
                SUM(CASE WHEN phase = 'random' THEN 1 ELSE 0 END) AS random_total,
                SUM(CASE WHEN outcome = 'match' THEN 1 ELSE 0 END) AS matches,
                SUM(CASE WHEN outcome = 'mismatch' THEN 1 ELSE 0 END) AS mismatches,
                SUM(CASE WHEN outcome = 'error' THEN 1 ELSE 0 END) AS errors,
                SUM(CASE WHEN outcome IN ('match', 'mismatch')
                         THEN volume ELSE 0 END) AS compared_blocks,
                SUM(CASE WHEN outcome = 'mismatch' THEN differing ELSE 0 END)
                    AS differing_blocks,
                AVG(CASE WHEN outcome IN ('match', 'mismatch') THEN
                    100.0 * (volume - CASE WHEN outcome = 'mismatch'
                    THEN differing ELSE 0 END) / volume END) AS mean_accuracy,
                MIN(CASE WHEN outcome IN ('match', 'mismatch') THEN
                    100.0 * (volume - CASE WHEN outcome = 'mismatch'
                    THEN differing ELSE 0 END) / volume END) AS lowest_accuracy,
                AVG(CASE WHEN outcome = 'mismatch' THEN
                    100.0 * (volume - differing) / volume END) AS mismatch_mean
            FROM case_results
            WHERE run_id = ?
            """,
            (run["run_id"],),
        ).fetchone()
        sessions = connection.execute(
            """
            SELECT COALESCE(SUM(elapsed_seconds), 0.0) AS elapsed
            FROM sessions
            WHERE run_id = ?
            """,
            (run["run_id"],),
        ).fetchone()
        first_failure = connection.execute(
            """
            SELECT *
            FROM case_results
            WHERE run_id = ? AND outcome != 'match'
            ORDER BY case_sequence
            LIMIT 1
            """,
            (run["run_id"],),
        ).fetchone()
        terminal_event = connection.execute(
            """
            SELECT kind, detail
            FROM events
            WHERE run_id = ? AND kind IN ('failed', 'interrupted')
            ORDER BY event_id DESC
            LIMIT 1
            """,
            (run["run_id"],),
        ).fetchone()
    finally:
        connection.close()

    total = int(aggregate["total"] or 0)
    fixed_total = int(aggregate["fixed_total"] or 0)
    random_total = int(aggregate["random_total"] or 0)
    matches = int(aggregate["matches"] or 0)
    mismatches = int(aggregate["mismatches"] or 0)
    errors = int(aggregate["errors"] or 0)
    compared_blocks = int(aggregate["compared_blocks"] or 0)
    differing_blocks = int(aggregate["differing_blocks"] or 0)
    comparison_count = matches + mismatches
    elapsed = float(sessions["elapsed"] or 0.0)
    weighted_accuracy: float | None = (
        100.0 * (compared_blocks - differing_blocks) / compared_blocks
        if compared_blocks
        else None
    )
    mean_accuracy = (
        float(aggregate["mean_accuracy"]) if comparison_count else None
    )
    if mismatches == 0 and comparison_count:
        median_accuracy: float | None = 100.0
    elif comparison_count:
        median_connection = _connect(database)
        try:
            median_accuracy = _median_accuracy(
                median_connection, run["run_id"], comparison_count
            )
        finally:
            median_connection.close()
    else:
        median_accuracy = None
    lowest_accuracy = (
        float(aggregate["lowest_accuracy"]) if comparison_count else None
    )
    mismatch_mean = aggregate["mismatch_mean"]
    budget = (
        f"{config['random_cases']} random cases"
        if config["budget_kind"] == "cases"
        else f"{config['duration_seconds']:g}s random phase"
    )
    lines = [
        "Fuzzer v2 campaign",
        "",
        f"  - Status: {run['status']}",
        f"  - Run ID: {run['run_id']}",
        f"  - Runtime: {elapsed:.1f} seconds",
        f"  - Budget: {budget}",
        f"  - Replay RNG seed: {config['rng_seed']}",
        f"  - Worker lanes: {config['jobs']}",
        f"  - Cases: {total} total — {fixed_total} fixed, {random_total} random",
        f"  - Exact matches: {matches}",
        f"  - Mismatches: {mismatches}",
        f"  - Oracle errors: {errors}",
        f"  - Blocks compared: {compared_blocks:,}",
        f"  - Differing blocks: {differing_blocks:,}",
        "",
        "  Accuracy statistics:",
        "",
        f"  - Mean per-world accuracy: {_percent(mean_accuracy)}",
        f"  - Median: {_percent(median_accuracy)}",
        f"  - Volume-weighted accuracy: {_percent(weighted_accuracy)}",
        "  - Mismatched-world mean: "
        + (f"{float(mismatch_mean):.6f}%" if mismatch_mean is not None else "N/A"),
        f"  - Lowest accuracy: {_percent(lowest_accuracy)}",
        "",
        "  Throughput:",
        "",
        f"  - Cases/second: {total / elapsed:.3f}" if elapsed else "  - Cases/second: N/A",
        f"  - Blocks/second: {compared_blocks / elapsed:,.0f}"
        if elapsed
        else "  - Blocks/second: N/A",
    ]
    if first_failure is None and terminal_event is not None:
        lines.extend(
            (
                "",
                f"  Campaign {terminal_event['kind']}: {terminal_event['detail']}",
            )
        )
    elif first_failure is None:
        lines.extend(("", "  Every completed case matched exactly."))
    elif first_failure["outcome"] == "mismatch":
        lines.extend(
            (
                "",
                f"  First mismatch: {first_failure['label']} "
                f"seed={first_failure['seed']} "
                f"{first_failure['width']}x{first_failure['height']}x{first_failure['depth']}",
                f"  - Differing: {first_failure['differing']}/{first_failure['volume']}",
                "  - First difference: "
                f"(x={first_failure['first_x']},y={first_failure['first_y']},"
                f"z={first_failure['first_z']}) @{first_failure['first_offset']} "
                f"a={first_failure['first_a']} b={first_failure['first_b']}",
            )
        )
    else:
        lines.extend(
            (
                "",
                f"  First error: {first_failure['label']} "
                f"seed={first_failure['seed']} "
                f"{first_failure['width']}x{first_failure['height']}x{first_failure['depth']}",
                f"  - Oracle A: {first_failure['error_a'] or 'N/A'}",
                f"  - Oracle B: {first_failure['error_b'] or 'N/A'}",
            )
        )
    return "\n".join(lines) + "\n"


def write_summary(database: Path, output: Path, run_id: str | None = None) -> None:
    """Atomically render ``output`` from a finalized or live campaign database."""

    text = render_summary(database, run_id)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=output.parent, delete=False
    ) as temporary:
        temporary.write(text)
        temporary_path = Path(temporary.name)
    os.replace(temporary_path, output)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path, help="v2 campaign SQLite database")
    parser.add_argument("--run-id", help="run ID to render (default: newest run)")
    parser.add_argument("--output", type=Path, help="write summary to this file")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        text = render_summary(args.database, args.run_id)
    except (OSError, ValueError, sqlite3.Error) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    if args.output is None:
        print(text, end="")
    else:
        try:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", dir=args.output.parent, delete=False
            ) as temporary:
                temporary.write(text)
                temporary_path = Path(temporary.name)
            os.replace(temporary_path, args.output)
        except OSError as error:
            print(f"error: {error}", file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
