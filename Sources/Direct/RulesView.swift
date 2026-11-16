import AppKit
import SwiftUI
import DirectCore

struct RulesView: View {
    @Bindable var store: RulesStore
    @State private var targets: [TargetOption] = []
    @State private var selection: RuleDraft.ID?

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.loadError {
                Banner(text: "rules.json has a problem, so editing is paused: \(error)", action: ("Reload", store.load))
            }
            if let error = store.saveError {
                Banner(text: "Could not save rules.json: \(error)", action: nil)
            }
            TestBar(store: store, targets: targets, selection: $selection)
            Divider()
            HSplitView {
                sidebar.frame(minWidth: 240, idealWidth: 270, maxWidth: 360)
                detail.frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .disabled(store.loadError != nil)
        .onAppear {
            targets = Catalog.targets()
            if selection == nil { selection = store.rules.first?.id }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Rules · first match wins") {
                    ForEach(store.rules) { rule in
                        RuleRow(rule: rule, targets: targets).tag(rule.id)
                    }
                    .onMove { store.rules.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            Divider()
            HStack(spacing: 4) {
                Button { addRule() } label: { Image(systemName: "plus") }
                Button { deleteSelected() } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Everything else opens in").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $store.fallback) {
                    Text("Ask me").tag(Fallback.ask)
                    Divider()
                    ForEach(targets) { Text($0.label).tag(Fallback.open($0.target)) }
                    if case let .open(target) = store.fallback, !targets.contains(where: { $0.target == target }) {
                        Text(Catalog.label(for: target, in: targets)).tag(store.fallback)
                    }
                }
                .labelsHidden()
            }
            .padding(10)
        }
    }

