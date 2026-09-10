#!/bin/bash
set -euo pipefail
porch_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$porch_root"
xcodegen generate
# Signing and distribution are handled by the operator's own installation workflow.
xcodebuild -project Porch.xcodeproj -scheme Porch -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$porch_root/.build-uat/Porch.xcarchive" \
  -derivedDataPath "$porch_root/.build-uat/DerivedData" CODE_SIGNING_ALLOWED=NO archive
printf '%s\n' "$porch_root/.build-uat/Porch.xcarchive/Products/Applications/Porch.app"
