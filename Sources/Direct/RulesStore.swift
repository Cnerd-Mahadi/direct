import Foundation
import Observation
import DirectCore

/// The rules window's state. Every edit is written to rules.json right away, and the
/// router re-reads that file per link, so changes apply instantly.
@MainActor
@Observable
final class RulesStore {
    var rules: [RuleDraft] = [] { didSet { save() } }
    var fallback: Fallback = .open(Target(browser: "com.apple.Safari")) { didSet { save() } }
    /// Set when rules.json exists but can't be read. Saving is off so a hand edit is never clobbered.
    private(set) var loadError: String?
    private(set) var saveError: String?
    private var loading = false

    var ruleSet: RuleSet {
        RuleSet(rules: rules.map(\.rule), fallback: fallback)
    }

    func load() {
        loading = true
        defer { loading = false }
        do {
            let set = try RuleSet.load(from: Paths.rules)
            rules = set.rules.map(RuleDraft.init)
            fallback = set.fallback
            loadError = nil
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            rules = []
            loadError = nil
        } catch {
            loadError = Self.describe(error)
        }
    }

    private func save() {
        guard !loading, loadError == nil else { return }
        do {
            try FileManager.default.createDirectory(at: Paths.rules.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ruleSet.encoded().write(to: Paths.rules, options: .atomic)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }
        let context: DecodingError.Context
        switch error {
        case let .dataCorrupted(c), let .keyNotFound(_, c), let .typeMismatch(_, c), let .valueNotFound(_, c): context = c
        @unknown default: return "\(error)"
        }
        let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        let detail = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
        return [path.isEmpty ? nil : "At \(path)", context.debugDescription, detail].compactMap { $0 }.joined(separator: ": ")
    }
}
