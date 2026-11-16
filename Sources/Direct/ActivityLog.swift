import Foundation
import DirectCore

enum Paths {
    static let rules = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Direct/rules.json")
    static let activityLog = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/Direct/activity.jsonl")
}

/// One line per routed link, so "why did this open here?" always has an answer.
struct ActivityEntry: Codable {
    enum SourceVia: String, Codable {
        /// The process that sent the open-URL event.
        case sender
        /// Best guess: the last app in front before Direct got the link.
        case frontmost
    }

    var time = Date()
    var url: String
    var sourceApp: String?
    var sourceVia: SourceVia
    var rule: [String]
    var target: Target?
    var method: OpenMethod?
    /// True when the person chose in the picker rather than a rule deciding.
    var picked: Bool?
    /// True when this open came from reopening an earlier link (⌃⌥D or Reopen on Home).
    var reopened: Bool?
    var error: String?

    /// A link that actually opened somewhere, as opposed to a cancelled picker.
    var opened: Bool { target != nil && method != nil }
}

enum ActivityLog {
    static func append(_ entry: ActivityEntry) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)

        let file = Paths.activityLog
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: file)
        }
    }
}

extension ActivityLog {
    /// Every entry, newest first.
    static func entries() -> [ActivityEntry] {
        guard let data = try? Data(contentsOf: Paths.activityLog) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).reversed().compactMap { try? decoder.decode(ActivityEntry.self, from: Data($0)) }
    }

    /// The most recent link Direct actually opened, so reopening survives a restart.
    static func lastOpened() -> ActivityEntry? {
        entries().first(where: \.opened)
    }
}

/// What Home shows: counts for this month and the latest opened links.
struct ActivitySummary {
    var opened = 0
    var picked = 0
    var reopened = 0
    var recent: [ActivityEntry] = []

    init(_ entries: [ActivityEntry], now: Date = Date(), recentCount: Int = 8) {
        let monthStart = Calendar.current.dateInterval(of: .month, for: now)?.start ?? now
        for entry in entries where entry.opened && entry.time >= monthStart {
            opened += 1
            if entry.reopened == true { reopened += 1 } else if entry.picked == true { picked += 1 }
        }
        recent = Array(entries.lazy.filter(\.opened).prefix(recentCount))
    }
}

/// Plain-text diagnostics in ~/Library/Logs/Direct/debug.log, for things the activity log doesn't cover.
enum DebugLog {
    static func write(_ message: String) {
        let file = Paths.activityLog.deletingLastPathComponent().appending(path: "debug.log")
        let line = Data("\(ISO8601DateFormatter().string(from: Date())) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: file)
        }
    }
}
