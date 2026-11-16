# Direct

Direct is a default browser for macOS that sends each link to the right browser and profile. You set rules in plain menus, such as "links from Teams open in my Work profile". Hold Option while clicking a link to choose where it opens. Press ⌃⌥D to send the last link somewhere else.

## Install

1. Download the latest `Direct-<version>.dmg` from [Releases](../../releases).
2. Open it and drag **Direct** to **Applications**.
3. Open Direct, then click **Make Direct the default** in its window.

Direct is signed ad hoc, not with an Apple Developer ID. It opens normally on the Mac that built it. On another Mac, the first launch needs a right-click and **Open**.

## Develop

You need macOS 14 or later and Xcode or the Swift 6 toolchain.

```bash
swift test                 # run the tests
scripts/install.sh         # build from source and replace /Applications/Direct.app
```

To check the screens without bringing Direct forward, render them to PNGs:

```bash
DIRECT_SNAPSHOT=/tmp/direct-snap build/Direct.app/Contents/MacOS/Direct
```

## Release

```bash
scripts/release.sh 0.3
```

The script sets the version, runs the tests, builds `dist/Direct-0.3.dmg`, tags `v0.3`, pushes, and publishes the DMG as a GitHub release. It stops if the tree has uncommitted changes or the tag exists. To build a DMG without releasing, run `scripts/build-app.sh` and then `scripts/make-dmg.sh`.

## Uninstall

```bash
scripts/uninstall.sh         # remove the app, keep rules and settings
scripts/uninstall.sh --all   # also remove rules, settings and the activity log
```

Removed files go to the Trash.

## Where things live

| What | Where |
| --- | --- |
| Rules | `~/Library/Application Support/Direct/rules.json` |
| Activity log | `~/Library/Logs/Direct/activity.jsonl` |
| Browser order and hidden browsers | `defaults read com.cnerd.direct` |

## Layout

- `Sources/DirectCore` holds the routing logic, the rules file format, and browser profile discovery. It has no UI and is fully tested.
- `Sources/Direct` holds the app: the menu bar item, the window, the picker, and opening links.
- `Support` holds `Info.plist`, the app icon, and the bundled fonts (Figtree and EB Garamond, both under the SIL Open Font License).
