#!/bin/bash
# For development: builds Direct from source, replaces /Applications/Direct.app, and starts it.
# To install a released version instead, open its DMG and drag Direct to Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh

DEST=/Applications/Direct.app
pkill -x Direct || true
rm -rf "$DEST"
cp -R build/Direct.app "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
open -g "$DEST"
echo "Installed $DEST"
