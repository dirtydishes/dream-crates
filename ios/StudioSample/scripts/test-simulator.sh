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
DESTINATION_ID="${DESTINATION_ID:-}"

if [[ -z "$DESTINATION_ID" ]]; then
  DESTINATION_ID="$(xcodebuild -showdestinations -project 'dream crates.xcodeproj' -scheme "$SCHEME" \
    | awk -F'id:' '/platform:iOS Simulator/ && $0 !~ /placeholder/ && $0 ~ /name:iPhone/{print $2; exit}' \
    | cut -d',' -f1 \
    | xargs)"
fi

if [[ -z "$DESTINATION_ID" ]]; then
  DESTINATION_ID="$(xcodebuild -showdestinations -project 'dream crates.xcodeproj' -scheme "$SCHEME" \
    | awk -F'id:' '/platform:iOS Simulator/ && $0 !~ /placeholder/{print $2; exit}' \
    | cut -d',' -f1 \
    | xargs)"
fi

if [[ -z "$DESTINATION_ID" ]]; then
  echo "error: could not find an iOS Simulator destination for scheme $SCHEME" >&2
  exit 1
fi

set -x
xcodebuild \
  -project 'dream crates.xcodeproj' \
  -scheme "$SCHEME" \
  -destination "id=${DESTINATION_ID}" \
  test
