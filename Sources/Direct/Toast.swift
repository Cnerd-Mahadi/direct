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
        let panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = host
        panel.setContentSize(host.sizeThatFits(in: NSSize(width: 10_000, height: 10_000)))
        panel.setFrameTopLeftPoint(topLeft ?? NSEvent.mouseLocation)
        panel.orderFrontRegardless()
        self.panel = panel
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
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
        HStack(spacing: 12) {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Theme.good, in: Circle())
            Text(message).font(Theme.ui(13)).foregroundStyle(Theme.HUD.text).lineLimit(2)
            if let onUndo {
                Button(action: onUndo) {
                    Text("Undo").font(Theme.ui(13, .semibold)).foregroundStyle(Theme.HUD.link)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Theme.HUD.tile, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, onUndo == nil ? 16 : 7)
        .frame(height: 44)
        .background(Theme.HUD.background, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.HUD.line, lineWidth: 1))
        .fixedSize()
    }
}
