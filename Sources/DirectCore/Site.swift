import Foundation

extension Link {
    /// The link's host without a leading "www.", as used for "Always use this for <site>".
    public var site: String? {
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
