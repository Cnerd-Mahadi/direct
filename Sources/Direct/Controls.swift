import AppKit
import SwiftUI
import DirectCore

/// One line in a dropdown's menu.
enum MenuEntry {
    case item(String, checked: Bool = false, action: () -> Void)
    case header(String)
    case separator
}

extension View {
    /// Pops a native menu below this view on click. SwiftUI's `Menu` flattens a custom label
    /// to plain text, which loses the browser icon and badge, so the label is drawn here instead.
    func dropdown(_ entries: @escaping () -> [MenuEntry]) -> some View {
        modifier(DropdownModifier(entries: entries))
    }
}

private struct DropdownModifier: ViewModifier {
    var entries: () -> [MenuEntry]
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.overlay { if isEnabled { DropdownTrigger(entries: entries) } }
    }
}

private struct DropdownTrigger: NSViewRepresentable {
    var entries: () -> [MenuEntry]

    func makeNSView(context: Context) -> TriggerView { TriggerView() }
    func updateNSView(_ view: TriggerView, context: Context) { view.entries = entries }

    final class TriggerView: NSView {
        var entries: () -> [MenuEntry] = { [] }
        private var actions: [() -> Void] = []

        override func mouseDown(with event: NSEvent) { popUp() }

        /// VoiceOver and other assistive apps see a pop-up button showing the checked choice.
        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .popUpButton }
        override func accessibilityValue() -> Any? {
            entries().lazy.compactMap { if case let .item(title, true, _) = $0 { title } else { nil } }.first
        }
        /// Deferred, because the menu runs its own loop and would hold the press call open until it closes.
        override func accessibilityPerformPress() -> Bool {
            DispatchQueue.main.async { self.popUp() }
            return true
        }

        private func popUp() {
            let menu = NSMenu()
            actions = []
            for entry in entries() {
                switch entry {
                case let .item(title, checked, action):
                    let item = NSMenuItem(title: title, action: #selector(pick(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = actions.count
                    item.state = checked ? .on : .off
                    actions.append(action)
                    menu.addItem(item)
                case let .header(title):
                    menu.addItem(NSMenuItem.sectionHeader(title: title))
                case .separator:
                    menu.addItem(.separator())
                }
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
        }

        @objc private func pick(_ item: NSMenuItem) { actions[item.tag]() }
        override var isFlipped: Bool { true }
    }
}

/// A rounded dropdown over a fixed list of choices.
struct PillMenu<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(Value, String)]
    var width: CGFloat?

    var body: some View {
        PillMenuLabel(width: width) { Text(options.first { $0.0 == selection }?.1 ?? "") }
            .fixedSize()
            .dropdown { options.map { value, title in .item(title, checked: value == selection) { selection = value } } }
    }
}

struct PillMenuLabel<Content: View>: View {
    var width: CGFloat?
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            content().font(Theme.ui(14))
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(width: width, height: 34)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.fieldLine, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

struct PillField: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.tertiary))
            .textFieldStyle(.plain)
            .font(Theme.ui(14, .medium))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.fieldLine, lineWidth: 1))
    }
}

struct RoundIconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
                .background(Theme.chip, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct AddLinkButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus").font(Theme.ui(13, .semibold)).foregroundStyle(Theme.link)
        }
        .buttonStyle(.plain)
    }
}

/// Where a link opens: one of the browsers and profiles on this Mac.
struct TargetMenu: View {
    @Binding var target: Target
    var targets: [TargetOption]

    var body: some View {
        PillMenuLabel { TargetLabel(target: target, options: targets, font: Theme.ui(14, .semibold)) }
            .fixedSize()
            .dropdown { TargetMenu.entries(targets, current: target) { target = $0 } }
    }

    static func entries(_ targets: [TargetOption], current: Target, pick: @escaping (Target) -> Void) -> [MenuEntry] {
        var entries = targets.map { option in MenuEntry.item(option.label, checked: option.target == current) { pick(option.target) } }
        if !targets.contains(where: { $0.target == current }) {
            entries.append(.item(Catalog.label(for: current, in: targets), checked: true) {})
        }
        return entries
    }
}

