import AppKit
import SwiftUI
import DirectCore

struct TargetOption: Identifiable, Hashable {
    var target: Target
    var appName: String
    var profileName: String?
    /// The profile's color from the browser, as 0xRRGGBB.
    var profileColor: UInt32?
    var id: Target { target }

    /// What people call it: the profile name for a profile, otherwise the app.
    var title: String { profileName ?? appName }
    /// One line for menus and messages.
    var label: String { profileName.map { "\(appName) · \($0)" } ?? appName }
    /// The last word's first letter, so "Mahbubur-Work" and "Mahbubur Rahman" get W and R.
    var initial: String? {
        profileName?.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" }).last?.first.map { String($0).uppercased() }
    }
    var badge: Color { Color(hex: profileColor ?? 0x8E897C) }

    /// Dark text on light profile colors, white on dark ones.
    var badgeText: Color {
        let c = profileColor ?? 0x8E897C
        let luma = 0.299 * Double((c >> 16) & 0xFF) + 0.587 * Double((c >> 8) & 0xFF) + 0.114 * Double(c & 0xFF)
        return luma > 150 ? Color(hex: 0x10213F) : .white
    }
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
                options.append(TargetOption(target: Target(browser: id), appName: name))
            } else {
                options += profiles.map {
                    TargetOption(target: Target(browser: id, profile: $0.directory), appName: name,
                                 profileName: $0.name, profileColor: $0.color)
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

    static func title(for target: Target, in options: [TargetOption]) -> String {
        options.first { $0.target == target }?.title ?? label(for: target, in: options)
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

    /// Icons are drawn many times per screen, and looking one up hits the disk.
    static func icon(_ bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons[bundleID] = icon
        return icon
    }

    private static var icons: [String: NSImage?] = [:]

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
