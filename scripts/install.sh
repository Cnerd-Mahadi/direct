#!/bin/bash
# Builds Direct.app, installs it to ~/Applications, seeds rules.json if missing, and starts it.
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
codesign --force --sign - "$APP"

DEST="$HOME/Applications/Direct.app"
pkill -x Direct || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"

RULES="$HOME/Library/Application Support/Direct/rules.json"
if [ ! -f "$RULES" ]; then
  mkdir -p "$(dirname "$RULES")"
  cp Support/rules.example.json "$RULES"
  echo "Seeded $RULES"
fi

open -g "$DEST"
echo "Installed $DEST"
