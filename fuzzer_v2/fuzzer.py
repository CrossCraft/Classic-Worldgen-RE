#!/usr/bin/env python3
"""Persistent, parallel differential fuzzer with SQLite campaign storage."""

from __future__ import annotations

import argparse
import dataclasses
import os
import random
import signal
import sqlite3
import sys
import time
from collections.abc import Callable, Iterator
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from fuzzer_v2.campaign import (  # noqa: E402
    CASE_GENERATOR_VERSION,
    FIXED_CORPUS_VERSION,
    PROTOCOL_VERSION,
    Case,
    fixed_cases,
    fixed_corpus_sha256,
    random_case,
)
from fuzzer_v2.lanes import LanePool  # noqa: E402
from fuzzer_v2.storage import (  # noqa: E402
    CampaignStorageError,
    CampaignStore,
    CaseResult,
    database_path,
)
from fuzzer_v2.summarize import write_summary  # noqa: E402
from fuzzer_v2.worker import WorkerError  # noqa: E402

PROGRESS_INTERVAL_SECONDS = 30.0


@dataclasses.dataclass
class _PhaseOutcome:
    terminal: CaseResult | None = None
    completed: int = 0


def parse_duration(text: str) -> float:
    units = {"s": 1.0, "m": 60.0, "h": 3600.0}
    if not text:
        raise argparse.ArgumentTypeError("duration must not be empty")
    suffix = text[-1].lower()
    try:
        value = float(text[:-1]) * units[suffix] if suffix in units else float(text)
    except ValueError as error:
        raise argparse.ArgumentTypeError(f"invalid duration: {text}") from error
    if value < 0:
        raise argparse.ArgumentTypeError("duration must not be negative")
    return value


def positive_integer(text: str) -> int:
    try:
        value = int(text)
    except ValueError as error:
        raise argparse.ArgumentTypeError(f"invalid integer: {text}") from error
    if value < 1:
        raise argparse.ArgumentTypeError("value must be at least one")
    return value


def nonnegative_integer(text: str) -> int:
    try:
        value = int(text)
    except ValueError as error:
        raise argparse.ArgumentTypeError(f"invalid integer: {text}") from error
    if value < 0:
        raise argparse.ArgumentTypeError("value must not be negative")
    return value


def default_jobs() -> int:
    process_count = getattr(os, "process_cpu_count", lambda: None)()
    return process_count or os.cpu_count() or 1


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--campaign-dir",
        required=True,
        type=Path,
        help="directory containing campaign.sqlite and generated result.txt",
    )
    parser.add_argument(
        "--oracle-a-worker",
        required=True,
        help="persistent worker command template for oracle A; {worker} is optional",
    )
    parser.add_argument(
        "--oracle-b-worker",
        required=True,
        help="persistent worker command template for oracle B; {worker} is optional",
    )
    budget = parser.add_mutually_exclusive_group(required=True)
    budget.add_argument(
        "--duration",
        type=parse_duration,
        metavar="SECONDS|Nm|Nh",
        help="random-phase wall-clock budget",
    )
    budget.add_argument(
        "--random-cases",
        type=nonnegative_integer,
        metavar="N",
        help="exact number of random cases after the fixed corpus",
    )
    parser.add_argument(
        "--rng-seed",
        type=int,
        help="seed for v2's counter-based random case generator",
    )
    parser.add_argument(
        "--jobs",
        type=positive_integer,
        default=default_jobs(),
        help="concurrent case lanes (default: available logical CPUs)",
    )
    parser.add_argument(
        "--startup-parallelism",
        type=positive_integer,
        help="maximum worker lanes launched concurrently (default: min(32, jobs))",
    )
    parser.add_argument(
        "--scratch-dir",
        type=Path,
        help="existing directory for per-lane temporary comparison files",
    )
    parser.add_argument(
        "--startup-timeout",
        type=parse_duration,
        default=60.0,
        metavar="SECONDS",
        help="per-worker READY timeout (default: 60)",
    )
    parser.add_argument(
        "--oracle-timeout",
        type=parse_duration,
        default=600.0,
        metavar="SECONDS",
        help="per-case, per-oracle timeout (default: 600)",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="resume an interrupted campaign after validating immutable config",
    )
    args = parser.parse_args(argv)
    if args.startup_parallelism is not None and args.startup_parallelism > args.jobs:
        parser.error("--startup-parallelism cannot exceed --jobs")
    if args.startup_timeout <= 0:
        parser.error("--startup-timeout must be positive")
    if args.oracle_timeout <= 0:
        parser.error("--oracle-timeout must be positive")
    if args.scratch_dir is not None and not args.scratch_dir.is_dir():
        parser.error("--scratch-dir must name an existing directory")
    return args


