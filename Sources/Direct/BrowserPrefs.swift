import Foundation
import Observation
import DirectCore

/// Which targets the picker shows, and in what order. The order is also each one's number key.
@MainActor
@Observable
final class BrowserPrefs {
    /// Apps that register for web links but aren't browsers anyone picks on purpose.
    private static let hiddenAtFirst: Set<String> = ["com.google.chrome.for.testing", "com.openai.codex", "com.openai.chat"]

    private(set) var order: [Target]
    private(set) var hidden: Set<Target>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        order = Self.read([Target].self, "browserOrder", defaults) ?? []
        hidden = Set(Self.read([Target].self, "hiddenBrowsers", defaults) ?? [])
        if defaults.object(forKey: "hiddenBrowsers") == nil {
            hidden = Set(Catalog.targets().map(\.target).filter { Self.hiddenAtFirst.contains($0.browser) })
        }
    }

    /// All targets split into the picker's list, in the person's order, and the hidden rest.
    func arrange(_ all: [TargetOption]) -> (shown: [TargetOption], hidden: [TargetOption]) {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = all.enumerated().sorted { a, b in
            (rank[a.element.target] ?? order.count + a.offset) < (rank[b.element.target] ?? order.count + b.offset)
        }.map(\.element)
        return (sorted.filter { !hidden.contains($0.target) }, sorted.filter { hidden.contains($0.target) })
    }

    func setHidden(_ target: Target, _ isHidden: Bool) {
        if isHidden { hidden.insert(target) } else { hidden.remove(target) }
        Self.write(Array(hidden), "hiddenBrowsers", defaults)
    }

    func setOrder(_ shown: [Target]) {
        order = shown
        Self.write(order, "browserOrder", defaults)
    }

    private static func read<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func write<T: Encodable>(_ value: T, _ key: String, _ defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
