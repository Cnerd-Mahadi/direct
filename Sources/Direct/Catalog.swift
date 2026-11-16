import AppKit
import DirectCore

struct TargetOption: Identifiable, Hashable {
    var target: Target
    var label: String
    var id: Target { target }
}

struct AppOption: Identifiable, Hashable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

/// What's installed on this Mac: browsers with their profiles, and app names and icons.
@MainActor
enum Catalog {
    /// Other link routers register as browsers too. Offering them as targets would loop.
    private static let routers: Set<String> = [
        "com.webcatalog.switchbar", "com.cnerd.bravewd", "se.johnste.finicky",
        "com.sindresorhus.Velja", "com.choosyosx.Choosy", "com.browserosaurus",
    ]

    static func targets() -> [TargetOption] {
        var seen: Set<String> = []
        var options: [TargetOption] = []
        for appURL in NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!) {
            guard let id = Bundle(url: appURL)?.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                  !routers.contains(id), seen.insert(id).inserted else { continue }
            let name = displayName(appURL)
            let profiles = Chromium.userDataDir(for: id)
                .flatMap { try? Data(contentsOf: $0.appending(path: "Local State")) }
                .flatMap { try? Chromium.profiles(localState: $0) } ?? []
            if profiles.isEmpty {
                options.append(TargetOption(target: Target(browser: id), label: name))
            } else {
                options += profiles.map {
                    TargetOption(target: Target(browser: id, profile: $0.directory), label: "\(name) · \($0.name)")
                }
            }
        }
        return options.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    static func label(for target: Target, in options: [TargetOption]) -> String {
        if let option = options.first(where: { $0.target == target }) { return option.label }
        let app = appName(target.browser) ?? target.browser
        return [app, target.profile].compactMap { $0 }.joined(separator: " · ") + " (not found)"
    }

    static func runningApps() -> [AppOption] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .compactMap { app in app.bundleIdentifier.map { AppOption(bundleID: $0, name: app.localizedName ?? $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func appName(_ bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map(displayName)
    }

    static func icon(_ bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    /// Asks the user to pick an app from /Applications and returns its bundle identifier.
    static func chooseApp() -> AppOption? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        return AppOption(bundleID: id, name: displayName(url))
    }

    private static func displayName(_ appURL: URL) -> String {
        let name = FileManager.default.displayName(atPath: appURL.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
