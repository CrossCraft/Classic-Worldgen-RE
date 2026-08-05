"""Persistent worker protocol client and incremental block-array comparison."""

from __future__ import annotations

import dataclasses
import hashlib
import os
import select
import shlex
import signal
import subprocess
import tempfile
import time
from collections.abc import Callable
from pathlib import Path
from typing import BinaryIO

from .campaign import Case, PROTOCOL_VERSION
from .storage import CaseResult

CHUNK_SIZE = 1 << 20
MAX_HEADER_BYTES = 4_096
STDERR_TAIL_BYTES = 4_096
MAX_STDERR_FILE_BYTES = 64 * 1_024


class WorkerError(RuntimeError):
    """A worker failed, timed out, or violated the v2 protocol."""


class _PipeReader:
    """Unbuffered deadline-aware reads that preserve payload bytes after headers."""

    def __init__(self, pipe: object, label: str):
        self._pipe = pipe
        self._fd = pipe.fileno()  # type: ignore[attr-defined]
        self._label = label
        self._buffer = bytearray()

    def read_line(self, deadline: float) -> bytes:
        while True:
            newline = self._buffer.find(b"\n")
            if newline >= 0:
                line = bytes(self._buffer[:newline])
                del self._buffer[: newline + 1]
                return line
            if len(self._buffer) > MAX_HEADER_BYTES:
                raise WorkerError(f"{self._label} emitted an oversized protocol header")
            self._buffer.extend(self._read_some(deadline))

    def copy_exact(
        self,
        count: int,
        deadline: float,
        consume: Callable[[bytes], None],
    ) -> None:
        remaining = count
        while remaining:
            if self._buffer:
                chunk = bytes(self._buffer[:remaining])
                del self._buffer[: len(chunk)]
            else:
                chunk = self._read_some(deadline, min(CHUNK_SIZE, remaining))
                if len(chunk) > remaining:
                    self._buffer.extend(chunk[remaining:])
                    chunk = chunk[:remaining]
            consume(chunk)
            remaining -= len(chunk)

    def _read_some(self, deadline: float, max_bytes: int = CHUNK_SIZE) -> bytes:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise WorkerError(f"{self._label} timed out waiting for protocol data")
        ready, _, _ = select.select([self._fd], [], [], remaining)
        if not ready:
            raise WorkerError(f"{self._label} timed out waiting for protocol data")
        try:
            data = os.read(self._fd, max_bytes)
        except OSError as error:
            raise WorkerError(f"{self._label} could not read protocol data: {error}") from error
        if not data:
            raise WorkerError(f"{self._label} closed stdout unexpectedly")
        return data


@dataclasses.dataclass(frozen=True)
class _Generation:
    sha256: bytes
    seconds: float


@dataclasses.dataclass(frozen=True)
class _Comparison:
    sha256: bytes
    seconds: float
    differing: int
    first_offset: int | None
    first_a: int | None
    first_b: int | None


