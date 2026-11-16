#!/bin/bash
# Removes Direct. With --all, also your rules, settings and activity log, for a fresh start.
# Everything goes to the Trash, so it can be put back.
set -euo pipefail

ALL=false
[ "${1:-}" = "--all" ] && ALL=true

pkill -x Direct || true

trash() {
  [ -e "$1" ] || return 0
  local name
  name="$(basename "$1")"
  mv "$1" "$HOME/.Trash/$name $(date +%H.%M.%S)"
  echo "Moved to Trash: $1"
}

trash /Applications/Direct.app
trash "$HOME/Applications/Direct.app"

if $ALL; then
  trash "$HOME/Library/Application Support/Direct"
  trash "$HOME/Library/Logs/Direct"
  defaults delete com.cnerd.direct 2>/dev/null && echo "Cleared settings (com.cnerd.direct)" || true
else
  echo "Kept your rules and settings. Run with --all to remove them too."
fi

echo
echo "If Direct was your default browser, check"
echo "System Settings > Desktop & Dock > Default web browser."
