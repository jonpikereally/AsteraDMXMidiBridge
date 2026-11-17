import Foundation

/// A fixture patch saved to disk so it can be shared or reloaded.
/// It holds the fixtures, MIDI channel and master CC, but not the output destination.
public struct PatchFile: Codable, Equatable, Sendable {
    public static let formatName = "AsteraDMXMidiBridge.patch"
    public static let currentVersion = 1
    public static let fileExtension = "json"

    public var format: String
    public var version: Int
    public var midiChannel: Int
    public var masterCC: Int
    public var fixtures: [FixturePatch]

    public init(config: BridgeConfig) {
        format = Self.formatName
        version = Self.currentVersion
        midiChannel = config.midiChannel
        masterCC = config.masterCC
        fixtures = config.fixtures
    }

    public static func export(_ config: BridgeConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(PatchFile(config: config))
    }

    /// Reads a patch file and applies it on top of `base`, keeping the base's output destination.
    /// Throws `PatchFileError` for an unreadable or unsupported file, or `PatchError` if the patch is invalid.
    public static func load(_ data: Data, into base: BridgeConfig) throws -> BridgeConfig {
        struct Header: Decodable { var format: String?; var version: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else {
            throw PatchFileError.unreadable
        }
        guard header.format == formatName else { throw PatchFileError.notAPatch }
        guard let version = header.version, version <= currentVersion else { throw PatchFileError.newerVersion }
        guard let file = try? JSONDecoder().decode(PatchFile.self, from: data), !file.fixtures.isEmpty else {
            throw PatchFileError.unreadable
        }
        var config = base
        config.midiChannel = file.midiChannel
        config.masterCC = file.masterCC
        config.fixtures = file.fixtures
        try config.validated(requireHost: false)
        return config
    }
}

public enum PatchFileError: LocalizedError, Equatable {
    case unreadable
    case notAPatch
    case newerVersion
    case exportFailed

    public var code: String {
        switch self {
        case .unreadable: "AX1-210"
        case .notAPatch: "AX1-211"
        case .newerVersion: "AX1-212"
        case .exportFailed: "AX1-213"
        }
    }

    public var errorDescription: String? {
        let message: String
        switch self {
        case .unreadable:
            message = "The patch file couldn’t be read. Export it again from AsteraDMXMidiBridge."
        case .notAPatch:
            message = "That file isn’t an AsteraDMXMidiBridge patch."
        case .newerVersion:
            message = "That patch was saved by a newer version of AsteraDMXMidiBridge. Update the app, then import it again."
        case .exportFailed:
            message = "The patch couldn’t be saved there. Choose another folder and try again."
        }
        return "\(code) · \(message)"
    }
}
