import AppKit
import SwiftUI
import DirectCore

struct PickerRequest {
    enum Reason { case noRuleMatched, modifierHeld, reopen }

    var link: DirectCore.Link
    /// What the current rules decide for this link.
    var decision: Decision
    /// For a reopen: where the link actually opened last time.
    var openedIn: Target?
    var reason: Reason
}

/// What to remember besides opening the link.
enum SaveChoice {
    case nothing
    /// Direct decides how: exception, repoint, or new rule.
    case alwaysForSite(String)
    /// Built in More…; added as an exception to the rule at this index, or as a new top rule.
    case custom(RuleDraft, exceptionOf: Int?)
}

struct PickerChoice {
    var target: Target
    var save: SaveChoice
}

@MainActor
@Observable
final class PickerModel {
    enum Mode { case once, always, custom }

    let request: PickerRequest
    let options: [TargetOption]
    var highlighted: Int
    var mode: Mode = .once
    var draft: RuleDraft
    var addAsException: Bool

    init(request: PickerRequest, options: [TargetOption]) {
        self.request = request
        self.options = options
        let preferred = request.openedIn == nil ? request.decision.target : nil
        highlighted = options.firstIndex { $0.target == preferred } ?? 0
        let site = request.link.site ?? ""
        var draft = RuleDraft(name: site, target: options.first?.target ?? Target(browser: "com.apple.Safari"))
        draft.conditions[0].text = site
        self.draft = draft
        addAsException = !request.decision.ruleIndices.isEmpty
    }

    var site: String { request.link.site ?? "this site" }

    /// The base rule that fired, which a custom rule can be added under.
    var firedRule: (index: Int, name: String)? {
        guard let index = request.decision.ruleIndices.first, let name = request.decision.rulePath.first else { return nil }
        return (index, name)
    }

    func move(_ delta: Int) {
        guard !options.isEmpty else { return }
        highlighted = (highlighted + delta + options.count) % options.count
    }

    func choice(at index: Int) -> PickerChoice? {
        guard options.indices.contains(index) else { return nil }
        let target = options[index].target
        switch mode {
        case .once: return PickerChoice(target: target, save: .nothing)
        case .always: return PickerChoice(target: target, save: request.link.site.map(SaveChoice.alwaysForSite) ?? .nothing)
        case .custom: return customChoice()
        }
    }

    func customChoice() -> PickerChoice {
        PickerChoice(target: draft.target, save: .custom(draft, exceptionOf: addAsException ? firedRule?.index : nil))
    }
}

struct PickerView: View {
    @Bindable var model: PickerModel
    var targets: [TargetOption]
    var onChoose: (PickerChoice?) -> Void
    var onResize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if model.mode == .custom {
                customEditor
            } else {
                browserList
                Divider()
                saveOptions
            }
        }
        .padding(14)
        .frame(width: model.mode == .custom ? 560 : 400)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: model.mode) { onResize() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { onChoose(nil) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Close without opening (esc)")
            }
            Text(model.request.link.url.absoluteString)
                .font(.callout)
                .lineLimit(2)
                .truncationMode(.middle)
            Text(context).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var browserList: some View {
        VStack(spacing: 2) {
            ForEach(Array(model.options.enumerated()), id: \.element.id) { index, option in
                Button { onChoose(model.choice(at: index)) } label: {
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
                        if let tag = tag(for: option.target) {
                            Text(tag).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .background(index == model.highlighted ? Color.accentColor.opacity(0.25) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var saveOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $model.mode) {
                Text("Just this once").tag(PickerModel.Mode.once)
                Text("Always use this for \(model.site)").tag(PickerModel.Mode.always)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            HStack {
                Button("More…") { model.mode = .custom }.buttonStyle(.link)
                Spacer()
                Text("1–9 to open · ↑↓ ↩ · esc").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var customEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Open links that match").font(.caption).foregroundStyle(.secondary)
            ConditionList(conditions: $model.draft.conditions, showMore: true)
            HStack {
                Text("in")
                TargetPicker(target: $model.draft.target, targets: targets)
            }
            if let fired = model.firedRule {
                Picker("", selection: $model.addAsException) {
                    Text("As an exception to “\(fired.name)”").tag(true)
                    Text("As a new rule at the top").tag(false)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            HStack {
                Button("Back") { model.mode = .once }
                Spacer()
                Button("Save and Open") { onChoose(model.customChoice()) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.draft.conditions.isEmpty)
            }
        }
    }

    private var title: String {
        switch model.request.reason {
        case .noRuleMatched: "No rule matched. Open in:"
        case .modifierHeld: "Open in:"
        case .reopen: "Reopen in:"
        }
    }

    private var context: String {
        let source = model.request.link.sourceApp.map { "from " + (Catalog.appName($0) ?? $0) }
        let rule = model.request.decision.rulePath.isEmpty
            ? "no rule matched"
            : "rule “\(model.request.decision.rulePath.joined(separator: " › "))”"
        return [source, rule].compactMap { $0 }.joined(separator: " · ")
    }

    private func tag(for target: Target) -> String? {
        if target == model.request.openedIn { return "opened here" }
        if target == model.request.decision.target { return "rule says" }
        return nil
    }
}

/// A floating panel near the mouse that takes keyboard focus without activating Direct.
/// It stays up when another app takes focus, so a link is never dropped by a focus race:
/// only a choice, esc, or the close button ends it.
@MainActor
final class PickerController {
    private var panel: PickerPanel?
    private var keyMonitor: Any?
    private var completion: ((PickerChoice?) -> Void)?
    private(set) var lastTopLeft: NSPoint?

    func show(_ request: PickerRequest, options: [TargetOption], completion: @escaping (PickerChoice?) -> Void) {
        finish(nil)
        let model = PickerModel(request: request, options: options)
        let view = PickerView(model: model, targets: options,
                              onChoose: { [weak self] choice in self?.finish(choice) },
                              onResize: { [weak self] in self?.fitToContent() })
        // Sized by hand: letting the window follow the content's preferred size looped
        // between window and content layout until AppKit crashed the app.
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []

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
        panel.setContentSize(Self.measure(host))
        let topLeft = Self.topLeft(for: panel.frame.size)
        panel.setFrameTopLeftPoint(topLeft)
        lastTopLeft = topLeft

        self.panel = panel
        self.completion = completion
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak model] event in
            guard let self, let model else { return event }
            return self.handle(event, model: model) ? nil : event
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func handle(_ event: NSEvent, model: PickerModel) -> Bool {
        if event.keyCode == 53 {
            finish(nil)
            return true
        }
        // In More… the keyboard belongs to the text fields.
        guard model.mode != .custom else { return false }
        switch event.keyCode {
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

    /// Re-measures after the content changed shape, keeping the top-left corner in place.
    private func fitToContent() {
        DispatchQueue.main.async { [weak self] in
            guard let panel = self?.panel, let host = panel.contentViewController as? NSHostingController<PickerView>
            else { return }
            let top = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
            panel.setContentSize(Self.measure(host))
            panel.setFrameTopLeftPoint(top)
        }
    }

    /// The size SwiftUI wants; the view fixes its own width and height.
    private static func measure<Content: View>(_ host: NSHostingController<Content>) -> NSSize {
        host.sizeThatFits(in: NSSize(width: 10_000, height: 10_000))
    }

    private func finish(_ choice: PickerChoice?) {
        guard let completion else { return }
        self.completion = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
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
    override var canBecomeKey: Bool { true }
}
