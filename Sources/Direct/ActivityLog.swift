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
    var target: Target
    var method: OpenMethod?
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
