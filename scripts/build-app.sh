#!/bin/bash
# Builds build/Direct.app from source. install.sh and release.sh both start here.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Direct

APP=build/Direct.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Direct "$APP/Contents/MacOS/Direct"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Support/Fonts "$APP/Contents/Resources/Fonts"
# Ad hoc signature: fine on this Mac. Other Macs would need a Developer ID and notarization.
codesign --force --sign - "$APP"
echo "Built $APP ($(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist"))"
