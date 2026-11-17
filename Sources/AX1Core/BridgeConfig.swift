import Foundation

public struct RGB: Codable, Equatable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public func scaled(velocity: UInt8, master: UInt8) -> RGB {
        RGB(
            Self.scaledComponent(r, velocity: velocity, master: master),
            Self.scaledComponent(g, velocity: velocity, master: master),
            Self.scaledComponent(b, velocity: velocity, master: master)
        )
    }

    static func scaledComponent(_ component: UInt8, velocity: UInt8, master: UInt8) -> UInt8 {
        let gain = Int(min(velocity, 127)) * Int(min(master, 127))
        let full = 127 * 127
        return UInt8((Int(component) * gain + full / 2) / full)
    }
}

public struct FixturePatch: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var address: Int
    public var note: UInt8
    public var color: RGB
    public var enabled: Bool
    public var profile: AX1Profile
    public var white: UInt8
    public var independentPixels: Bool
    /// Used only by Effect Mode profiles.
    public var effect: EffectSettings

    public var noteCount: Int { independentPixels ? profile.pixelCount : 1 }
    public var maximumBaseNote: Int { 128 - noteCount }
    public var noteRange: ClosedRange<Int> { Int(note)...(Int(note) + noteCount - 1) }

    public init(
        id: UUID = UUID(), name: String, address: Int, note: UInt8, color: RGB, enabled: Bool = true,
        profile: AX1Profile = .rgb, white: UInt8 = 0, independentPixels: Bool = false,
        effect: EffectSettings = EffectSettings()
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.note = note
        self.color = color
        self.enabled = enabled
        self.profile = profile
        self.white = white
        self.independentPixels = independentPixels
        self.effect = effect
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, address, note, color, enabled, profile, white, independentPixels, effect
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            name: try values.decode(String.self, forKey: .name),
            address: try values.decode(Int.self, forKey: .address),
            note: try values.decode(UInt8.self, forKey: .note),
            color: try values.decode(RGB.self, forKey: .color),
            enabled: try values.decode(Bool.self, forKey: .enabled),
            profile: try values.decodeIfPresent(AX1Profile.self, forKey: .profile) ?? .rgb,
            white: try values.decodeIfPresent(UInt8.self, forKey: .white) ?? 0,
            independentPixels: try values.decodeIfPresent(Bool.self, forKey: .independentPixels) ?? false,
            effect: try values.decodeIfPresent(EffectSettings.self, forKey: .effect) ?? EffectSettings()
        )
    }
}

public struct BridgeConfig: Codable, Equatable, Sendable {
    public var host: String
    public var universe: Int
    public var midiChannel: Int
    public var masterCC: Int
    public var fixtures: [FixturePatch]

    public init(host: String, universe: Int, midiChannel: Int, masterCC: Int, fixtures: [FixturePatch]) {
        self.host = host
        self.universe = universe
        self.midiChannel = midiChannel
        self.masterCC = masterCC
        self.fixtures = fixtures
    }

    public static let defaults = BridgeConfig(
        host: "", universe: 0, midiChannel: 0, masterCC: 7,
        fixtures: [
            RGB(255, 73, 59), RGB(255, 153, 42), RGB(255, 223, 90), RGB(84, 231, 132),
            RGB(44, 223, 216), RGB(72, 146, 255), RGB(156, 111, 255), RGB(245, 107, 210),
        ].enumerated().map { index, color in
            FixturePatch(name: "AX1 \(index + 1)", address: 1 + index * 3, note: UInt8(36 + index), color: color)
        }
    )

    public func validated() throws {
        try validated(requireHost: true)
    }

    public func validated(requireHost: Bool) throws {
        let destination = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if destination.isEmpty {
            if requireHost { throw PatchError.missingHost }
        } else {
            guard Self.isUnicastIPv4(destination) else { throw PatchError.invalidHost }
        }
        guard ArtNet.portAddresses.contains(universe) else { throw PatchError.invalidUniverse }
        guard (0...16).contains(midiChannel) else { throw PatchError.invalidMIDIChannel }
        guard (0...119).contains(masterCC) else { throw PatchError.invalidMasterCC }

        var occupiedSlots = [Int: String]()
        var assignedNotes = [Int: String]()
        for fixture in fixtures {
            let profile = fixture.profile
            guard (1...profile.maximumStartAddress).contains(fixture.address) else {
                throw PatchError.invalidAddress(fixture.name, profile.maximumStartAddress, profile.slotCount)
            }
            guard Int(fixture.note) <= fixture.maximumBaseNote else {
                throw PatchError.invalidNote(fixture.name, fixture.maximumBaseNote, fixture.noteCount)
            }
            guard fixture.enabled else { continue }

            for slot in fixture.address..<(fixture.address + profile.slotCount) {
                if let name = occupiedSlots[slot] {
                    throw PatchError.overlappingAddress(fixture.name, name, slot)
                }
                occupiedSlots[slot] = fixture.name
            }
            for note in fixture.noteRange {
                if let name = assignedNotes[note] {
                    throw PatchError.overlappingNote(fixture.name, name, note)
                }
                assignedNotes[note] = fixture.name
            }
        }
    }

    private static func isUnicastIPv4(_ value: String) -> Bool {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else { return false }
        let octets = components.compactMap { component -> UInt8? in
            guard (1...3).contains(component.utf8.count),
                  component.utf8.allSatisfy({ (48...57).contains($0) }),
                  component.count == 1 || component.first != "0" else { return nil }
            return UInt8(component)
        }
        return octets.count == 4 && (1...223).contains(octets[0])
    }
}

public enum PatchError: LocalizedError, Equatable {
    case missingHost
    case invalidHost
    case invalidUniverse
    case invalidMIDIChannel
    case invalidMasterCC
    case invalidAddress(String, Int, Int)
    case invalidNote(String, Int, Int)
    case overlappingAddress(String, String, Int)
    case overlappingNote(String, String, Int)

    public var code: String {
        switch self {
        case .missingHost: "AX1-201"
        case .invalidHost: "AX1-202"
        case .invalidUniverse: "AX1-203"
        case .invalidMIDIChannel: "AX1-204"
        case .invalidMasterCC: "AX1-205"
        case .invalidAddress: "AX1-206"
        case .invalidNote: "AX1-207"
        case .overlappingAddress: "AX1-208"
        case .overlappingNote: "AX1-209"
        }
    }

    public var errorDescription: String? {
        let message: String
        switch self {
        case .missingHost:
            message = "Enter the Art-Net node’s IPv4 address."
        case .invalidHost:
            message = "Enter a unicast IPv4 address for the Art-Net node."
        case .invalidUniverse:
            message = "Enter an Art-Net universe from 0 to 32767."
        case .invalidMIDIChannel:
            message = "Choose Omni or a MIDI channel from 1 to 16."
        case .invalidMasterCC:
            message = "Enter a master MIDI CC number from 0 to 119."
        case let .invalidAddress(fixture, maximum, width):
            message = "\(fixture) needs a start address from 1 to \(maximum) to fit its \(width) DMX channels."
        case let .invalidNote(fixture, maximum, count):
            message = count == 1
                ? "\(fixture) needs a MIDI note number from 0 to 127."
                : "\(fixture) needs a starting note from 0 to \(maximum) to fit its \(count) MIDI notes."
        case let .overlappingAddress(fixture, other, slot):
            message = "DMX channel \(slot) is assigned to both \(fixture) and \(other)."
        case let .overlappingNote(fixture, other, note):
            message = "MIDI note \(note) is assigned to both \(fixture) and \(other)."
        }
        return "\(code) · \(message)"
    }
}
