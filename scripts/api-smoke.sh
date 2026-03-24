#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"
DEVICE_ID="${DEVICE_ID:-local-device}"

check() {
  local name="$1"
  local url="$2"
  echo "==> $name"
  curl -fsS "$url" >/dev/null
}

check "health" "$BASE_URL/healthz"
check "defaults" "$BASE_URL/v1/channels/defaults"
check "samples" "$BASE_URL/v1/samples"
check "library" "$BASE_URL/v1/users/$DEVICE_ID/library"

echo "API smoke checks passed against $BASE_URL"
