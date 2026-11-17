import AppKit
import SwiftUI
import DirectCore

enum HubPage: Hashable, CaseIterable {
    case home, rules, browsers

    var title: String {
        switch self {
        case .home: "Home"
        case .rules: "Rules"
        case .browsers: "Browsers"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .rules: "arrow.triangle.branch"
        case .browsers: "globe"
        }
    }
}

/// Direct's one window: a sidebar and a page. Opened from the menu bar or by launching the app again.
struct HubView: View {
    @Bindable var store: RulesStore
    var prefs: BrowserPrefs
    var reopen: (ActivityEntry) -> Void

    @State private var page: HubPage

    init(store: RulesStore, prefs: BrowserPrefs, startPage: HubPage = .home, reopen: @escaping (ActivityEntry) -> Void) {
        self.store = store
        self.prefs = prefs
        self.reopen = reopen
        _page = State(initialValue: startPage)
    }
    @State private var targets: [TargetOption] = []
    @State private var summary = ActivitySummary([])
    @State private var isDefaultBrowser = true

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Group {
                switch page {
                case .home: HomePage(summary: summary, ruleCount: store.rules.count, targets: targets, reopen: reopen)
                case .rules: RulesPage(store: store, targets: targets)
                case .browsers: BrowsersPage(prefs: prefs, targets: targets)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 1))
            .padding([.top, .trailing, .bottom], 8)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .font(Theme.ui(14))
        .frame(minWidth: 980, minHeight: 640)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if (note.object as? NSWindow)?.contentViewController is NSHostingController<HubView> { refresh() }
        }
    }

    private func refresh() {
        targets = Catalog.targets()
        summary = ActivitySummary(ActivityLog.entries())
        isDefaultBrowser = DefaultBrowser.isDirect
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(nsImage: DirectMark.image(size: 22))
                    .renderingMode(.template)
                    .foregroundStyle(Theme.text)
                    .accessibilityHidden(true)
                Text("Direct").font(Theme.ui(18, .bold))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 18)

            ForEach(HubPage.allCases, id: \.self) { item in
                Button { page = item } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol).frame(width: 18)
                        Text(item.title).font(Theme.ui(14, page == item ? .semibold : .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(page == item ? Theme.selected : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()
            defaultBrowserCard
        }
        .padding(EdgeInsets(top: 44, leading: 12, bottom: 14, trailing: 12))
        .frame(width: 220)
    }

    private var defaultBrowserCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle().fill(isDefaultBrowser ? Theme.good : .orange).frame(width: 7, height: 7)
                Text(isDefaultBrowser ? "Default browser" : "Not your default browser").font(Theme.ui(13, .semibold))
            }
            Text(isDefaultBrowser ? "Links from every app come to Direct first." : "Links skip Direct until it is your default browser.")
                .font(Theme.ui(12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !isDefaultBrowser {
                Button("Make Direct the default") {
                    DefaultBrowser.makeDirect { isDefaultBrowser = DefaultBrowser.isDirect }
                }
                .buttonStyle(QuietButtonStyle())
                .padding(.top, 2)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 14)
    }
}

enum DefaultBrowser {
    static var isDirect: Bool {
        let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        return handler?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// macOS asks the person to confirm; `done` runs after they answer.
    @MainActor static func makeDirect(done: @escaping @MainActor () -> Void) {
        // AppKit calls this back on a background thread.
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http") { @Sendable _ in
            Task { @MainActor in done() }
        }
    }
}

// MARK: Shared page pieces

struct PageHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.display(34))
            Text(subtitle).font(Theme.ui(14)).foregroundStyle(Theme.secondary)
        }
    }
}

// MARK: Home

struct HomePage: View {
    var summary: ActivitySummary
    var ruleCount: Int
    var targets: [TargetOption]
    var reopen: (ActivityEntry) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text("Hold").font(Theme.display(32))
                        KeyCap(keys: "⌥ Option")
                        Text("and click any link").font(Theme.display(32))
                    }
                    HStack(spacing: 6) {
                        Text("Direct asks where to open it. Opened in the wrong place? Press")
                        KeyCap(keys: "⌃ ⌥ D", size: 13)
                    }
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.secondary)
                }

                HStack(alignment: .top, spacing: 16) {
                    stat("Links directed", summary.opened, "this month")
                    stat("Chosen by hand", summary.picked, "with ⌥-click")
                    stat("Fixed with ⌃⌥D", summary.reopened, "reopened elsewhere")
                    stat("Rules", ruleCount, "plus a fallback")
                }
                .padding(EdgeInsets(top: 20, leading: 24, bottom: 20, trailing: 24))
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent links").font(Theme.ui(16, .semibold))
                    if summary.recent.isEmpty {
                        Text("Links you open from other apps will show up here.")
                            .foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                            .card()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(summary.recent.enumerated()), id: \.offset) { index, entry in
                                if index > 0 { Divider().overlay(Theme.line).padding(.horizontal, 14) }
                                RecentLinkRow(entry: entry, targets: targets) { reopen(entry) }
                            }
                        }
                        .padding(6)
                        .card()
                    }
                }
            }
            .padding(EdgeInsets(top: 40, leading: 44, bottom: 40, trailing: 44))
        }
    }

    private func stat(_ title: String, _ value: Int, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.ui(13)).foregroundStyle(Theme.secondary)
            Text(value.formatted()).font(Theme.ui(24, .semibold))
            Text(note).font(Theme.ui(12)).foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecentLinkRow: View {
    var entry: ActivityEntry
    var targets: [TargetOption]
    var reopen: () -> Void
    @State private var hovering = false

    var body: some View {
        let url = URL(string: entry.url)
        HStack(spacing: 14) {
            Text(entry.time.formatted(date: .omitted, time: .shortened))
                .font(Theme.ui(12))
                .foregroundStyle(Theme.tertiary)
                .frame(width: 64, alignment: .leading)
            Group {
                if let source = entry.sourceApp, let icon = Catalog.icon(source) {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "link").foregroundStyle(Theme.tertiary)
                }
            }
            .frame(width: 20, height: 20)
            (Text(url?.host() ?? entry.url).fontWeight(.semibold) + Text(pathAndQuery(url)).foregroundColor(Theme.secondary))
                .font(Theme.ui(14))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hovering {
                Button(action: reopen) {
                    Label("Reopen", systemImage: "arrow.counterclockwise").font(Theme.ui(12, .semibold))
                }
                .buttonStyle(QuietButtonStyle(fill: Theme.card))
                .overlay(Capsule().strokeBorder(Theme.fieldLine, lineWidth: 1))
            }
            if let target = entry.target {
                HStack(spacing: 6) {
                    Text("↳").foregroundStyle(Theme.secondary)
                    TargetLabel(target: target, options: targets)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(hovering ? Theme.soft : .clear, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // The Reopen button only shows on hover, so VoiceOver gets the row itself as the button.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Offers this link in the picker again")
        .accessibilityAction { reopen() }
    }

    private func pathAndQuery(_ url: URL?) -> String {
        guard let url else { return "" }
        let path = url.path(percentEncoded: false)
        return (path == "/" ? "" : path) + (url.query().map { "?" + $0 } ?? "")
    }
}
