#!/bin/bash
# Cuts a release: sets the version, tests, builds the DMG, tags, pushes, and publishes it on GitHub.
# Usage: scripts/release.sh 0.3
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: scripts/release.sh <version>, for example 0.3}"
TAG="v$VERSION"
fail() { echo "$1" >&2; exit 1; }

[ "$(git branch --show-current)" = main ] || fail "Releases come from main."
[ -z "$(git status --porcelain)" ] || fail "Commit or stash your changes first."
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "$TAG already exists."

# Publish as the repo's owner, whichever GitHub account gh has active.
OWNER="$(git remote get-url origin | sed -E 's#.*github.com[:/]([^/]+)/.*#\1#')"
GH_TOKEN="$(gh auth token --user "$OWNER" 2>/dev/null)" || fail "gh isn't logged in as $OWNER. Run: gh auth login"
export GH_TOKEN

PLIST=Support/Info.plist
trap 'git checkout -q -- "$PLIST"' ERR  # a failed test or build leaves the version untouched
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $(( $(git rev-list --count HEAD) + 1 ))" "$PLIST"

swift test
scripts/build-app.sh
scripts/make-dmg.sh

git commit -q -m "Release $VERSION" "$PLIST"
trap - ERR
git tag -a "$TAG" -m "Direct $VERSION"
git push -q origin main "$TAG"
gh release create "$TAG" "dist/Direct-$VERSION.dmg" --title "Direct $VERSION" --generate-notes
