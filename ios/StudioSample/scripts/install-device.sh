#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DEVICE_NAME="${DEVICE_NAME:-kellcd}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/StudioSampleDerived}"
BUNDLE_ID="${BUNDLE_ID:-com.dreamcrates.studiosample}"

"$ROOT_DIR/scripts/build-device.sh"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphoneos/StudioSampleApp.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found at $APP_PATH" >&2
  exit 1
fi

set -x
xcrun devicectl device install app --device "$DEVICE_NAME" "$APP_PATH"
xcrun devicectl device process launch --device "$DEVICE_NAME" "$BUNDLE_ID"
