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
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.mode == .custom {
                customEditor
            } else {
                tiles
                footer
            }
        }
        .padding(EdgeInsets(top: 16, leading: 12, bottom: 12, trailing: 12))
        .frame(width: model.mode == .custom ? 640 : width)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.HUD.background, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.HUD.line, lineWidth: 1))
        .foregroundStyle(Theme.HUD.text)
        .font(Theme.ui(13))
        .environment(\.colorScheme, .dark)
        .onChange(of: model.mode) { onResize() }
    }

    private static let columns = 6
    private static let tileWidth: CGFloat = 116
    private var width: CGFloat { CGFloat(max(4, min(model.options.count, Self.columns))) * (Self.tileWidth + 4) + 20 }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                (Text(model.request.link.url.host() ?? "").fontWeight(.semibold)
                    + Text(pathAndQuery).foregroundColor(Theme.HUD.secondary))
                    .font(Theme.ui(14))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(context).font(Theme.ui(12)).foregroundStyle(Theme.HUD.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            Button { onChoose(nil) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Theme.HUD.chip, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close without opening (esc)")
            .accessibilityLabel("Close without opening")
        }
        .padding(.horizontal, 8)
    }

    private var tiles: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.tileWidth), spacing: 4), count: min(max(model.options.count, 1), Self.columns)),
                  spacing: 4) {
            ForEach(Array(model.options.enumerated()), id: \.element.id) { index, option in
                Button { onChoose(model.choice(at: index)) } label: {
                    VStack(spacing: 7) {
                        TargetIcon(option, size: 48, ring: Color(hex: index == model.highlighted ? 0x2A2A2A : 0x161616))
                        Text(option.title)
                            .font(Theme.ui(12, index == model.highlighted ? .semibold : .medium))
                            .foregroundStyle(index == model.highlighted ? Theme.HUD.text : Theme.HUD.secondary)
                            .lineLimit(1)
                        Circle().fill(Theme.HUD.secondary).frame(width: 4, height: 4)
                            .opacity(option.target == model.request.openedIn ? 1 : 0)
                    }
                    .padding(EdgeInsets(top: 12, leading: 4, bottom: 6, trailing: 4))
                    .frame(width: Self.tileWidth)
                    .background(index == model.highlighted ? Theme.HUD.tile : .clear, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .topLeading) {
                        if index < 9 {
                            Text("\(index + 1)").font(Theme.ui(11, .semibold)).foregroundStyle(Theme.HUD.secondary).padding(.leading, 8).padding(.top, 6)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .help(tip(for: option))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                segment("Just this once", .once)
                segment("Always for \(model.site)", .always)
            }
            .padding(3)
            .background(Theme.HUD.chip, in: Capsule())
            Spacer()
            Button("More options") { model.mode = .custom }
                .buttonStyle(.plain)
                .font(Theme.ui(12, .semibold))
                .foregroundStyle(Theme.HUD.link)
        }
        .padding(.horizontal, 4)
    }

    private func segment(_ title: String, _ mode: PickerModel.Mode) -> some View {
        Button { model.mode = mode } label: {
            Text(title)
                .font(Theme.ui(12, .semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(model.mode == mode ? Color(hex: 0x161616) : Theme.HUD.secondary)
                .background(model.mode == mode ? Theme.HUD.text : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
    }

    private var customEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Open in")
                TargetMenu(target: $model.draft.target, targets: targets)
                Text("when")
            }
            .font(Theme.ui(14))
            ConditionList(conditions: $model.draft.conditions)
            if let fired = model.firedRule {
                Picker("", selection: $model.addAsException) {
                    Text("An exception to “\(fired.name)”, so only links that rule catches change").tag(true)
                    Text("A new rule at the top, checked before every other rule").tag(false)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .font(Theme.ui(13))
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Back") { model.mode = .once }.buttonStyle(QuietButtonStyle(fill: Theme.HUD.chip))
                Button("Save and open") { onChoose(model.customChoice()) }
                    .buttonStyle(HUDAccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.draft.conditions.isEmpty)
            }
        }
        .padding(.horizontal, 6)
    }

    private var pathAndQuery: String {
        let url = model.request.link.url
        let path = url.path(percentEncoded: false)
        return (path == "/" ? "" : path) + (url.query().map { "?" + $0 } ?? "")
    }

    private var context: String {
        let source = model.request.link.sourceApp.map { "From " + (Catalog.appName($0) ?? $0) + ". " } ?? ""
        let rule = model.request.decision.rulePath.first
        let ruleTarget = model.request.decision.target.map { Catalog.title(for: $0, in: targets) }
        let detail: String = switch model.request.reason {
        case .reopen:
            "Opened in " + (model.request.openedIn.map { Catalog.title(for: $0, in: targets) } ?? "a browser")
                + (rule.map { " by “\($0)”" } ?? "")
        case .modifierHeld:
            if let rule, let ruleTarget { "“\(rule)” would open it in \(ruleTarget)" } else { "No rule matches this link" }
        case .noRuleMatched:
            "No rule matches this link yet"
        }
        return source + detail
    }

    private func tip(for option: TargetOption) -> String {
        if option.target == model.request.openedIn { return "\(option.label), where it opened last time" }
        if option.target == model.request.decision.target { return "\(option.label), what your rules pick" }
        return option.label
    }
}

private struct HUDAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(13, .semibold))
            .foregroundStyle(Color(hex: 0x1D1B16))
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Theme.HUD.accent, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
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

    /// `options` are the picker's tiles; `all` also covers hidden targets, for names and More options.
    func show(_ request: PickerRequest, options: [TargetOption], all: [TargetOption],
              completion: @escaping (PickerChoice?) -> Void) {
        finish(nil)
        let model = PickerModel(request: request, options: options)
        let view = PickerView(model: model, targets: all,
                              onChoose: { [weak self] choice in self?.finish(choice) },
                              onResize: { [weak self] in self?.fitToContent() })
        // Sized by hand: letting the window follow the content's preferred size looped
        // between window and content layout until AppKit crashed the app.
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []

        let panel = PickerPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                                backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
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
            guard let self, let model, event.window === self.panel else { return event }
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
        case 124, 125: model.move(1)
        case 123, 126: model.move(-1)
        case 48: model.mode = model.mode == .once ? .always : .once
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
