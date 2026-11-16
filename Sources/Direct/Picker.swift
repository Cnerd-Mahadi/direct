import AppKit
import SwiftUI
import DirectCore

struct PickerRequest {
    enum Reason { case noRuleMatched, modifierHeld, reopen }

    var link: DirectCore.Link
    /// What the rules decided. Its target is pre-highlighted; for a reopen it's where the link went.
    var decision: Decision
    var reason: Reason
}

enum RuleChange {
    /// Inserted at the top so "always" holds even where another rule would match first.
    case add(Rule)
    /// Point the rule at these indices to the chosen target.
    case retarget([Int])
}

struct PickerChoice {
    var target: Target
    var ruleChange: RuleChange?
}

@MainActor
@Observable
final class PickerModel {
    let request: PickerRequest
    let options: [TargetOption]
    let ingredients: [Ingredient]
    var highlighted: Int
    var remember = false
    var showMore = false
    var picked: Set<Ingredient>

    init(request: PickerRequest, options: [TargetOption]) {
        self.request = request
        self.options = options
        ingredients = request.link.ingredients
        picked = Set(ingredients.prefix(1))
        highlighted = options.firstIndex { $0.target == request.decision.target } ?? 0
    }

    /// A reopen of a link a rule decided offers to fix that rule instead of adding one.
    var fixesExistingRule: Bool {
        request.reason == .reopen && !request.decision.ruleIndices.isEmpty
    }

    var host: String {
        for case let .website(host) in ingredients { return host }
        return "this link"
    }

    var rememberLabel: String {
        if fixesExistingRule { return "Fix the rule “\(request.decision.rulePath.joined(separator: " › "))” too" }
        if showMore { return "Always open links like this here" }
        return "Always open \(host) here"
    }

    var chosenIngredients: [Ingredient] { ingredients.filter(picked.contains) }

    func move(_ delta: Int) {
        guard !options.isEmpty else { return }
        highlighted = (highlighted + delta + options.count) % options.count
    }

    func choice(at index: Int) -> PickerChoice? {
        guard options.indices.contains(index) else { return nil }
        let target = options[index].target
        guard remember else { return PickerChoice(target: target) }
        if fixesExistingRule { return PickerChoice(target: target, ruleChange: .retarget(request.decision.ruleIndices)) }
        let chosen = showMore ? chosenIngredients : Array(ingredients.prefix(1))
        guard !chosen.isEmpty else { return PickerChoice(target: target) }
        let rule = Rule(name: chosen.map(\.label).joined(separator: " · "), when: chosen.map(\.condition), open: target)
        return PickerChoice(target: target, ruleChange: .add(rule))
    }
}

extension Ingredient {
    @MainActor var label: String {
        switch self {
        case let .website(host): host
        case let .pathWord(word): "/\(word)"
        case let .app(bundleID): "from " + (Catalog.appName(bundleID) ?? bundleID)
        }
    }
}

struct PickerView: View {
    @Bindable var model: PickerModel
    var onPick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(model.request.link.url.absoluteString)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if let app = model.request.link.sourceApp {
                    Text("from " + (Catalog.appName(app) ?? app)).font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 2) {
                ForEach(Array(model.options.enumerated()), id: \.element.id) { index, option in
                    Button { onPick(index) } label: {
                        HStack(spacing: 8) {
                            Text(index < 9 ? "\(index + 1)" : " ")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            if let icon = Catalog.icon(option.target.browser) {
                                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                            }
                            Text(option.label)
                            Spacer()
                            if option.target == model.request.decision.target {
                                Text(model.request.reason == .reopen ? "opened here" : "rule says")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .background(index == model.highlighted ? Color.accentColor.opacity(0.25) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .onHover { if $0 { model.highlighted = index } }
                }
            }

            Divider()

            HStack {
                Toggle(model.rememberLabel, isOn: $model.remember)
                Spacer()
                if !model.fixesExistingRule {
                    Button(model.showMore ? "Fewer options" : "More options…") { model.showMore.toggle() }
                        .buttonStyle(.link)
                }
            }

            if model.showMore, !model.fixesExistingRule {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Match links that have all of:").font(.caption).foregroundStyle(.secondary)
                    FlowRow(items: model.ingredients) { ingredient in
                        Toggle(ingredient.label, isOn: Binding(
                            get: { model.picked.contains(ingredient) },
                            set: { if $0 { model.picked.insert(ingredient) } else { model.picked.remove(ingredient) } }
                        ))
                        .toggleStyle(.button)
                    }
                    if model.chosenIngredients.isEmpty {
                        Text("Pick at least one, or no rule is saved.").font(.caption).foregroundStyle(.orange)
                    }
                }
            }

            Text("1–9 to open · ↑↓ and ↩ · esc to cancel")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 400)
    }

    private var title: String {
        switch model.request.reason {
        case .noRuleMatched: "No rule matched. Open in:"
        case .modifierHeld: "Open in:"
        case .reopen: "Reopen last link in:"
        }
    }
}

/// Lays chips out left to right, wrapping onto new lines.
private struct FlowRow<Item: Hashable, Content: View>: View {
    var items: [Item]
    var content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

/// A floating panel near the mouse that takes keyboard focus without activating Direct.
@MainActor
final class PickerController {
    private var panel: PickerPanel?
    private var keyMonitor: Any?
    private var completion: ((PickerChoice?) -> Void)?

    func show(_ request: PickerRequest, options: [TargetOption], completion: @escaping (PickerChoice?) -> Void) {
        finish(nil)
        let model = PickerModel(request: request, options: options)
        let view = PickerView(
            model: model,
            onPick: { [weak self, weak model] index in self?.finish(model?.choice(at: index)) }
        )
        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]

        let panel = PickerPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                                backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = host
        panel.setContentSize(host.view.fittingSize)
        panel.setFrameTopLeftPoint(Self.topLeft(for: panel.frame.size))
        panel.onResignKey = { [weak self] in self?.finish(nil) }

        self.panel = panel
        self.completion = completion
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak model] event in
            guard let self, let model else { return event }
            return self.handle(event, model: model) ? nil : event
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func handle(_ event: NSEvent, model: PickerModel) -> Bool {
        switch event.keyCode {
        case 53: finish(nil)
        case 36, 76: finish(model.choice(at: model.highlighted))
        case 125: model.move(1)
        case 126: model.move(-1)
        default:
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let digit = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(digit),
                  digit <= model.options.count else { return false }
            finish(model.choice(at: digit - 1))
        }
        return true
    }

    private func finish(_ choice: PickerChoice?) {
        guard let completion else { return }
        self.completion = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.onResignKey = nil
        panel?.orderOut(nil)
        panel = nil
        completion(choice)
    }

    private static func topLeft(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return mouse }
        let x = min(max(mouse.x - 24, visible.minX + 8), visible.maxX - size.width - 8)
        let y = max(min(mouse.y + 12, visible.maxY - 8), visible.minY + size.height + 8)
        return NSPoint(x: x, y: y)
    }
}

final class PickerPanel: NSPanel {
    var onResignKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
