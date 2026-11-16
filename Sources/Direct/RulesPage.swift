import AppKit
import SwiftUI
import DirectCore

/// One rule being edited in the sheet. Edits stay in the copy until Save.
private struct EditSession: Identifiable {
    var id: UUID { draft.id }
    var draft: RuleDraft
    var isNew: Bool
}

struct RulesPage: View {
    @Bindable var store: RulesStore
    var targets: [TargetOption]
    @State private var editing: EditSession?
    @State private var testText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Rules", subtitle: "Links are checked from the top. The first rule that matches decides where they open.")
            if let error = store.loadError {
                Banner(text: "rules.json has a problem, so editing is paused: \(error)", action: ("Reload", store.load))
            }
            if let error = store.saveError {
                Banner(text: "Could not save rules.json: \(error)", action: nil)
            }
            tryBar
            List {
                ForEach($store.rules) { $rule in
                    let number = (store.rules.firstIndex { $0.id == rule.id } ?? 0) + 1
                    RuleCard(rule: $rule, number: number, targets: targets)
                        .onTapGesture { editing = EditSession(draft: rule, isNew: false) }
                        .contextMenu {
                            Button("Edit…") { editing = EditSession(draft: rule, isNew: false) }
                            Button("Delete", role: .destructive) { store.rules.removeAll { $0.id == rule.id } }
                        }
                        .cardRow()
                }
                .onMove { store.rules.move(fromOffsets: $0, toOffset: $1) }
                FallbackCard(fallback: $store.fallback, targets: targets).cardRow().moveDisabled(true)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // The row insets plus the table's own margins (8 left, 10 right), so cards line up with the bar above.
            .padding(.leading, -16)
            .padding(.trailing, -18)
        }
        .padding(EdgeInsets(top: 40, leading: 44, bottom: 12, trailing: 44))
        .disabled(store.loadError != nil)
        .sheet(item: $editing) { session in
            RuleEditorSheet(session: session, targets: targets) { saved in
                if let index = store.rules.firstIndex(where: { $0.id == saved.id }) {
                    store.rules[index] = saved
                } else if session.isNew {
                    store.rules.insert(saved, at: 0)
                }
                editing = nil
            } onDelete: {
                store.rules.removeAll { $0.id == session.id }
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
    }

    private var tryBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "link").foregroundStyle(Theme.secondary)
                    TextField("", text: $testText, prompt: Text("Paste a link to see where it opens").foregroundColor(Theme.tertiary))
                        .textFieldStyle(.plain)
                }
                .font(Theme.ui(14))
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Theme.field, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.fieldLine, lineWidth: 1))

                Button { editing = EditSession(draft: newRule(), isNew: true) } label: {
                    Label("Add rule", systemImage: "plus")
                }
                .buttonStyle(AccentButtonStyle())
            }
            if let decision = testDecision {
                HStack(spacing: 6) {
                    Text("↳")
                    if let target = decision.target {
                        Text("Opens in")
                        TargetLabel(target: target, options: targets, size: 16)
                    } else {
                        Text("Direct will ask you")
                    }
                    Text(reason(decision))
                }
                .font(Theme.ui(13))
                .foregroundStyle(Theme.secondary)
                .padding(.leading, 16)
            }
        }
    }

    private var testDecision: Decision? {
        let trimmed = testText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), url.host() != nil else { return nil }
        return store.ruleSet.route(DirectCore.Link(url: url, sourceApp: nil))
    }

    private func reason(_ decision: Decision) -> String {
        switch decision.ruleIndices.count {
        case 0: "because no rule matches"
        case 1: "by rule \(decision.ruleIndices[0] + 1)"
        default: "by the exception in rule \(decision.ruleIndices[0] + 1)"
        }
    }

    private func newRule() -> RuleDraft {
        let fallback: Target? = if case let .open(target) = store.fallback { target } else { nil }
        return RuleDraft(name: "", target: fallback ?? targets.first?.target ?? Target(browser: "com.apple.Safari"))
    }
}

private extension View {
    func cardRow() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
    }
}

