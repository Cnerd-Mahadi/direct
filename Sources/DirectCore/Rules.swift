import Foundation

/// A link as Direct receives it: the URL plus where the click came from.
public struct Link: Sendable, Equatable {
    public var url: URL
    public var sourceApp: String?

    public init(url: URL, sourceApp: String?) {
        self.url = url
        self.sourceApp = sourceApp
    }
}

/// Where a link opens. `profile` is a Chromium profile directory such as "Profile 14".
public struct Target: Codable, Sendable, Hashable {
    public var browser: String
    public var profile: String?

    public init(browser: String, profile: String? = nil) {
        self.browser = browser
        self.profile = profile
    }
}

public enum HostMatch: String, Codable, Sendable {
    case exactly
    /// The host itself or any subdomain of it: "github.com" matches "gist.github.com".
    case domain
    case contains
}

public enum TextMatch: String, Codable, Sendable {
    case contains, startsWith, endsWith, exactly
}

public enum Condition: Sendable, Equatable {
    case host(String, HostMatch)
    case path(String, TextMatch, caseSensitive: Bool)
    case url(String, TextMatch, caseSensitive: Bool)
    /// Matches when the link came from any of these apps (bundle identifiers).
    case app([String])
}

/// All conditions must match. Exceptions are only checked when the rule itself matches,
/// so they inherit the parent's conditions, and a matching exception overrides the parent.
public struct Rule: Sendable, Equatable {
    public var name: String
    public var enabled: Bool
    public var when: [Condition]
    public var open: Target
    public var except: [Rule]

    public init(name: String, enabled: Bool = true, when: [Condition], open: Target, except: [Rule] = []) {
        self.name = name
        self.enabled = enabled
        self.when = when
        self.open = open
        self.except = except
    }
}

/// Top-level rules are checked in order and the first match wins. Nothing matched means `fallback`.
public struct RuleSet: Codable, Sendable, Equatable {
    public var rules: [Rule]
    public var fallback: Target

    public init(rules: [Rule], fallback: Target) {
        self.rules = rules
        self.fallback = fallback
    }
}

public struct Decision: Sendable, Equatable {
    public var target: Target
    /// Names from the top-level rule down to the exception that decided. Empty means fallback.
    public var rulePath: [String]
    /// The same path as positions: [2, 0] is the first exception of the third rule.
    public var ruleIndices: [Int]
}

extension RuleSet {
    public func route(_ link: Link) -> Decision {
        for (index, rule) in rules.enumerated() {
            if let decision = rule.route(link, names: [], indices: [index]) { return decision }
        }
        return Decision(target: fallback, rulePath: [], ruleIndices: [])
    }
}

extension Rule {
    func route(_ link: Link, names: [String], indices: [Int]) -> Decision? {
        guard enabled, when.allSatisfy({ $0.matches(link) }) else { return nil }
        let names = names + [name]
        for (index, exception) in except.enumerated() {
            if let decision = exception.route(link, names: names, indices: indices + [index]) { return decision }
        }
        return Decision(target: open, rulePath: names, ruleIndices: indices)
    }
}

extension Condition {
    /// An empty condition never matches, so a half-written rule can't catch links.
    func matches(_ link: Link) -> Bool {
        switch self {
        case let .host(value, match):
            let value = value.trimmingCharacters(in: .whitespaces).lowercased()
            guard !value.isEmpty, let host = link.url.host()?.lowercased() else { return false }
            switch match {
            case .exactly: return host == value
            case .domain: return host == value || host.hasSuffix("." + value)
            case .contains: return host.contains(value)
            }
        case let .path(value, match, caseSensitive):
            return match.test(link.url.path(percentEncoded: false), value, caseSensitive: caseSensitive)
        case let .url(value, match, caseSensitive):
            return match.test(link.url.absoluteString, value, caseSensitive: caseSensitive)
        case let .app(bundleIDs):
            guard let source = link.sourceApp else { return false }
            return bundleIDs.contains { $0.caseInsensitiveCompare(source) == .orderedSame }
        }
    }
}

extension TextMatch {
    func test(_ text: String, _ value: String, caseSensitive: Bool) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let text = caseSensitive ? text : text.lowercased()
        let value = caseSensitive ? trimmed : trimmed.lowercased()
        switch self {
        case .contains: return text.contains(value)
        case .startsWith: return text.hasPrefix(value)
        case .endsWith: return text.hasSuffix(value)
        case .exactly: return text == value
        }
    }
}
