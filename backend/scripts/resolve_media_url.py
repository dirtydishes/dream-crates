#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys

from app.services.ytdlp import pick_media_headers, pick_media_url, run_ytdlp_json


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Resolve a YouTube media URL via yt-dlp.")
    parser.add_argument("--video-id", required=True)
    parser.add_argument("--mode", choices=["stream", "download"], default="stream")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source_url = f"https://www.youtube.com/watch?v={args.video_id}"
    format_selector = "bestaudio[ext=m4a]/bestaudio/best" if args.mode == "stream" else "bestaudio/best"

    try:
        payload = run_ytdlp_json(
            [
                "--no-playlist",
                "--skip-download",
                "--format",
                format_selector,
                source_url,
            ]
        )
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    resolved_url = pick_media_url(payload)
    if not resolved_url:
        print("No playable media URL found in yt-dlp output", file=sys.stderr)
        return 1

    print(
        json.dumps(
            {
                "url": resolved_url,
                "headers": pick_media_headers(payload),
                "source": "yt-dlp",
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