class WorkerProcess:
    """One serial v2 worker process with a private stdin/stdout stream."""

    def __init__(
        self, command_template: str, lane: int, oracle_name: str, stderr_path: Path
    ):
        self.command_template = command_template
        self.lane = lane
        self.oracle_name = oracle_name
        self.stderr_path = stderr_path
        self.process: subprocess.Popen[bytes] | None = None
        self.reader: _PipeReader | None = None
        self._stderr_stream: BinaryIO | None = None

    @property
    def label(self) -> str:
        return f"oracle {self.oracle_name} worker {self.lane}"

    def start(self, timeout: float) -> None:
        try:
            command = self.command_template.format(worker=self.lane)
        except (IndexError, KeyError, ValueError) as error:
            raise WorkerError(f"{self.label} command template is invalid: {error}") from error
        try:
            argv = shlex.split(command)
        except ValueError as error:
            raise WorkerError(f"{self.label} command cannot be parsed: {error}") from error
        if not argv:
            raise WorkerError(f"{self.label} command is empty")
        try:
            descriptor = os.open(
                self.stderr_path,
                os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_APPEND,
                0o600,
            )
            self._stderr_stream = os.fdopen(descriptor, "wb", buffering=0)
            self.process = subprocess.Popen(
                argv,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=self._stderr_stream,
                bufsize=0,
                start_new_session=True,
            )
        except OSError as error:
            if self._stderr_stream is not None:
                self._stderr_stream.close()
                self._stderr_stream = None
            raise WorkerError(f"{self.label} failed to launch: {error}") from error
        assert self.process.stdout is not None
        self.reader = _PipeReader(self.process.stdout, self.label)
        try:
            line = self.reader.read_line(time.monotonic() + timeout)
        except WorkerError as error:
            self._raise_with_diagnostics(str(error))
        if line != f"READY {PROTOCOL_VERSION}".encode("ascii"):
            self._raise_with_diagnostics(
                f"{self.label} sent invalid startup header {line!r}"
            )

    def generate_to_file(self, case: Case, path: Path, timeout: float) -> _Generation:
        started = time.monotonic()
        deadline = started + timeout
        self._request(case, deadline)
        digest = hashlib.sha256()
        try:
            with path.open("wb") as output:
                self._read_payload(case, deadline, lambda chunk: _write_hash(
                    output, digest, chunk
                ))
        except OSError as error:
            raise WorkerError(f"{self.label} could not spool its block array: {error}") from error
        return _Generation(digest.digest(), time.monotonic() - started)

    def compare_file(self, case: Case, path: Path, timeout: float) -> _Comparison:
        started = time.monotonic()
        deadline = started + timeout
        self._request(case, deadline)
        digest = hashlib.sha256()
        differing = 0
        first_offset: int | None = None
        first_a: int | None = None
        first_b: int | None = None
        offset = 0
        try:
            with path.open("rb") as expected:
                def consume(chunk: bytes) -> None:
                    nonlocal differing, first_offset, first_a, first_b, offset
                    other = expected.read(len(chunk))
                    if len(other) != len(chunk):
                        raise WorkerError(
                            f"{self.label} comparison spool was shorter than its payload"
                        )
                    digest.update(chunk)
                    if other != chunk:
                        for local, (byte_a, byte_b) in enumerate(zip(other, chunk)):
                            if byte_a != byte_b:
                                differing += 1
                                if first_offset is None:
                                    first_offset = offset + local
                                    first_a = byte_a
                                    first_b = byte_b
                    offset += len(chunk)

                self._read_payload(case, deadline, consume)
                if expected.read(1):
                    raise WorkerError(
                        f"{self.label} comparison spool was longer than its payload"
                    )
        except OSError as error:
            raise WorkerError(f"{self.label} could not read comparison spool: {error}") from error
        return _Comparison(
            digest.digest(),
            time.monotonic() - started,
            differing,
            first_offset,
            first_a,
            first_b,
        )

    def _request(self, case: Case, deadline: float) -> None:
        process = self._require_process()
        if process.poll() is not None:
            self._raise_with_diagnostics(
                f"{self.label} exited with status {process.returncode}"
            )
        self._trim_stderr()
        assert process.stdin is not None and self.reader is not None
        request = (
            f"CASE {case.sequence} {case.seed} {case.width} {case.height}"
            f" {case.depth}\n"
        ).encode("ascii")
        try:
            process.stdin.write(request)
            process.stdin.flush()
        except (BrokenPipeError, OSError) as error:
            self._raise_with_diagnostics(
                f"{self.label} could not send a request: {error}"
            )
        try:
            header = self.reader.read_line(deadline)
        except WorkerError as error:
            self._raise_with_diagnostics(str(error))
        pieces = header.split()
        if len(pieces) == 2 and pieces[0] == b"FAIL":
            self._raise_with_diagnostics(
                f"{self.label} rejected case {case.sequence}"
            )
        if len(pieces) != 3 or pieces[0] != b"OK":
            self._raise_with_diagnostics(
                f"{self.label} sent invalid response header {header!r}"
            )
        try:
            response_id = int(pieces[1])
            byte_count = int(pieces[2])
        except ValueError:
            self._raise_with_diagnostics(
                f"{self.label} sent non-integer response header {header!r}"
            )
        if response_id != case.sequence:
            self._raise_with_diagnostics(
                f"{self.label} answered case {response_id}, expected {case.sequence}"
            )
        if byte_count != case.volume:
            self._raise_with_diagnostics(
                f"{self.label} declared {byte_count} bytes, expected {case.volume}"
            )

    def _read_payload(
        self, case: Case, deadline: float, consume: Callable[[bytes], None]
    ) -> None:
        assert self.reader is not None
        try:
            self.reader.copy_exact(case.volume, deadline, consume)
        except WorkerError as error:
            self._raise_with_diagnostics(str(error))

    def shutdown(self, timeout: float = 5.0) -> None:
        process = self.process
        if process is None:
            return
        try:
            if process.poll() is None and process.stdin is not None and self.reader is not None:
                process.stdin.write(b"QUIT\n")
                process.stdin.flush()
                response = self.reader.read_line(time.monotonic() + timeout)
                if response != b"BYE":
                    raise WorkerError(f"{self.label} sent invalid shutdown header {response!r}")
                process.wait(timeout=timeout)
        except (BrokenPipeError, OSError, subprocess.TimeoutExpired, WorkerError):
            self.terminate()
        finally:
            self._close_pipes()

    def terminate(self) -> None:
        process = self.process
        if process is None:
            return
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except (OSError, ProcessLookupError):
                process.terminate()
            try:
                process.wait(timeout=3.0)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except (OSError, ProcessLookupError):
                    process.kill()
                try:
                    process.wait(timeout=3.0)
                except subprocess.TimeoutExpired:
                    pass
        self._close_pipes()

    def _close_pipes(self) -> None:
        process = self.process
        if process is not None:
            for pipe in (process.stdin, process.stdout):
                if pipe is not None:
                    try:
                        pipe.close()
                    except OSError:
                        pass
        if self._stderr_stream is not None:
            try:
                self._stderr_stream.close()
            except OSError:
                pass
            self._stderr_stream = None

    def _require_process(self) -> subprocess.Popen[bytes]:
        if self.process is None:
            raise WorkerError(f"{self.label} was not started")
        return self.process

    def _raise_with_diagnostics(self, message: str) -> None:
        detail = self._stderr_tail()
        if detail:
            message = f"{message}; stderr tail: {detail}"
        raise WorkerError(message)

    def _stderr_tail(self) -> str:
        try:
            with self.stderr_path.open("rb") as stream:
                stream.seek(0, os.SEEK_END)
                size = stream.tell()
                stream.seek(max(0, size - STDERR_TAIL_BYTES))
                return stream.read().decode("utf-8", "replace").strip()
        except OSError:
            return ""

    def _trim_stderr(self) -> None:
        """Bound benign worker logging without losing a just-emitted failure tail."""

        try:
            if self.stderr_path.stat().st_size > MAX_STDERR_FILE_BYTES:
                with self.stderr_path.open("r+b") as stream:
                    stream.truncate(0)
        except OSError:
            pass