def campaign_config(args: argparse.Namespace, rng_seed: int) -> dict[str, object]:
    budget_kind = "duration" if args.duration is not None else "cases"
    return {
        "schema_version": 1,
        "protocol_version": PROTOCOL_VERSION,
        "case_generator_version": CASE_GENERATOR_VERSION,
        "fixed_corpus_version": FIXED_CORPUS_VERSION,
        "fixed_corpus_sha256": fixed_corpus_sha256(),
        "rng_seed": rng_seed,
        "budget_kind": budget_kind,
        "duration_seconds": args.duration if budget_kind == "duration" else None,
        "random_cases": args.random_cases if budget_kind == "cases" else None,
        "jobs": args.jobs,
        "startup_parallelism": args.startup_parallelism or min(32, args.jobs),
        "startup_timeout_seconds": args.startup_timeout,
        "oracle_timeout_seconds": args.oracle_timeout,
        "oracle_a_worker": args.oracle_a_worker,
        "oracle_b_worker": args.oracle_b_worker,
        "scratch_dir": str(args.scratch_dir) if args.scratch_dir is not None else None,
        "host_cpu_count": os.cpu_count(),
        "process_cpu_count": getattr(os, "process_cpu_count", lambda: None)(),
    }


def _start_pairs(args: argparse.Namespace) -> LanePool:
    parallelism = args.startup_parallelism or min(32, args.jobs)
    pairs = LanePool(
        args.jobs,
        args.oracle_a_worker,
        args.oracle_b_worker,
        args.scratch_dir,
        parallelism,
        args.startup_timeout,
    )
    try:
        pairs.start()
    except Exception:
        pairs.close(True)
        raise
    return pairs


def _close_pairs(pairs: LanePool | None, force: bool) -> None:
    if pairs is not None:
        pairs.close(force)


def _run_phase(
    pairs: LanePool,
    cases: Iterator[Case],
    store: CampaignStore,
    oracle_timeout: float,
    random_elapsed: Callable[[], float],
    may_schedule: Callable[[], bool],
    phase_name: str,
) -> _PhaseOutcome:
    """Schedule a source iterator across persistent lanes until terminal state."""

    pending: dict[int, Case] = {}
    exhausted = False
    last_progress = time.monotonic()
    completed = 0

    def submit_next(lane: int) -> bool:
        nonlocal exhausted
        if exhausted or not may_schedule():
            return False
        try:
            case = next(cases)
        except StopIteration:
            exhausted = True
            return False
        pairs.submit(lane, case, oracle_timeout)
        pending[lane] = case
        return True

    try:
        for lane in range(pairs.lane_count):
            submit_next(lane)
        while pending:
            completed_result = pairs.receive(1.0)
            if completed_result is None:
                if store.should_flush():
                    store.flush(random_elapsed())
                if time.monotonic() - last_progress >= PROGRESS_INTERVAL_SECONDS:
                    print(
                        f"{phase_name} progress: {completed} cases completed; "
                        f"{len(pending)} active",
                        flush=True,
                    )
                    last_progress = time.monotonic()
                continue
            lane, result = completed_result
            case = pending.pop(lane, None)
            if case is None:
                raise WorkerError(f"lane {lane} returned a result without a pending case")
            if result.case != case:
                raise WorkerError(f"lane {lane} returned a result for the wrong case")
            store.add_result(result)
            completed += 1
            if result.outcome != "match":
                store.flush(random_elapsed(), force=True)
                _close_pairs(pairs, True)
                return _PhaseOutcome(result, completed)
            if store.should_flush():
                store.flush(random_elapsed())
            submit_next(lane)
            if time.monotonic() - last_progress >= PROGRESS_INTERVAL_SECONDS:
                print(
                    f"{phase_name} progress: {completed} cases completed; "
                    f"{len(pending)} active",
                    flush=True,
                )
                last_progress = time.monotonic()
        store.flush(random_elapsed(), force=True)
        return _PhaseOutcome(None, completed)
    except KeyboardInterrupt:
        _close_pairs(pairs, True)
        raise
    except Exception:
        _close_pairs(pairs, True)
        raise


