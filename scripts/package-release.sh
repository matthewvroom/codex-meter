#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="${1:-$ROOT/dist}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ARCHIVE="Codex-Meter-$VERSION.zip"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

PAYLOAD="$STAGE/Codex Meter $VERSION"
"$ROOT/scripts/build-app.sh" "$PAYLOAD"
cp "$ROOT/Resources/INSTALL.txt" "$ROOT/LICENSE" "$PAYLOAD/"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$PAYLOAD" "$STAGE/$ARCHIVE"

mkdir "$STAGE/check"
unzip -q "$STAGE/$ARCHIVE" -d "$STAGE/check"
EXTRACTED="$STAGE/check/Codex Meter $VERSION"
APP="$EXTRACTED/Codex Meter.app"
for ARCH in arm64 x86_64; do
  xcrun lipo "$APP/Contents/MacOS/CodexMeter" -verify_arch "$ARCH"
  xcrun lipo "$EXTRACTED/codex-meter" -verify_arch "$ARCH"
done
codesign --verify --deep --strict "$APP"
codesign --verify --strict "$EXTRACTED/codex-meter"
ICON="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP/Contents/Info.plist")"
test -s "$APP/Contents/Resources/$ICON"
cmp "$ROOT/Resources/CreatorSignature.svg" "$APP/Contents/Resources/CreatorSignature.svg"
cmp "$ROOT/Resources/HeaderIcon.png" "$APP/Contents/Resources/HeaderIcon.png"
cmp "$ROOT/Resources/INSTALL.txt" "$EXTRACTED/INSTALL.txt"
cmp "$ROOT/LICENSE" "$EXTRACTED/LICENSE"
"$EXTRACTED/codex-meter" --help >/dev/null

mkdir -p "$OUTPUT"
mv "$STAGE/$ARCHIVE" "$OUTPUT/$ARCHIVE"
shasum -a 256 "$OUTPUT/$ARCHIVE"