private struct RuleCard: View {
    @Binding var rule: RuleDraft
    var number: Int
    var targets: [TargetOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                Text("\(number)")
                    .font(Theme.ui(12, .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 22, height: 22)
                    .background(Theme.chip, in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(rule.name.isEmpty ? "Untitled rule" : rule.name).font(Theme.ui(15, .semibold))
                    HStack(spacing: 8) {
                        ForEach(Array(rule.conditions.enumerated()), id: \.element.id) { index, condition in
                            if index > 0 { Text("and") }
                            ConditionPhrase(condition: condition)
                        }
                        if rule.conditions.isEmpty { Text("Every link") }
                        Text("↳")
                        TargetLabel(target: rule.target, options: targets)
                    }
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                }
                Spacer()
                Toggle("Rule is on", isOn: $rule.enabled).toggleStyle(.switch).tint(Theme.switchOn).labelsHidden()
            }
            ForEach(rule.exceptions) { exception in
                Divider().overlay(Theme.line).padding(.leading, 54)
                HStack(spacing: 8) {
                    Text("Except")
                    ForEach(exception.conditions) { ConditionPhrase(condition: $0) }
                    Text("↳")
                    TargetLabel(target: exception.target, options: targets)
                    if !exception.enabled { Text("(off)") }
                }
                .font(Theme.ui(13))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .padding(.leading, 54)
            }
        }
        .opacity(rule.enabled ? 1 : 0.55)
        .padding(EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 16))
        .card()
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct FallbackCard: View {
    @Binding var fallback: Fallback
    var targets: [TargetOption]

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Everything else").font(Theme.ui(15, .semibold))
                Text("When no rule matches").font(Theme.ui(13)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            PillMenuLabel {
                switch fallback {
                case .ask: Text("Ask me").font(Theme.ui(14, .semibold))
                case let .open(target): TargetLabel(target: target, options: targets, font: Theme.ui(14, .semibold))
                }
            }
            .fixedSize()
            .dropdown {
                let current: Target? = if case let .open(target) = fallback { target } else { nil }
                return [MenuEntry.item("Ask me", checked: current == nil) { fallback = .ask }, .separator]
                    + targets.map { option in .item(option.label, checked: option.target == current) { fallback = .open(option.target) } }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 54, bottom: 14, trailing: 16))
        .card(fill: Theme.soft)
    }
}

private struct RuleEditorSheet: View {
    @State private var draft: RuleDraft
    private let isNew: Bool
    var targets: [TargetOption]
    var onSave: (RuleDraft) -> Void
    var onDelete: () -> Void
    var onCancel: () -> Void

    init(session: EditSession, targets: [TargetOption], onSave: @escaping (RuleDraft) -> Void,
         onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: session.draft)
        isNew = session.isNew
        self.targets = targets
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isNew ? "New rule" : "Edit rule").font(Theme.display(28))
                Spacer()
                RoundIconButton(symbol: "xmark", help: "Close without saving", action: onCancel)
            }
            .padding(EdgeInsets(top: 22, leading: 24, bottom: 14, trailing: 24))

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Name") { PillField(placeholder: "Shopify goes to Work", text: $draft.name) }
                    section("When") { ConditionList(conditions: $draft.conditions) }
                    section("Open in") { TargetMenu(target: $draft.target, targets: targets) }
                    section("Except") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach($draft.exceptions) { $exception in
                                ExceptionEditor(exception: $exception, targets: targets) {
                                    draft.exceptions.removeAll { $0.id == exception.id }
                                }
                            }
                            AddLinkButton(title: "Add exception") {
                                draft.exceptions.append(RuleDraft(name: "Exception", target: draft.target))
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 520)

            Divider().overlay(Theme.line)
            HStack(spacing: 10) {
                if !isNew {
                    Button("Delete rule", role: .destructive, action: onDelete)
                        .buttonStyle(.plain)
                        .font(Theme.ui(14, .semibold))
                        .foregroundStyle(Theme.danger)
                }
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save") { onSave(named(draft)) }.buttonStyle(AccentButtonStyle()).keyboardShortcut(.defaultAction)
            }
            .padding(EdgeInsets(top: 14, leading: 24, bottom: 18, trailing: 24))
        }
        .frame(width: 720)
        .background(Theme.card)
        .foregroundStyle(Theme.text)
        .font(Theme.ui(14))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.ui(13, .semibold)).foregroundStyle(Theme.secondary)
            content()
        }
    }

    /// A rule saved without a name gets one from what it matches, so the list never shows "Untitled".
    private func named(_ rule: RuleDraft) -> RuleDraft {
        guard rule.name.trimmingCharacters(in: .whitespaces).isEmpty else { return rule }
        var rule = rule
        let subject = rule.conditions.first.map { $0.kind == .app ? ($0.apps.first.flatMap(Catalog.appName) ?? "App") : $0.text } ?? "Every link"
        rule.name = "\(subject.isEmpty ? "New rule" : subject) goes to \(Catalog.title(for: rule.target, in: targets))"
        return rule
    }
}

private struct ExceptionEditor: View {
    @Binding var exception: RuleDraft
    var targets: [TargetOption]
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ConditionList(conditions: $exception.conditions)
            HStack(spacing: 8) {
                Text("↳ Open in").foregroundStyle(Theme.secondary)
                TargetMenu(target: $exception.target, targets: targets)
                Spacer()
                Toggle("On", isOn: $exception.enabled).toggleStyle(.switch).tint(Theme.switchOn).controlSize(.small)
                Button("Remove", role: .destructive, action: onRemove)
                    .buttonStyle(.plain)
                    .font(Theme.ui(13, .semibold))
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(14)
        .card(fill: Theme.soft)
    }
}

private struct Banner: View {
    var text: String
    var action: (String, () -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if let action { Button(action.0, action: action.1).buttonStyle(QuietButtonStyle()) }
        }
        .font(Theme.ui(13))
        .padding(12)
        .card(fill: Color.orange.opacity(0.12), outline: Color.orange.opacity(0.3), radius: 12)
    }
}
