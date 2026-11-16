import Foundation

/// Form state for one condition in the rules window. Looser than `Condition` so that
/// switching the kind mid-edit keeps the typed text. Converts to a `Condition` on save.
public struct ConditionDraft: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case app, website, path, link
    }

    public enum Match: String, CaseIterable, Sendable {
        case isOrUnder, isExactly, contains, startsWith, endsWith
    }

    public var id = UUID()
    public var kind: Kind {
        didSet { if !kind.matches.isEmpty, !kind.matches.contains(match) { match = kind.matches[0] } }
    }
    public var text: String
    public var apps: [String]
    public var match: Match
    public var caseSensitive: Bool

    public init(kind: Kind = .website) {
        self.kind = kind
        text = ""
        apps = []
        match = kind.matches.first ?? .contains
        caseSensitive = false
    }

    public init(_ condition: Condition) {
        self.init()
        switch condition {
        case let .host(value, hostMatch):
            kind = .website
            text = value
            match = switch hostMatch {
            case .domain: .isOrUnder
            case .exactly: .isExactly
            case .contains: .contains
            }
        case let .path(value, textMatch, caseSensitive):
            kind = .path
            (text, match, self.caseSensitive) = (value, Match(textMatch), caseSensitive)
        case let .url(value, textMatch, caseSensitive):
            kind = .link
            (text, match, self.caseSensitive) = (value, Match(textMatch), caseSensitive)
        case let .app(bundleIDs):
            kind = .app
            apps = bundleIDs
        }
    }

    public var condition: Condition {
        switch kind {
        case .app:
            return .app(apps)
        case .website:
            let hostMatch: HostMatch = switch match {
            case .isExactly: .exactly
            case .contains: .contains
            default: .domain
            }
            return .host(Self.hostOnly(text), hostMatch)
        case .path:
            return .path(text.trimmingCharacters(in: .whitespaces), textMatch, caseSensitive: caseSensitive)
        case .link:
            return .url(text.trimmingCharacters(in: .whitespaces), textMatch, caseSensitive: caseSensitive)
        }
    }

    private var textMatch: TextMatch {
        switch match {
        case .startsWith: .startsWith
        case .endsWith: .endsWith
        case .isExactly: .exactly
        default: .contains
        }
    }

    /// People paste whole links into the website field. Keep just the host.
    static func hostOnly(_ text: String) -> String {
        var text = text.trimmingCharacters(in: .whitespaces).lowercased()
        if text.contains("://"), let host = URL(string: text)?.host() { return host }
        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        return text
    }
}

extension ConditionDraft.Kind {
    /// The match types that make sense for this kind, default first.
    public var matches: [ConditionDraft.Match] {
        switch self {
        case .app: []
        case .website: [.isOrUnder, .isExactly, .contains]
        case .path, .link: [.contains, .startsWith, .endsWith, .isExactly]
        }
    }
}

extension ConditionDraft.Match {
    init(_ textMatch: TextMatch) {
        self = switch textMatch {
        case .contains: .contains
        case .startsWith: .startsWith
        case .endsWith: .endsWith
        case .exactly: .isExactly
        }
    }
}

/// Form state for a rule and its exceptions.
public struct RuleDraft: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var enabled: Bool
    public var conditions: [ConditionDraft]
    public var target: Target
    public var exceptions: [RuleDraft]

    public init(name: String, target: Target) {
        self.name = name
        enabled = true
        conditions = [ConditionDraft()]
        self.target = target
        exceptions = []
    }

    public init(_ rule: Rule) {
        name = rule.name
        enabled = rule.enabled
        conditions = rule.when.map(ConditionDraft.init)
        target = rule.open
        exceptions = rule.except.map(RuleDraft.init)
    }

    /// Drafts double as exception drafts; their own `exceptions` stay empty.
    public init(_ exception: Exception) {
        name = exception.name
        enabled = exception.enabled
        conditions = exception.when.map(ConditionDraft.init)
        target = exception.open
        exceptions = []
    }

    public var rule: Rule {
        Rule(name: name, enabled: enabled, when: conditions.map(\.condition), open: target, except: exceptions.map(\.exception))
    }

    public var exception: Exception {
        Exception(name: name, enabled: enabled, when: conditions.map(\.condition), open: target)
    }
}