    @ViewBuilder private var detail: some View {
        if let index = store.rules.firstIndex(where: { $0.id == selection }) {
            RuleEditor(rule: $store.rules[index], targets: targets)
                .id(store.rules[index].id)
        } else {
            Text(store.rules.isEmpty ? "No rules yet. Press + to add one." : "Select a rule")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func addRule() {
        let fallbackTarget: Target? = if case let .open(target) = store.fallback { target } else { nil }
        let rule = RuleDraft(name: "New rule", target: fallbackTarget ?? targets.first?.target ?? Target(browser: "com.apple.Safari"))
        store.rules.append(rule)
        selection = rule.id
    }

    private func deleteSelected() {
        guard let index = store.rules.firstIndex(where: { $0.id == selection }) else { return }
        selection = nil
        store.rules.remove(at: index)
        selection = store.rules.indices.contains(index) ? store.rules[index].id : store.rules.last?.id
    }
}

private struct Banner: View {
    var text: String
    var action: (String, () -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if let action { Button(action.0, action: action.1) }
        }
        .padding(10)
        .background(.orange.opacity(0.12))
    }
}

// MARK: Live test

private struct TestBar: View {
    var store: RulesStore
    var targets: [TargetOption]
    @Binding var selection: RuleDraft.ID?
    @State private var text = ""
    @State private var sourceApp: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Paste a link to test where it would open", text: $text)
                    .textFieldStyle(.roundedBorder)
                AppMenu(title: sourceApp.flatMap(Catalog.appName) ?? sourceApp ?? "From any app",
                        extra: appsInRules, none: "From any app") { sourceApp = $0?.bundleID }
                    .fixedSize()
            }
            if let decision {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                    Text(decision.target.map { Catalog.label(for: $0, in: targets) } ?? "You'll be asked").bold()
                    Text(decision.rulePath.isEmpty ? "No rule matched, so the fallback applies"
                                                   : "via " + decision.rulePath.joined(separator: " › "))
                        .foregroundStyle(.secondary)
                    if let first = decision.ruleIndices.first, store.rules.indices.contains(first) {
                        Button("Show rule") { selection = store.rules[first].id }.buttonStyle(.link)
                    }
                }
                .font(.callout)
            }
        }
        .padding(12)
    }

    private var decision: Decision? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), url.host() != nil else { return nil }
        return store.ruleSet.route(Link(url: url, sourceApp: sourceApp))
    }

    private var appsInRules: [AppOption] {
        func ids(_ rule: RuleDraft) -> [String] {
            rule.conditions.flatMap { $0.kind == .app ? $0.apps : [] } + rule.exceptions.flatMap(ids)
        }
        let unique = Array(Set(store.rules.flatMap(ids)))
        return unique.map { AppOption(bundleID: $0, name: Catalog.appName($0) ?? $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: Sidebar row

private struct RuleRow: View {
    var rule: RuleDraft
    var targets: [TargetOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rule.name.isEmpty ? "Untitled rule" : rule.name)
                .foregroundStyle(rule.enabled ? .primary : .secondary)
            Text((rule.enabled ? "" : "Off · ") + "→ " + Catalog.label(for: rule.target, in: targets))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

// MARK: Rule editor

private struct RuleEditor: View {
    @Binding var rule: RuleDraft
    var targets: [TargetOption]
    @State private var showMore = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $rule.name)
                Toggle("Rule is on", isOn: $rule.enabled)
            }
            Section("When the link") {
                ConditionList(conditions: $rule.conditions, showMore: showMore)
            }
            Section("Open it in") {
                TargetPicker(target: $rule.target, targets: targets)
            }
            Section {
                Text(Summary.sentence(for: rule, targets: targets))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section {
                Button(showMore ? "Hide more options" : "Show more options: match types and exceptions",
                       systemImage: showMore ? "chevron.down" : "chevron.right") { showMore.toggle() }
                    .buttonStyle(.borderless)
                if showMore {
                    Text("Exceptions are checked only when this rule matches. The first matching exception decides instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if showMore {
                ForEach($rule.exceptions) { $exception in
                    Section("Exception") {
                        TextField("Name", text: $exception.name)
                        Toggle("Exception is on", isOn: $exception.enabled)
                        ConditionList(conditions: $exception.conditions, showMore: true)
                        LabeledContent("Open it in") {
                            TargetPicker(target: $exception.target, targets: targets)
                        }
                        Button("Remove exception", systemImage: "trash", role: .destructive) {
                            rule.exceptions.removeAll { $0.id == exception.id }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Section {
                    Button("Add exception", systemImage: "plus") {
                        rule.exceptions.append(RuleDraft(name: "Exception", target: rule.target))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { showMore = !rule.exceptions.isEmpty || rule.conditions.contains(where: \.isAdvanced) }
    }
}

private struct ConditionList: View {
    @Binding var conditions: [ConditionDraft]
    var showMore: Bool

    var body: some View {
        ForEach($conditions) { $condition in
            ConditionRow(condition: $condition, showMatch: showMore || condition.isAdvanced) {
                conditions.removeAll { $0.id == condition.id }
            }
        }
        if conditions.isEmpty {
            Label("No conditions, so this rule matches every link.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else if conditions.count > 1 {
            Text("All conditions must match.").font(.caption).foregroundStyle(.secondary)
        }
        Button("Add condition", systemImage: "plus") { conditions.append(ConditionDraft()) }
            .buttonStyle(.borderless)
    }
}

private struct ConditionRow: View {
    @Binding var condition: ConditionDraft
    var showMatch: Bool
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Picker("", selection: $condition.kind) {
                ForEach(ConditionDraft.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()

            if condition.kind == .app {
                AppList(apps: $condition.apps)
            } else {
                if showMatch {
                    Picker("", selection: $condition.match) {
                        ForEach(condition.kind.matches, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                TextField("", text: $condition.text, prompt: Text(condition.kind.placeholder))
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                if showMatch, condition.kind != .website {
                    Toggle("Match case", isOn: $condition.caseSensitive).fixedSize()
                }
            }
            Button(action: onDelete) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove condition")
        }
    }
}

private struct AppList: View {
    @Binding var apps: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(apps, id: \.self) { id in
                HStack(spacing: 4) {
                    if let icon = Catalog.icon(id) { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                    Text(Catalog.appName(id) ?? id)
                    Button { apps.removeAll { $0 == id } } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            }
            AppMenu(title: apps.isEmpty ? "Choose app" : "Add", extra: [], none: nil) { option in
                if let option, !apps.contains(option.bundleID) { apps.append(option.bundleID) }
            }
            .fixedSize()
            Spacer(minLength: 0)
        }
    }
}

/// A menu of running apps plus "Choose…" for anything in /Applications.
private struct AppMenu: View {
    var title: String
    var extra: [AppOption]
    var none: String?
    var onPick: (AppOption?) -> Void

    var body: some View {
        Menu(title) {
            if let none { Button(none) { onPick(nil) } }
            if !extra.isEmpty {
                Section("In your rules") { ForEach(extra) { option in Button(option.name) { onPick(option) } } }
            }
            Section("Running now") {
                ForEach(Catalog.runningApps()) { option in Button(option.name) { onPick(option) } }
            }
            Divider()
            Button("Choose from Applications…") { if let option = Catalog.chooseApp() { onPick(option) } }
        }
    }
}

private struct TargetPicker: View {
    @Binding var target: Target
    var targets: [TargetOption]

    var body: some View {
        Picker("", selection: $target) {
            ForEach(targets) { Text($0.label).tag($0.target) }
            if !targets.contains(where: { $0.target == target }) {
                Text(Catalog.label(for: target, in: targets)).tag(target)
            }
        }
        .labelsHidden()
    }
}

// MARK: Plain-English wording

extension ConditionDraft {
    /// True when the condition uses something the simple view hides.
    var isAdvanced: Bool {
        caseSensitive || (kind != .app && match != kind.matches.first)
    }
}

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

@MainActor
enum Summary {
    static func sentence(for rule: RuleDraft, targets: [TargetOption]) -> String {
        let target = Catalog.label(for: rule.target, in: targets)
        let parts = rule.conditions.map(describe)
        var sentence = parts.isEmpty
            ? "Every link opens in \(target)."
            : "Links \(parts.joined(separator: " and ")) open in \(target)."
        let exceptions = rule.exceptions.filter(\.enabled)
        if !exceptions.isEmpty {
            sentence += " Except: " + exceptions.map { exception in
                let when = exception.conditions.map(describe).joined(separator: " and ")
                return "\(when.isEmpty ? "always" : when) → \(Catalog.label(for: exception.target, in: targets))"
            }.joined(separator: "; ") + "."
        }
        return sentence
    }

    private static func describe(_ condition: ConditionDraft) -> String {
        let text = condition.text.trimmingCharacters(in: .whitespaces)
        let value = text.isEmpty ? "(not filled in)" : "“\(text)”"
        let caseNote = condition.caseSensitive ? " (matching case)" : ""
        switch condition.kind {
        case .app:
            let names = condition.apps.map { Catalog.appName($0) ?? $0 }
            return names.isEmpty ? "from (no app chosen)" : "from " + names.joined(separator: " or ")
        case .website:
            return switch condition.match {
            case .isExactly: "on exactly \(value)"
            case .contains: "on a website containing \(value)"
            default: "on \(value) or its subdomains"
            }
        case .path:
            return "whose path \(condition.match.label) \(value)\(caseNote)"
        case .link:
            return "whose link \(condition.match.label) \(value)\(caseNote)"
        }
    }
}
