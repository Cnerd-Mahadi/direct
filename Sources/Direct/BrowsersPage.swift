import SwiftUI
import DirectCore

struct BrowsersPage: View {
    var prefs: BrowserPrefs
    var targets: [TargetOption]

    var body: some View {
        let (shown, hidden) = prefs.arrange(targets)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Browsers",
                           subtitle: "Choose what shows up when Direct asks. Drag to set the order, which is also the number key.")
                section("In the picker") {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, option in
                        if index > 0 { Divider().overlay(Theme.line).padding(.leading, 60) }
                        BrowserRow(option: option, key: index < 9 ? index + 1 : nil, isShown: true) {
                            prefs.setHidden(option.target, true)
                        }
                        .disabled(shown.count == 1)
                        .draggable(index.description)
                        .dropDestination(for: String.self) { items, _ in
                            guard let from = items.first.flatMap(Int.init), shown.indices.contains(from) else { return false }
                            var order = shown.map(\.target)
                            order.move(fromOffsets: [from], toOffset: from < index ? index + 1 : index)
                            prefs.setOrder(order)
                            return true
                        }
                    }
                }
                if !hidden.isEmpty {
                    section("Hidden") {
                        ForEach(Array(hidden.enumerated()), id: \.element.id) { index, option in
                            if index > 0 { Divider().overlay(Theme.line).padding(.leading, 60) }
                            BrowserRow(option: option, key: nil, isShown: false) { prefs.setHidden(option.target, false) }
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: 40, leading: 44, bottom: 40, trailing: 44))
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.ui(13, .semibold)).foregroundStyle(Theme.secondary)
            VStack(spacing: 0, content: rows).padding(.vertical, 4).card()
        }
    }
}

private struct BrowserRow: View {
    var option: TargetOption
    var key: Int?
    var isShown: Bool
    var toggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "line.3.horizontal").font(.system(size: 12)).foregroundStyle(Theme.tertiary).opacity(isShown ? 1 : 0)
            TargetIcon(option, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title).font(Theme.ui(15, .semibold))
                if option.profileName != nil {
                    Text(option.appName).font(Theme.ui(12)).foregroundStyle(Theme.secondary)
                }
            }
            Spacer()
            if let key {
                Text("\(key)")
                    .font(Theme.ui(13, .semibold))
                    .frame(minWidth: 24, minHeight: 22)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel("Number key \(key)")
            }
            Toggle("Show in picker", isOn: Binding(get: { isShown }, set: { _ in toggle() }))
                .toggleStyle(.switch)
                .tint(Theme.switchOn)
                .labelsHidden()
        }
        .opacity(isShown ? 1 : 0.6)
        .padding(.horizontal, 16)
        .frame(height: 58)
        .contentShape(Rectangle())
    }
}
