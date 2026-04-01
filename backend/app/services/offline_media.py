from __future__ import annotations

from collections import defaultdict
from pathlib import Path
import os
from subprocess import run
import tempfile
import threading

from app.services.resolver import ResolveResult


class OfflineMediaError(RuntimeError):
    pass


class OfflineMediaCache:
    def __init__(self, cache_directory: str | Path):
        self.cache_directory = Path(cache_directory)
        self._locks: defaultdict[str, threading.Lock] = defaultdict(threading.Lock)

    def resolve(self, sample_id: str, source: ResolveResult) -> Path:
        target = self.cache_directory / f"{sample_id}.m4a"
        if self._is_usable_file(target):
            return target

        with self._locks[sample_id]:
            if self._is_usable_file(target):
                return target

            self.cache_directory.mkdir(parents=True, exist_ok=True)
            fd, temporary_name = tempfile.mkstemp(
                prefix=f"{sample_id}-",
                suffix=".m4a",
                dir=self.cache_directory,
            )
            os.close(fd)
            temporary_path = Path(temporary_name)

            try:
                self._transcode(source=source, destination=temporary_path)
                if not self._is_usable_file(temporary_path):
                    raise OfflineMediaError("The transcoded download was empty or incomplete.")
                temporary_path.replace(target)
            except Exception:
                temporary_path.unlink(missing_ok=True)
                raise

        return target

    def _transcode(self, source: ResolveResult, destination: Path) -> None:
        command = [
            "ffmpeg",
            "-nostdin",
            "-v",
            "error",
            "-y",
        ]
        headers = _ffmpeg_headers(source.headers)
        if headers:
            command.extend(["-headers", headers])
        command.extend(
            [
                "-i",
                source.url,
                "-vn",
                "-map_metadata",
                "-1",
                "-c:a",
                "aac",
                "-b:a",
                "160k",
                "-movflags",
                "+faststart",
                "-f",
                "ipod",
                str(destination),
            ]
        )

        completed = run(
            command,
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            message = completed.stderr.strip() or "ffmpeg failed while preparing offline audio."
            raise OfflineMediaError(message)

    def _is_usable_file(self, path: Path) -> bool:
        try:
            return path.is_file() and path.stat().st_size > 1024
        except OSError:
            return False


def _ffmpeg_headers(headers: dict[str, str]) -> str:
    if not headers:
        return ""
    return "".join(f"{name}: {value}\r\n" for name, value in headers.items())
