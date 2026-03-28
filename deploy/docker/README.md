# Docker Deployment

This deployment path packages the Dream Crates backend with `yt-dlp` and `ffmpeg`
so `/v1/playback/resolve` and `/v1/download/prepare` can resolve YouTube audio
URLs inside the container.

## Files

- `docker-compose.yml`: API + poller services
- `deploy/docker/dream-crates.env.example`: environment template for compose
- `backend/Dockerfile`: runtime image with Python, `yt-dlp`, and `ffmpeg`
- `backend/scripts/resolve_media_url.py`: resolver command invoked by the backend

## Quick Start

Copy the example env file:

```bash
cp deploy/docker/dream-crates.env.example deploy/docker/dream-crates.env
```

Fill in `STUDIO_YOUTUBE_API_KEY`, then start the stack:

```bash
docker compose up --build -d
```

Check the API:

```bash
curl -fsS http://127.0.0.1:8000/healthz
docker compose logs api --tail=100
```

Trigger a manual poll:

```bash
docker compose exec api python -c "import asyncio; from app.main import poll_once; asyncio.run(poll_once())"
```

## Notes

- The SQLite database is stored on the named volume at `/data/studiosample.db`.
- The poller service runs in a simple loop using `POLL_INTERVAL_SECONDS` and defaults to 300 seconds.
- The resolver command is preconfigured to call `/app/scripts/resolve_media_url.py`.
- If `yt-dlp` resolution fails, the backend falls back to `STUDIO_RESOLVER_FALLBACK_URL`.
