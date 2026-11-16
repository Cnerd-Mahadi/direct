import AppKit

if Snapshot.runIfRequested() { exit(0) }

// NSApplication holds its delegate weakly, so this global is what keeps it alive.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
