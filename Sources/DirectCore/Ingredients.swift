import Foundation

/// A piece of a link the picker offers as a rule condition: tick the pieces that matter.
public enum Ingredient: Hashable, Sendable {
    case website(String)
    case pathWord(String)
    case app(String)

    public var condition: Condition {
        switch self {
        case let .website(host): .host(host, .domain)
        case let .pathWord(word): .path(word, .contains, caseSensitive: false)
        case let .app(bundleID): .app([bundleID])
        }
    }
}

extension Link {
    /// Website first (without "www."), then up to four path words, then the source app.
    public var ingredients: [Ingredient] {
        var result: [Ingredient] = []
        if let host = url.host()?.lowercased(), !host.isEmpty {
            result.append(.website(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host))
        }
        var seen: Set<String> = []
        for word in url.pathComponents where word != "/" && !word.isEmpty && seen.insert(word).inserted {
            guard seen.count <= 4 else { break }
            result.append(.pathWord(word))
        }
        if let sourceApp { result.append(.app(sourceApp)) }
        return result
    }
}
