import AppKit
import Carbon
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
    private let picker = PickerController()
    /// The last link Direct opened and how, for the reopen shortcut.
    private var lastLink: DirectCore.Link?
    private var lastDecision: Decision?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Direct")
        let menu = NSMenu()
        menu.addItem(withTitle: "Rules…", action: #selector(showRules), keyEquivalent: ",")
        let reopen = menu.addItem(withTitle: "Reopen Last Link…", action: #selector(reopenLastLink), keyEquivalent: "d")
        reopen.keyEquivalentModifierMask = [.control, .option]
        let registered = HotKey.register(id: 1, keyCode: kVK_ANSI_D, modifiers: controlKey | optionKey) { [weak self] in
            self?.reopenLastLink()
        }
        if !registered { reopen.title = "Reopen Last Link… (⌃⌥D is taken by another app)" }
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
        let link = DirectCore.Link(url: url, sourceApp: sourceApp)
        let decision = rules.route(link)

        let optionHeld = NSEvent.modifierFlags.contains(.option)
        if let target = decision.target, !optionHeld {
            open(link, in: target, decision: decision, via: via, picked: false, problems: problems)
        } else {
            showPicker(PickerRequest(link: link, decision: decision, reason: optionHeld ? .modifierHeld : .noRuleMatched),
                       via: via, problems: problems)
        }
    }

    private func showPicker(_ request: PickerRequest, via: ActivityEntry.SourceVia, problems: [String]) {
        picker.show(request, options: Catalog.targets()) { [weak self] choice in
            guard let self else { return }
            guard let choice else {
                ActivityLog.append(ActivityEntry(url: request.link.url.absoluteString, sourceApp: request.link.sourceApp,
                                                 sourceVia: via, rule: [], target: nil, picked: true,
                                                 error: "Picker closed without choosing"))
                return
            }
            var problems = problems
            var decision = Decision(target: choice.target, rulePath: [], ruleIndices: [])
            if let change = choice.ruleChange {
                do {
                    decision.ruleIndices = try self.apply(change, target: choice.target)
                    if case let .add(rule) = change { decision.rulePath = [rule.name] }
                    if request.reason == .reopen, case .retarget = change { decision.rulePath = request.decision.rulePath }
                } catch {
                    problems.append("Could not save the rule: \(error)")
                }
            }
            self.open(request.link, in: choice.target, decision: decision, via: via, picked: true, problems: problems)
        }
    }

    /// Writes a rule change from the picker to rules.json and returns the changed rule's position.
    private func apply(_ change: RuleChange, target: Target) throws -> [Int] {
        var rules: RuleSet
        do {
            rules = try RuleSet.load(from: Paths.rules)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            rules = RuleSet(rules: [], fallback: .ask)
        }
        let indices: [Int]
        switch change {
        case let .add(rule):
            rules.rules.insert(rule, at: 0)
            indices = [0]
        case let .retarget(path):
            guard rules.setTarget(target, forRuleAt: path) else { throw OpenError(description: "That rule no longer exists") }
            indices = path
        }
        try FileManager.default.createDirectory(at: Paths.rules.deletingLastPathComponent(), withIntermediateDirectories: true)
        try rules.encoded().write(to: Paths.rules, options: .atomic)
        if rulesWindow?.isVisible == true { store.load() }
        return indices
    }

    private func open(_ link: DirectCore.Link, in target: Target, decision: Decision, via: ActivityEntry.SourceVia,
                      picked: Bool, problems: [String]) {
        lastLink = link
        lastDecision = Decision(target: target, rulePath: decision.rulePath, ruleIndices: decision.ruleIndices)
        Task {
            var problems = problems
            var method: OpenMethod?
            do {
                method = try await Opener.open(link.url, in: target)
            } catch {
                problems.append("\(error)")
                method = try? await Opener.open(link.url, in: Self.lastResort)
            }
            ActivityLog.append(ActivityEntry(
                url: link.url.absoluteString,
                sourceApp: link.sourceApp,
                sourceVia: via,
                rule: decision.rulePath,
                target: target,
                method: method,
                picked: picked ? true : nil,
                error: problems.isEmpty ? nil : problems.joined(separator: " | ")
            ))
        }
    }

    @objc private func reopenLastLink() {
        guard let lastLink, let lastDecision else {
            NSSound.beep()
            return
        }
        showPicker(PickerRequest(link: lastLink, decision: lastDecision, reason: .reopen), via: .frontmost, problems: [])
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
