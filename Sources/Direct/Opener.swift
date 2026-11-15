import AppKit
import DirectCore

enum OpenMethod: String, Codable {
    /// Handed to the running Chromium browser over its singleton socket. No second process.
    case socket
    /// Browser was not running, so it was launched with the profile argument.
    case launchWithProfile
    /// Socket failed while the browser was running. A short-lived second process forwarded the link.
    case forwardedLaunch
    /// No profile involved. macOS handed the link to the browser.
    case workspace
}

struct OpenError: Error, CustomStringConvertible {
    var description: String
}

@MainActor
enum Opener {
    static func open(_ url: URL, in target: Target) async throws -> OpenMethod {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.browser) else {
            throw OpenError(description: "\(target.browser) is not installed")
        }
        guard let profile = target.profile, let dataDir = Chromium.userDataDir(for: target.browser) else {
            try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: .init())
            return .workspace
        }
        // Chromium silently creates a fresh profile for an unknown directory, so refuse instead.
        guard FileManager.default.fileExists(atPath: dataDir.appending(path: profile).path) else {
            throw OpenError(description: "\(target.browser) has no profile directory \"\(profile)\"")
        }
        guard let executable = Bundle(url: appURL)?.executableURL else {
            throw OpenError(description: "Cannot find the executable inside \(appURL.path)")
        }

        let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: target.browser).isEmpty
        guard isRunning else {
            let config = NSWorkspace.OpenConfiguration()
            config.arguments = ["--profile-directory=\(profile)", url.absoluteString]
            try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            return .launchWithProfile
        }

        let socket = dataDir.appending(path: "SingletonSocket")
        let message = Chromium.singletonMessage(executable: executable.path, profile: profile, url: url)
        if await Task.detached(operation: { SingletonSocket.send(message, via: socket) }).value {
            return .socket
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["--profile-directory=\(profile)", url.absoluteString]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return .forwardedLaunch
    }
}

enum SingletonSocket {
    /// `link` is the SingletonSocket symlink in the browser's user data directory.
    /// Returns true when the running browser acknowledged the message.
    static func send(_ message: Data, via link: URL) -> Bool {
        guard let path = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return false }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8CString)
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { dst in
            pathBytes.withUnsafeBytes { dst.copyMemory(from: $0) }
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return false }

        let sent = message.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
        guard sent == message.count else { return false }
        shutdown(fd, SHUT_WR)

        var reply = [UInt8](repeating: 0, count: 16)
        let received = recv(fd, &reply, reply.count, 0)
        return received >= 3 && reply.starts(with: Array("ACK".utf8))
    }
}
