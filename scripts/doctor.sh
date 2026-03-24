#!/usr/bin/env bash
set -euo pipefail

MISSING=0
for cmd in bd xcodebuild xcodegen xcrun python3; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "ok: $cmd"
  else
    echo "missing: $cmd"
    MISSING=1
  fi
done

if command -v xcrun >/dev/null 2>&1; then
  echo
  echo "Connected/paired devices:"
  xcrun devicectl list devices || true
fi

if [[ "$MISSING" -ne 0 ]]; then
  exit 1
fi
