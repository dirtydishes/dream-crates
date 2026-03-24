#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

xcodegen generate >/dev/null
xcodebuild -showdestinations -project 'dream crates.xcodeproj' -scheme StudioSampleApp
