"""Process-isolated persistent worker lanes for high-core-count campaigns."""

from __future__ import annotations

import multiprocessing
import signal
import time
from dataclasses import dataclass
from multiprocessing.connection import Connection
from pathlib import Path
from typing import Any

from .campaign import Case
from .storage import CaseResult
from .worker import WorkerError, WorkerPair


@dataclass
class _Lane:
    lane: int
    command: Connection
    process: multiprocessing.Process
    started: float


def _emit(results: Any, message: tuple[str, int, object]) -> None:
    """Best-effort reporting for a child that may be shutting down."""

    try:
        results.put(message)
    except (BrokenPipeError, EOFError, OSError):
        pass


def _lane_process(
    lane: int,
    oracle_a: str,
    oracle_b: str,
    scratch_dir: str | None,
    startup_timeout: float,
    command: Connection,
    results: Any,
) -> None:
    """Own one worker pair in its own interpreter and therefore its own GIL."""

    pair: WorkerPair | None = None
    ready = False
    force_close = True

    def _interrupt(_signum: int, _frame: object) -> None:
        raise KeyboardInterrupt

    signal.signal(signal.SIGINT, _interrupt)
    signal.signal(signal.SIGTERM, _interrupt)
    try:
        pair = WorkerPair(
            lane,
            oracle_a,
            oracle_b,
            Path(scratch_dir) if scratch_dir is not None else None,
        )
        pair.start(startup_timeout)
        ready = True
        _emit(results, ("ready", lane, None))

        while True:
            kind, payload = command.recv()
            if kind == "run":
                case, oracle_timeout = payload
                _emit(results, ("result", lane, pair.run(case, oracle_timeout)))
            elif kind == "stop":
                force_close = bool(payload)
                return
            else:
                raise RuntimeError(f"unknown lane command: {kind!r}")
    except KeyboardInterrupt:
        return
    except Exception as error:
        event = "fatal" if ready else "startup_error"
        _emit(results, (event, lane, f"{type(error).__name__}: {error}"))
    finally:
        if pair is not None:
            try:
                pair.close(force=force_close)
            except Exception:
                pass
        try:
            command.close()
        except OSError:
            pass


class LanePool:
    """A parent-coordinated pool whose lanes compare payloads independently."""

    def __init__(
        self,
        jobs: int,
        oracle_a: str,
        oracle_b: str,
        scratch_dir: Path | None,
        startup_parallelism: int,
        startup_timeout: float,
    ):
        self._context = multiprocessing.get_context("spawn")
        self._jobs = jobs
        self._oracle_a = oracle_a
        self._oracle_b = oracle_b
        self._scratch_dir = str(scratch_dir) if scratch_dir is not None else None
        self._startup_parallelism = startup_parallelism
        self._startup_timeout = startup_timeout
        self._results = self._context.SimpleQueue()
        self._lanes: dict[int, _Lane] = {}
        self._closed = False

    @property
    def lane_count(self) -> int:
        return self._jobs

    def start(self) -> None:
        for first in range(0, self._jobs, self._startup_parallelism):
            batch = list(range(first, min(first + self._startup_parallelism, self._jobs)))
            for lane in batch:
                receiver, sender = self._context.Pipe(duplex=False)
                process = self._context.Process(
                    target=_lane_process,
                    args=(
                        lane,
                        self._oracle_a,
                        self._oracle_b,
                        self._scratch_dir,
                        self._startup_timeout,
                        receiver,
                        self._results,
                    ),
                    name=f"classic-fuzz-lane-{lane}",
                )
                process.start()
                receiver.close()
                self._lanes[lane] = _Lane(lane, sender, process, time.monotonic())
            self._await_startup(batch)

    def submit(self, lane: int, case: Case, oracle_timeout: float) -> None:
        if self._closed:
            raise WorkerError("cannot submit work after lane shutdown")
        try:
            self._lanes[lane].command.send(("run", (case, oracle_timeout)))
        except (BrokenPipeError, EOFError, OSError) as error:
            raise WorkerError(f"lane {lane} could not receive a case: {error}") from error

    def receive(self, timeout: float) -> tuple[int, CaseResult] | None:
        event = self._next_event(timeout)
        if event is None:
            self._raise_for_exited(self._lanes)
            return None
        kind, lane, payload = event
        if kind == "result":
            if not isinstance(payload, CaseResult):
                raise WorkerError(f"lane {lane} returned an invalid result")
            return lane, payload
        if kind in {"startup_error", "fatal"}:
            raise WorkerError(f"lane {lane} failed: {payload}")
        raise WorkerError(f"lane {lane} emitted unexpected event {kind!r}")

    def close(self, force: bool) -> None:
        if self._closed:
            return
        self._closed = True

        if force:
            for entry in self._lanes.values():
                if entry.process.is_alive():
                    entry.process.terminate()
        else:
            for entry in self._lanes.values():
                try:
                    entry.command.send(("stop", False))
                except (BrokenPipeError, EOFError, OSError):
                    pass

        self._join_until(time.monotonic() + 10.0)
        for entry in self._lanes.values():
            if entry.process.is_alive():
                entry.process.terminate()
        self._join_until(time.monotonic() + 10.0)

        for entry in self._lanes.values():
            try:
                entry.command.close()
            except OSError:
                pass
        self._results.close()

    def _await_startup(self, batch: list[int]) -> None:
        pending = set(batch)
        while pending:
            now = time.monotonic()
            for lane in pending:
                entry = self._lanes[lane]
                if entry.process.exitcode is not None:
                    raise WorkerError(
                        f"lane {lane} exited during startup with status "
                        f"{entry.process.exitcode}"
                    )
                if now - entry.started > self._startup_timeout * 2 + 5.0:
                    raise WorkerError(f"lane {lane} timed out during startup")

            event = self._next_event(0.1)
            if event is None:
                continue
            kind, lane, payload = event
            if kind == "ready" and lane in pending:
                pending.remove(lane)
                continue
            if kind in {"startup_error", "fatal"}:
                raise WorkerError(f"lane {lane} failed during startup: {payload}")
            raise WorkerError(f"lane {lane} emitted unexpected startup event {kind!r}")

    def _next_event(self, timeout: float) -> tuple[str, int, object] | None:
        reader = self._results._reader
        if not reader.poll(timeout):
            return None
        event = self._results.get()
        if not isinstance(event, tuple) or len(event) != 3:
            raise WorkerError(f"lane pool received malformed event {event!r}")
        kind, lane, payload = event
        if not isinstance(kind, str) or not isinstance(lane, int):
            raise WorkerError(f"lane pool received malformed event {event!r}")
        return kind, lane, payload

    def _raise_for_exited(self, lanes: object) -> None:
        for lane in lanes:
            entry = self._lanes[lane]
            if entry.process.exitcode is not None:
                raise WorkerError(
                    f"lane {lane} exited unexpectedly with status {entry.process.exitcode}"
                )

    def _join_until(self, deadline: float) -> None:
        for entry in self._lanes.values():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return
            entry.process.join(remaining)
