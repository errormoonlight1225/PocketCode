#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null || ! command -v xcodegen >/dev/null; then
  echo '需要 macOS、Xcode 和 XcodeGen（brew install xcodegen）。' >&2
  exit 1
fi
# Xcode 16 still includes the iOS 12 deployment target; Xcode 26 does not.
for candidate in /Applications/Xcode_16.4.app /Applications/Xcode_16.3.app /Applications/Xcode_16.2.app; do
  if [ -d "$candidate" ]; then export DEVELOPER_DIR="$candidate/Contents/Developer"; break; fi
done
xcodebuild -version
xcrun swiftc App/Core.swift App/ANSIScreen.swift Tests/main.swift -o /tmp/pocket-native-tests
/tmp/pocket-native-tests
xcodegen generate
xcodebuild -project CodeSpacePocket.xcodeproj -scheme CodeSpacePocket \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir -p dist
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/Payload"
cp -R build/Build/Products/Release-iphoneos/CodeSpacePocket.app "$staging/Payload/"
# An unsigned IPA is an intermediate for a signing tool, not directly installable.
output="$PWD/dist/CodeSpacePocket-unsigned.ipa"
rm -f "$output"
(cd "$staging" && /usr/bin/zip -qry "$output" Payload)
echo "Created: $output (UNSIGNED; signing is required before installation)"