def _fixed_iterator(store: CampaignStore) -> Iterator[Case]:
    completed = store.completed_fixed_sequences()
    for case in fixed_cases():
        if case.sequence not in completed:
            yield case


def _random_indices_for_duration(store: CampaignStore) -> Iterator[int]:
    highest = store.maximum_random_index()
    yield from store.missing_random_indices(highest)
    index = highest + 1
    while True:
        yield index
        index += 1


def _random_iterator(store: CampaignStore, config: dict[str, object]) -> Iterator[Case]:
    rng_seed = int(config["rng_seed"])
    if config["budget_kind"] == "cases":
        assert config["random_cases"] is not None
        indices = store.missing_random_indices(int(config["random_cases"]))
    else:
        indices = _random_indices_for_duration(store)
    for index in indices:
        yield random_case(rng_seed, index)


def _print_case_failure(result: CaseResult) -> None:
    case = result.case
    dims = f"{case.width}x{case.height}x{case.depth}"
    if result.outcome == "mismatch":
        print(
            f"MISMATCH {case.label} seed={case.seed} {dims} "
            f"differing={result.differing}/{case.volume} "
            f"first=(x={result.first_x},y={result.first_y},z={result.first_z})"
            f"@{result.first_offset} a={result.first_a} b={result.first_b}",
            flush=True,
        )
    else:
        print(f"ERROR {case.label} seed={case.seed} {dims}", flush=True)
        if result.error_a:
            print(f"  A: {result.error_a}", flush=True)
        if result.error_b:
            print(f"  B: {result.error_b}", flush=True)


