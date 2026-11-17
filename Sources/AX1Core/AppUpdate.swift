import Foundation

/// A release version such as `1.3.0` or `v1.3`, compared number by number.
public struct ReleaseVersion: Comparable, Sendable {
    public let numbers: [Int]

    public init?(_ tag: String) {
        let version = (tag.first == "v" || tag.first == "V") ? tag.dropFirst() : tag[...]
        let parts = version.split(separator: "+", omittingEmptySubsequences: false)
        guard let main = parts.first, parts.count <= 2 else { return nil }
        if let build = parts.dropFirst().first {
            let identifiers = build.split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty, identifiers.allSatisfy({ identifier in
                !identifier.isEmpty && identifier.utf8.allSatisfy { byte in
                    (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45
                }
            }) else { return nil }
        }

        let components = main.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count) else { return nil }
        let numbers = components.compactMap { component -> Int? in
            guard !component.isEmpty, component.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return Int(component)
        }
        guard numbers.count == components.count else { return nil }
        self.numbers = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    public var text: String { numbers.map(String.init).joined(separator: ".") }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        lhs.numbers.lexicographicallyPrecedes(rhs.numbers)
    }
}

/// Rules the in-app updater uses before it downloads or installs a release.
public enum AppUpdate {
    public static let bundleIdentifier = "com.jonpike.ax1bridge"
    public static let appName = "AsteraDMXMidiBridge.app"
    public static let assetName = "AsteraDMXMidiBridge.zip"
    public static let downloadPathPrefix = "/jonpikereally/AsteraDMXMidiBridge/releases/download/"

    /// The app ZIP's download URL, when the release has one served from this project's GitHub releases.
    public static func downloadURL(assets: [(name: String, url: String)]) -> URL? {
        guard let asset = assets.first(where: { $0.name == assetName }),
              let url = URL(string: asset.url), url.scheme == "https", url.host == "github.com",
              url.port == nil, url.user == nil, url.password == nil,
              url.path.hasPrefix(downloadPathPrefix), url.lastPathComponent == assetName else { return nil }
        return url
    }

    /// Whether the download may follow a redirect to this URL (GitHub and its asset storage only, over HTTPS).
    public static func allowsDownloadRedirect(to url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(),
              url.port == nil || url.port == 443, url.user == nil, url.password == nil else { return false }
        return host == "github.com" || host.hasSuffix(".githubusercontent.com")
    }

    /// Why a downloaded app bundle's Info.plist must not be installed, or nil when it is the expected update.
    public static func bundleProblem(info: [String: Any], expected: ReleaseVersion, installed: ReleaseVersion) -> String? {
        guard info["CFBundleIdentifier"] as? String == bundleIdentifier else {
            return "it is not AsteraDMXMidiBridge"
        }
        guard let text = info["CFBundleShortVersionString"] as? String, let version = ReleaseVersion(text) else {
            return "its version can’t be read"
        }
        guard version == expected else { return "it is version \(version.text), not \(expected.text)" }
        guard installed < version else { return "it is not newer than version \(installed.text)" }
        guard let executable = info["CFBundleExecutable"] as? String, executable == "AsteraDMXMidiBridge" else {
            return "its executable is missing"
        }
        return nil
    }
}
