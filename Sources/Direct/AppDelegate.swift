import AppKit
import DirectCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let lastResort = Target(browser: "com.apple.Safari")

    /// Last app other than Direct to come to the front. Used when the event's sender is unknown.
    private var lastOtherApp: String?

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
