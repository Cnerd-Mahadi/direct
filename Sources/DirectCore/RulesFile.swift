import Foundation

// rules.json is meant to be read and edited by hand, so each condition is one flat object:
//   { "host": "github.com", "match": "domain" }
//   { "url": "acme", "match": "contains", "caseSensitive": true }
//   { "app": ["com.tinyspeck.slackmacgap"] }

extension RuleSet {
    public static func load(from file: URL) throws -> RuleSet {
        try JSONDecoder().decode(RuleSet.self, from: Data(contentsOf: file))
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// "fallback": "ask" or "fallback": { "browser": ... }
extension Fallback: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let word = try? c.decode(String.self) {
            guard word == "ask" else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "fallback must be \"ask\" or a target")
            }
            self = .ask
        } else {
            self = .open(try c.decode(Target.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .open(target): try c.encode(target)
        case .ask: try c.encode("ask")
        }
    }
}

extension Rule: Codable {
    private enum Key: String, CodingKey { case name, enabled, when, open, except }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        self.init(
            name: try c.decode(String.self, forKey: .name),
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            when: try c.decodeIfPresent([Condition].self, forKey: .when) ?? [],
            open: try c.decode(Target.self, forKey: .open),
            except: try c.decodeIfPresent([Exception].self, forKey: .except) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(name, forKey: .name)
        if !enabled { try c.encode(enabled, forKey: .enabled) }
        try c.encode(when, forKey: .when)
        try c.encode(open, forKey: .open)
        if !except.isEmpty { try c.encode(except, forKey: .except) }
    }
}

extension Exception: Codable {
    private enum Key: String, CodingKey { case name, enabled, when, open, except }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        guard !c.contains(.except) else {
            throw DecodingError.dataCorruptedError(forKey: .except, in: c,
                debugDescription: "An exception can't have exceptions of its own. Make it a separate rule higher in the list.")
        }
        self.init(
            name: try c.decode(String.self, forKey: .name),
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            when: try c.decodeIfPresent([Condition].self, forKey: .when) ?? [],
            open: try c.decode(Target.self, forKey: .open)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(name, forKey: .name)
        if !enabled { try c.encode(enabled, forKey: .enabled) }
        try c.encode(when, forKey: .when)
        try c.encode(open, forKey: .open)
    }
}

extension Condition: Codable {
    private enum Key: String, CodingKey { case host, path, url, app, match, caseSensitive }
    private static let subjects: [Key] = [.host, .path, .url, .app]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let present = Self.subjects.filter(c.contains)
        guard present.count == 1, let subject = present.first else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: c.codingPath,
                debugDescription: "A condition needs exactly one of: host, path, url, app"
            ))
        }
        let caseSensitive = try c.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? false
        switch subject {
        case .host:
            self = .host(try c.decode(String.self, forKey: .host),
                         try c.decodeIfPresent(HostMatch.self, forKey: .match) ?? .domain)
        case .path:
            self = .path(try c.decode(String.self, forKey: .path),
                         try c.decodeIfPresent(TextMatch.self, forKey: .match) ?? .contains,
                         caseSensitive: caseSensitive)
        case .url:
            self = .url(try c.decode(String.self, forKey: .url),
                        try c.decodeIfPresent(TextMatch.self, forKey: .match) ?? .contains,
                        caseSensitive: caseSensitive)
        default:
            if let one = try? c.decode(String.self, forKey: .app) {
                self = .app([one])
            } else {
                self = .app(try c.decode([String].self, forKey: .app))
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .host(value, match):
            try c.encode(value, forKey: .host)
            try c.encode(match, forKey: .match)
        case let .path(value, match, caseSensitive):
            try c.encode(value, forKey: .path)
            try c.encode(match, forKey: .match)
            if caseSensitive { try c.encode(true, forKey: .caseSensitive) }
        case let .url(value, match, caseSensitive):
            try c.encode(value, forKey: .url)
            try c.encode(match, forKey: .match)
            if caseSensitive { try c.encode(true, forKey: .caseSensitive) }
        case let .app(bundleIDs):
            try c.encode(bundleIDs, forKey: .app)
        }
    }
}
