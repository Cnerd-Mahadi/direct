#!/bin/bash
# Packs build/Direct.app into dist/Direct-<version>.dmg, with the usual drag-to-Applications window.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Direct.app
[ -d "$APP" ] || { echo "No $APP yet. Run scripts/build-app.sh first." >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="dist/Direct-$VERSION.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f "$DMG"
hdiutil create -quiet -volname "Direct $VERSION" -srcfolder "$STAGE" -format UDZO "$DMG"
echo "Made $DMG"
