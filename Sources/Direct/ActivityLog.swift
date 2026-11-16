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
    var error: String?
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
    /// The most recent link Direct actually opened, so reopening survives a restart.
    static func lastOpened() -> ActivityEntry? {
        guard let data = try? Data(contentsOf: Paths.activityLog) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for line in data.split(separator: 0x0A).reversed() {
            if let entry = try? decoder.decode(ActivityEntry.self, from: Data(line)), entry.target != nil, entry.method != nil {
                return entry
            }
        }
        return nil
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
