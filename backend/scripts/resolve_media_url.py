#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from subprocess import CompletedProcess, run
import sys

from app.services.ytdlp import pick_media_url


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Resolve a YouTube media URL via yt-dlp.")
    parser.add_argument("--video-id", required=True)
    parser.add_argument("--mode", choices=["stream", "download"], default="stream")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source_url = f"https://www.youtube.com/watch?v={args.video_id}"
    format_selector = "bestaudio[ext=m4a]/bestaudio/best" if args.mode == "stream" else "bestaudio/best"

    completed: CompletedProcess[str] = run(
        [
            "yt-dlp",
            "--dump-single-json",
            "--no-playlist",
            "--no-warnings",
            "--skip-download",
            "--format",
            format_selector,
            source_url,
        ],
        check=False,
        capture_output=True,
        text=True,
    )

    if completed.returncode != 0:
        print(completed.stderr.strip() or "yt-dlp failed", file=sys.stderr)
        return 1

    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError:
        print("yt-dlp returned invalid JSON", file=sys.stderr)
        return 1

    resolved_url = pick_media_url(payload)
    if not resolved_url:
        print("No playable media URL found in yt-dlp output", file=sys.stderr)
        return 1

    print(
        json.dumps(
            {
                "url": resolved_url,
                "source": "yt-dlp",
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
