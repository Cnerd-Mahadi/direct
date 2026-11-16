import AppKit
import SwiftUI
import DirectCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let lastResort = Target(browser: "com.apple.Safari")

    /// Last app other than Direct to come to the front. Used when the event's sender is unknown.
    private var lastOtherApp: String?
    private var statusItem: NSStatusItem?
    private var rulesWindow: NSWindow?
    private let store = RulesStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Direct")
        let menu = NSMenu()
        menu.addItem(withTitle: "Rules…", action: #selector(showRules), keyEquivalent: ",")
        menu.addItem(withTitle: "Show Activity Log in Finder", action: #selector(showActivityLog), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Direct", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item.menu = menu
        statusItem = item
    }

    /// Launching Direct.app again while it runs opens the rules window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showRules()
        return false
    }

    @objc func showRules() {
        store.load()
        if rulesWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: RulesView(store: store)))
            window.title = "Direct"
            window.setContentSize(NSSize(width: 900, height: 600))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            rulesWindow = window
        }
        // A Dock icon and ⌘-Tab while the window is open, so it can't get lost behind other apps.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        rulesWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showActivityLog() {
        NSWorkspace.shared.activateFileViewerSelecting([Paths.activityLog])
    }

    /// Direct has no visible menu bar, but text fields still need these key equivalents.
    /// There is deliberately no ⌘Q: quitting would stop links from being routed.
    private static func makeMainMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let main = NSMenu()
        for submenu in [NSMenu(title: "Direct"), edit, window] {
            let item = main.addItem(withTitle: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
        }
        return main
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        remember(NSWorkspace.shared.frontmostApplication)
    }

    @objc private func appDidActivate(_ note: Notification) {
        remember(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
    }

    private func remember(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != getpid(), let id = app.bundleIdentifier else { return }
        lastOtherApp = id
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text) else { return }
        let senderPID = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        if let senderPID, senderPID != getpid(),
           let sender = NSRunningApplication(processIdentifier: senderPID)?.bundleIdentifier {
            route(url, sourceApp: sender, via: .sender)
        } else {
            route(url, sourceApp: lastOtherApp, via: .frontmost)
        }
    }

    /// HTML files opened with Direct (it registers as a browser, so Finder may send them).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { route(url, sourceApp: lastOtherApp, via: .frontmost) }
    }

    private func route(_ url: URL, sourceApp: String?, via: ActivityEntry.SourceVia) {
        var problems: [String] = []
        let rules: RuleSet
        do {
            rules = try RuleSet.load(from: Paths.rules)
        } catch {
            problems.append("Could not read \(Paths.rules.path): \(error)")
            rules = RuleSet(rules: [], fallback: Self.lastResort)
        }
        let decision = rules.route(Link(url: url, sourceApp: sourceApp))

        Task {
            var method: OpenMethod?
            do {
                method = try await Opener.open(url, in: decision.target)
            } catch {
                problems.append("\(error)")
                method = try? await Opener.open(url, in: Self.lastResort)
            }
            ActivityLog.append(ActivityEntry(
                url: url.absoluteString,
                sourceApp: sourceApp,
                sourceVia: via,
                rule: decision.rulePath,
                target: decision.target,
                method: method,
                error: problems.isEmpty ? nil : problems.joined(separator: " | ")
            ))
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