def run(args: argparse.Namespace) -> int:
    try:
        if args.resume:
            existing = CampaignStore.existing_config(args.campaign_dir)
            rng_seed = existing["rng_seed"] if args.rng_seed is None else args.rng_seed
        else:
            rng_seed = args.rng_seed
            if rng_seed is None:
                rng_seed = random.SystemRandom().randrange(1 << 63)
    except (CampaignStorageError, OSError, sqlite3.Error) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    assert isinstance(rng_seed, int)
    config = campaign_config(args, rng_seed)
    try:
        store = (
            CampaignStore.resume(args.campaign_dir, config)
            if args.resume
            else CampaignStore.create(args.campaign_dir, config)
        )
    except (CampaignStorageError, OSError, sqlite3.Error) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    pairs: LanePool | None = None
    random_elapsed = store.run.random_elapsed_seconds
    random_elapsed_now: Callable[[], float] = lambda: random_elapsed
    terminal_status = "failed"
    terminal_detail: str | None = None
    exit_code = 2
    try:
        print(f"fuzzer v2 rng seed: {rng_seed}")
        print(f"worker lanes: {args.jobs}")
        print(f"oracle A worker: {args.oracle_a_worker}")
        print(f"oracle B worker: {args.oracle_b_worker}")
        pairs = _start_pairs(args)
        store.add_event(
            "workers_started", f"{pairs.lane_count} persistent worker lanes ready"
        )
        store.flush(random_elapsed, force=True)

        fixed_outcome = _run_phase(
            pairs,
            _fixed_iterator(store),
            store,
            args.oracle_timeout,
            lambda: random_elapsed,
            lambda: True,
            "fixed corpus",
        )
        if fixed_outcome.terminal is not None:
            _print_case_failure(fixed_outcome.terminal)
            terminal_status = "failed"
            terminal_detail = "fixed corpus produced a non-match"
            exit_code = 1 if fixed_outcome.terminal.outcome == "mismatch" else 2
        else:
            print("fixed corpus done", flush=True)
            if config["budget_kind"] == "duration":
                budget = float(config["duration_seconds"])
                remaining = max(0.0, budget - random_elapsed)
                random_started = time.monotonic()
                deadline = random_started + remaining
                random_elapsed_now = lambda: random_elapsed + (
                    time.monotonic() - random_started
                )
                may_schedule = lambda: time.monotonic() < deadline
                phase_name = f"random phase ({remaining:g}s remaining)"
            else:
                random_elapsed_now = lambda: random_elapsed
                may_schedule = lambda: True
                phase_name = "random phase"

            random_outcome = _run_phase(
                pairs,
                _random_iterator(store, config),
                store,
                args.oracle_timeout,
                random_elapsed_now,
                may_schedule,
                phase_name,
            )
            random_elapsed = random_elapsed_now()
            if random_outcome.terminal is not None:
                _print_case_failure(random_outcome.terminal)
                terminal_status = "failed"
                terminal_detail = "random phase produced a non-match"
                exit_code = 1 if random_outcome.terminal.outcome == "mismatch" else 2
            else:
                terminal_status = "complete"
                exit_code = 0
    except KeyboardInterrupt:
        random_elapsed = random_elapsed_now()
        terminal_status = "interrupted"
        terminal_detail = "interrupted by user"
        exit_code = 130
        print("interrupted; campaign can be resumed", file=sys.stderr)
    except (CampaignStorageError, WorkerError, OSError, sqlite3.Error) as error:
        random_elapsed = random_elapsed_now()
        terminal_status = "failed"
        terminal_detail = str(error)
        exit_code = 2
        print(f"error: {error}", file=sys.stderr)
    except Exception as error:
        random_elapsed = random_elapsed_now()
        terminal_status = "failed"
        terminal_detail = f"unexpected fuzzer error: {error}"
        exit_code = 2
        print(f"error: {terminal_detail}", file=sys.stderr)
    finally:
        if pairs is not None:
            _close_pairs(pairs, terminal_status != "complete")
        try:
            store.finish(terminal_status, random_elapsed, terminal_detail)
            store.close()
            write_summary(
                database_path(args.campaign_dir),
                args.campaign_dir / "result.txt",
                store.run.run_id,
            )
        except (OSError, CampaignStorageError, RuntimeError, sqlite3.Error) as error:
            print(f"error while finalizing campaign: {error}", file=sys.stderr)
            if exit_code == 0:
                exit_code = 2
    return exit_code


def _request_interruption(_signum: int, _frame: object) -> None:
    """Turn supervisor termination into the normal resumable shutdown path."""

    raise KeyboardInterrupt


def main(argv: list[str] | None = None) -> int:
    # A non-interactive shell starts a background job with SIGINT ignored.  Set
    # explicit handlers here so both direct Ctrl-C and a service supervisor's
    # SIGTERM become the existing, resumable KeyboardInterrupt path.
    signal.signal(signal.SIGINT, _request_interruption)
    signal.signal(signal.SIGTERM, _request_interruption)
    args = parse_args(sys.argv[1:] if argv is None else argv)
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
