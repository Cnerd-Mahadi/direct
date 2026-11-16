import AppKit
import SwiftUI
import DirectCore

/// `DIRECT_SNAPSHOT=<folder> Direct` renders each screen offscreen to PNGs and exits,
/// so the UI can be checked without a window ever coming to the front.
@MainActor
enum Snapshot {
    static func runIfRequested() -> Bool {
        guard let folder = ProcessInfo.processInfo.environment["DIRECT_SNAPSHOT"] else { return false }
        let out = URL(filePath: folder, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        Theme.registerFonts()

        let store = RulesStore()
        store.load()
        let prefs = BrowserPrefs()
        let all = Catalog.targets()
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            for page in HubPage.allCases {
                let view = HubView(store: store, prefs: prefs, startPage: page) { _ in }
                save(view, size: NSSize(width: 1120, height: 760), appearance: appearance, to: out.appending(path: "hub-\(page)-\(suffix).png"))
            }
        }

        let link = DirectCore.Link(url: URL(string: "https://admin.shopify.com/store/quotepilot-dev")!, sourceApp: "com.microsoft.teams2")
        let rules = (try? RuleSet.load(from: Paths.rules)) ?? RuleSet(rules: [], fallback: .ask)
        let shown = prefs.arrange(all).shown
        for (name, reason, openedIn, mode) in [("picker-reopen", PickerRequest.Reason.reopen, rules.route(link).target, PickerModel.Mode.once),
                                               ("picker-more", .reopen, rules.route(link).target, .custom)] {
            let model = PickerModel(request: PickerRequest(link: link, decision: rules.route(link), openedIn: openedIn, reason: reason), options: shown)
            model.mode = mode
            let view = PickerView(model: model, targets: all, onChoose: { _ in }, onResize: {}).padding(30)
            save(view, size: nil, appearance: .aqua, to: out.appending(path: "\(name).png"))
        }
        print("Snapshots in \(out.path)")
        return true
    }

    private static func save<V: View>(_ view: V, size: NSSize?, appearance: NSAppearance.Name, to file: URL) {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: appearance)
        let fitted = size ?? host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fitted), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = NSColor(srgbRed: 0.85, green: 0.85, blue: 0.83, alpha: 1)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: fitted)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
    }
}
