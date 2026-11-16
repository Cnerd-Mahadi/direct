import AppKit
import SwiftUI

/// A short note after the picker changed rules, with Undo. Never takes keyboard focus.
@MainActor
final class ToastController {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ message: String, near topLeft: NSPoint?, undo: (() -> Void)?) {
        hide()
        let view = ToastView(message: message, onUndo: undo.map { undo in { [weak self] in
            undo()
            self?.hide()
        } })
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        let panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = host
        panel.setContentSize(host.sizeThatFits(in: NSSize(width: 10_000, height: 10_000)))
        panel.setFrameTopLeftPoint(topLeft ?? NSEvent.mouseLocation)
        panel.orderFrontRegardless()
        self.panel = panel
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { self?.hide() }
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct ToastView: View {
    var message: String
    var onUndo: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(message).fixedSize(horizontal: false, vertical: true)
            if let onUndo {
                Button("Undo", action: onUndo)
            }
        }
        .padding(12)
        .frame(width: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