def _write_hash(output: BinaryIO, digest: "hashlib._Hash", chunk: bytes) -> None:
    output.write(chunk)
    digest.update(chunk)


class WorkerPair:
    """A serial A/B lane that owns two workers and one reusable scratch directory."""

    def __init__(
        self,
        lane: int,
        oracle_a: str,
        oracle_b: str,
        scratch_dir: Path | None = None,
    ):
        self.lane = lane
        self._temporary = tempfile.TemporaryDirectory(
            prefix=f"classic-fuzz-v2-{lane}-", dir=scratch_dir
        )
        temporary_path = Path(self._temporary.name)
        self.a = WorkerProcess(oracle_a, lane, "A", temporary_path / "a.stderr")
        self.b = WorkerProcess(oracle_b, lane, "B", temporary_path / "b.stderr")
        self._spool = temporary_path / "a.blocks"

    def start(self, timeout: float) -> None:
        try:
            self.a.start(timeout)
            self.b.start(timeout)
        except Exception:
            self.close(force=True)
            raise

    def run(self, case: Case, timeout: float) -> CaseResult:
        started = time.monotonic()
        try:
            output_a = self.a.generate_to_file(case, self._spool, timeout)
        except WorkerError as error:
            return CaseResult(
                case=case,
                lane=self.lane,
                seconds=time.monotonic() - started,
                a_seconds=None,
                b_seconds=None,
                outcome="error",
                error_a=str(error),
            )
        try:
            output_b = self.b.compare_file(case, self._spool, timeout)
        except WorkerError as error:
            return CaseResult(
                case=case,
                lane=self.lane,
                seconds=time.monotonic() - started,
                a_seconds=output_a.seconds,
                b_seconds=None,
                outcome="error",
                error_b=str(error),
            )
        if output_b.differing == 0:
            return CaseResult(
                case=case,
                lane=self.lane,
                seconds=time.monotonic() - started,
                a_seconds=output_a.seconds,
                b_seconds=output_b.seconds,
                outcome="match",
            )
        assert output_b.first_offset is not None
        assert output_b.first_a is not None and output_b.first_b is not None
        row = case.width
        slab = row * case.depth
        y, rest = divmod(output_b.first_offset, slab)
        z, x = divmod(rest, row)
        return CaseResult(
            case=case,
            lane=self.lane,
            seconds=time.monotonic() - started,
            a_seconds=output_a.seconds,
            b_seconds=output_b.seconds,
            outcome="mismatch",
            differing=output_b.differing,
            first_offset=output_b.first_offset,
            first_x=x,
            first_y=y,
            first_z=z,
            first_a=output_b.first_a,
            first_b=output_b.first_b,
            a_sha256=output_a.sha256,
            b_sha256=output_b.sha256,
        )

    def close(self, force: bool = False) -> None:
        if force:
            self.a.terminate()
            self.b.terminate()
        else:
            self.a.shutdown()
            self.b.shutdown()
        self._temporary.cleanup()
