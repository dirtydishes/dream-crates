#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEME="${SCHEME:-StudioSampleApp}"
DEVICE_NAME="${DEVICE_NAME:-kellcd}"
DEVICE_ID="${DEVICE_ID:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-6263528F3C}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/StudioSampleDerived}"

xcodegen generate >/dev/null

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(xcodebuild -showdestinations -project 'dream crates.xcodeproj' -scheme "$SCHEME" \
    | awk -v target_name="$DEVICE_NAME" -F'id:' '$0 ~ "platform:iOS" && $0 ~ ("name:" target_name) {print $2; exit}' \
    | cut -d',' -f1 \
    | xargs)"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "error: could not find iOS device '$DEVICE_NAME' for scheme $SCHEME" >&2
  exit 1
fi

set -x
xcodebuild \
  -project 'dream crates.xcodeproj' \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=${DEVICE_ID}" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphoneos/StudioSampleApp.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: build succeeded but app not found at $APP_PATH" >&2
  exit 1
fi

echo "Built app: $APP_PATH"
