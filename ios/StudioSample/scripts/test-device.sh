#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required (brew install xcodegen)" >&2
  exit 1
fi

xcodegen generate >/dev/null

SCHEME="${SCHEME:-StudioSampleApp}"
DEVICE_ID="${DEVICE_ID:-}"
DEVICE_NAME="${DEVICE_NAME:-kellcd}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/StudioSampleDerived}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-6263528F3C}"

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(xcodebuild -showdestinations -project 'dream crates.xcodeproj' -scheme "$SCHEME" \
    | awk -v target_name="$DEVICE_NAME" -F'id:' '$0 ~ "platform:iOS" && $0 ~ ("name:" target_name) {print $2; exit}' \
    | cut -d',' -f1 \
    | xargs)"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "error: could not find an iOS device destination with name '$DEVICE_NAME'" >&2
  exit 1
fi

XCODEBUILD_ARGS=(
  -project 'dream crates.xcodeproj'
  -scheme "$SCHEME"
  -destination "id=${DEVICE_ID}"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -allowProvisioningUpdates
  -allowProvisioningDeviceRegistration
  CODE_SIGN_STYLE=Automatic
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}"
)

set -x
xcodebuild "${XCODEBUILD_ARGS[@]}" test
