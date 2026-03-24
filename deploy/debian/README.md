# Debian Deployment

This folder contains a single-node deployment layout for the Dream Crates backend on Debian.

## Services

- `dream-crates-api.service`: FastAPI HTTP API via `uvicorn`
- `dream-crates-poller.service`: one-shot YouTube poller job
- `dream-crates-poller.timer`: recurring poller trigger every 5 minutes
- `nginx/dream-crates.conf`: reverse proxy site config

## Host Preparation

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv nginx
sudo useradd --system --create-home --shell /usr/sbin/nologin dream-crates
sudo mkdir -p /opt/dream-crates
sudo chown -R dream-crates:dream-crates /opt/dream-crates
```

Clone the repo to `/opt/dream-crates/app` and create the backend virtualenv:

```bash
sudo -u dream-crates git clone <repo-url> /opt/dream-crates/app
cd /opt/dream-crates/app/backend
sudo -u dream-crates python3 -m venv .venv
sudo -u dream-crates .venv/bin/pip install -e .[dev]
```

## Environment

Copy `deploy/debian/dream-crates.env.example` to `/etc/dream-crates.env` and fill in secrets.

The playback resolver supports either a static fallback URL or a command-based resolver via `STUDIO_RESOLVER_COMMAND`.
That command must print JSON like:

```json
{"url":"https://...","expiresAt":"2026-01-01T00:00:00Z","source":"command"}
```

## Install systemd units

```bash
sudo cp deploy/debian/systemd/*.service deploy/debian/systemd/*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now dream-crates-api.service
sudo systemctl enable --now dream-crates-poller.timer
```

## nginx

Copy `deploy/debian/nginx/dream-crates.conf` to `/etc/nginx/sites-available/dream-crates.conf`, adjust `server_name`, then enable it:

```bash
sudo ln -s /etc/nginx/sites-available/dream-crates.conf /etc/nginx/sites-enabled/dream-crates.conf
sudo nginx -t
sudo systemctl reload nginx
```

## Smoke Checks

```bash
curl -fsS http://127.0.0.1:8000/healthz
cd /opt/dream-crates/app
./scripts/api-smoke.sh
```