struct ConditionList: View {
    @Binding var conditions: [ConditionDraft]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($conditions) { $condition in
                ConditionRow(condition: $condition) { conditions.removeAll { $0.id == condition.id } }
            }
            if conditions.isEmpty {
                Label("No conditions, so this matches every link.", systemImage: "exclamationmark.triangle")
                    .font(Theme.ui(13))
                    .foregroundStyle(.orange)
            } else if conditions.count > 1 {
                Text("All of these must match.").font(Theme.ui(12)).foregroundStyle(Theme.secondary)
            }
            AddLinkButton(title: "Add condition") { conditions.append(ConditionDraft()) }
        }
    }
}

struct ConditionRow: View {
    @Binding var condition: ConditionDraft
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            PillMenu(selection: $condition.kind, options: ConditionDraft.Kind.allCases.map { ($0, $0.label) }, width: 132)
            if condition.kind == .app {
                AppList(apps: $condition.apps)
            } else {
                PillMenu(selection: $condition.match, options: condition.kind.matches.map { ($0, $0.label) }, width: 136)
                PillField(placeholder: condition.kind.placeholder, text: $condition.text)
                if condition.kind != .website {
                    Toggle("Aa", isOn: $condition.caseSensitive)
                        .toggleStyle(.button)
                        .help("Match upper and lower case exactly")
                }
            }
            RoundIconButton(symbol: "minus", help: "Remove condition", action: onDelete)
        }
    }
}

struct AppList: View {
    @Binding var apps: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(apps, id: \.self) { id in
                HStack(spacing: 6) {
                    if let icon = Catalog.icon(id) { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                    Text(Catalog.appName(id) ?? id).font(Theme.ui(14, .medium))
                    Button { apps.removeAll { $0 == id } } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.secondary)
                        .accessibilityLabel("Remove \(Catalog.appName(id) ?? id)")
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.fieldLine, lineWidth: 1))
            }
            AppMenu(title: apps.isEmpty ? "Choose app" : "Add app", extra: [], none: nil) { option in
                if let option, !apps.contains(option.bundleID) { apps.append(option.bundleID) }
            }
            Spacer(minLength: 0)
        }
    }
}

/// A menu of running apps plus "Choose…" for anything in /Applications.
struct AppMenu: View {
    var title: String
    var extra: [AppOption]
    var none: String?
    var onPick: (AppOption?) -> Void

    var body: some View {
        PillMenuLabel { Text(title) }
            .fixedSize()
            .dropdown {
                var entries: [MenuEntry] = []
                if let none { entries.append(.item(none) { onPick(nil) }) }
                if !extra.isEmpty {
                    entries.append(.header("In your rules"))
                    entries += extra.map { option in .item(option.name) { onPick(option) } }
                }
                entries.append(.header("Running now"))
                entries += Catalog.runningApps().map { option in .item(option.name) { onPick(option) } }
                entries.append(.separator)
                entries.append(.item("Choose from Applications…") { if let option = Catalog.chooseApp() { onPick(option) } })
                return entries
            }
    }
}

// MARK: Plain-English wording

extension ConditionDraft.Kind {
    var label: String {
        switch self {
        case .app: "Opened from"
        case .website: "Website"
        case .path: "Path"
        case .link: "Whole link"
        }
    }

    var placeholder: String {
        switch self {
        case .app: ""
        case .website: "github.com"
        case .path: "/acme/issues"
        case .link: "any word in the link"
        }
    }
}

extension ConditionDraft.Match {
    var label: String {
        switch self {
        case .isOrUnder: "is or is under"
        case .isExactly: "is exactly"
        case .contains: "contains"
        case .startsWith: "starts with"
        case .endsWith: "ends with"
        }
    }
}

/// A condition as a short phrase for a rule card, such as "Website contains shopify".
struct ConditionPhrase: View {
    var condition: ConditionDraft

    var body: some View {
        let text = condition.text.trimmingCharacters(in: .whitespaces)
        switch condition.kind {
        case .app:
            HStack(spacing: 6) {
                Text("From")
                ForEach(condition.apps, id: \.self) { id in
                    if let icon = Catalog.icon(id) { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                    Text(Catalog.appName(id) ?? id).foregroundStyle(Theme.text).fontWeight(.medium)
                }
                if condition.apps.isEmpty { Text("no app chosen yet").italic() }
            }
        default:
            (Text(condition.kind.label + " " + condition.match.label + " ")
                + Text(text.isEmpty ? "(empty)" : text).foregroundColor(Theme.text).fontWeight(.medium))
        }
    }
}
