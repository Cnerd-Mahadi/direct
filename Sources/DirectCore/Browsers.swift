import Foundation

/// Chromium-family browsers, keyed by bundle identifier, with their user data directory
/// relative to ~/Library/Application Support. Profiles and the singleton socket live there.
public enum Chromium {
    public static let userDataDirs: [String: String] = [
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.brave.Browser.beta": "BraveSoftware/Brave-Browser-Beta",
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "org.chromium.Chromium": "Chromium",
    ]

    public static func userDataDir(for bundleID: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        userDataDirs[bundleID].map {
            home.appending(path: "Library/Application Support").appending(path: $0, directoryHint: .isDirectory)
        }
    }

    public struct Profile: Sendable, Equatable {
        public var directory: String
        public var name: String
        /// The color the person picked for this profile in the browser, as 0xRRGGBB.
        public var color: UInt32?

        public init(directory: String, name: String, color: UInt32? = nil) {
            self.directory = directory
            self.name = name
            self.color = color
        }
    }

    /// Reads profile directories, display names and colors from the browser's "Local State" file.
    public static func profiles(localState: Data) throws -> [Profile] {
        struct LocalState: Decodable {
            struct ProfileSection: Decodable { var info_cache: [String: Info] }
            struct Info: Decodable {
                var name: String
                /// Signed ARGB, as Chromium stores it.
                var profile_color_seed: Int64?
            }
            var profile: ProfileSection
        }
        return try JSONDecoder().decode(LocalState.self, from: localState).profile.info_cache
            .map { Profile(directory: $0.key, name: $0.value.name,
                           color: $0.value.profile_color_seed.map { UInt32(truncatingIfNeeded: $0) & 0xFFFFFF }) }
            .sorted { $0.directory.localizedStandardCompare($1.directory) == .orderedAscending }
    }

    /// The message a second browser process sends over the singleton socket to hand its
    /// command line to the running browser. Writing it ourselves means no second process.
    public static func singletonMessage(executable: String, profile: String, url: URL) -> Data {
        Data(["START", "/", executable, "--profile-directory=\(profile)", url.absoluteString].joined(separator: "\0").utf8)
    }
}
