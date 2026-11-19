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

    public func scaled(velocity: UInt8, master: UInt8, limit: Double) -> RGB {
        RGB(
            Self.scaledComponent(r, velocity: velocity, master: master, limit: limit),
            Self.scaledComponent(g, velocity: velocity, master: master, limit: limit),
            Self.scaledComponent(b, velocity: velocity, master: master, limit: limit)
        )
    }

    /// `limit` (0–1) is the fixture's maximum brightness after its groups.
    static func scaledComponent(_ component: UInt8, velocity: UInt8, master: UInt8, limit: Double = 1) -> UInt8 {
        let gain = Double(min(velocity, 127)) * Double(min(master, 127)) * min(1, max(0, limit))
        let full = 127 * 127
        return UInt8(min(255, ((Double(component) * gain + Double(full / 2)) / Double(full)).rounded(.down)))
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
    /// When on, a look note replaces this fixture's colour and effect settings.
    public var followsLooks: Bool
    /// A MIDI CC (0–119) that sets this fixture's level, or nil for notes only.
    /// The dimmer uses whichever is higher: the held note's velocity or the CC value.
    public var levelCC: Int?
    /// Maximum brightness, 0–100 percent. Scales everything this fixture outputs.
    public var maxLevel: UInt8

    public var noteCount: Int { independentPixels ? profile.pixelCount : 1 }
    public var maximumBaseNote: Int { 128 - noteCount }
    public var noteRange: ClosedRange<Int> { Int(note)...(Int(note) + noteCount - 1) }

    public init(
        id: UUID = UUID(), name: String, address: Int, note: UInt8, color: RGB, enabled: Bool = true,
        profile: AX1Profile = .rgb, white: UInt8 = 0, independentPixels: Bool = false,
        effect: EffectSettings = EffectSettings(), followsLooks: Bool = true, levelCC: Int? = nil, maxLevel: UInt8 = 100
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
        self.followsLooks = followsLooks
        self.levelCC = levelCC
        self.maxLevel = min(maxLevel, 100)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, address, note, color, enabled, profile, white, independentPixels, effect, followsLooks, levelCC, maxLevel
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
            effect: try values.decodeIfPresent(EffectSettings.self, forKey: .effect) ?? EffectSettings(),
            followsLooks: try values.decodeIfPresent(Bool.self, forKey: .followsLooks) ?? true,
            levelCC: try values.decodeIfPresent(Int.self, forKey: .levelCC),
            maxLevel: min(try values.decodeIfPresent(UInt8.self, forKey: .maxLevel) ?? 100, 100)
        )
    }
}

public struct BridgeConfig: Codable, Equatable, Sendable {
    public var host: String
    public var universe: Int
    public var midiChannel: Int
    public var masterCC: Int
    public var fixtures: [FixturePatch]
    public var looks: [Look]
    public var groups: [FixtureGroup]

    public init(host: String, universe: Int, midiChannel: Int, masterCC: Int, fixtures: [FixturePatch], looks: [Look] = [],
                groups: [FixtureGroup] = []) {
        self.host = host
        self.universe = universe
        self.midiChannel = midiChannel
        self.masterCC = masterCC
        self.fixtures = fixtures
        self.looks = looks
        self.groups = groups
    }

    private enum CodingKeys: String, CodingKey {
        case host, universe, midiChannel, masterCC, fixtures, looks, groups
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            host: try values.decode(String.self, forKey: .host),
            universe: try values.decode(Int.self, forKey: .universe),
            midiChannel: try values.decode(Int.self, forKey: .midiChannel),
            masterCC: try values.decode(Int.self, forKey: .masterCC),
            fixtures: try values.decode([FixturePatch].self, forKey: .fixtures),
            looks: try values.decodeIfPresent([Look].self, forKey: .looks) ?? [],
            groups: try values.decodeIfPresent([FixtureGroup].self, forKey: .groups) ?? []
        )
    }

    /// A fixture's maximum brightness (0–1): its own maximum times that of every group it is in.
    public func limit(of fixture: FixturePatch) -> Double {
        groups.filter { $0.fixtureIDs.contains(fixture.id) }
            .reduce(Double(fixture.maxLevel) / 100) { $0 * Double($1.maxLevel) / 100 }
    }

    /// The fixed warmth (kelvin) for a fixture: from the first group that contains it and fixes warmth, if any.
    public func warmth(of fixture: FixturePatch) -> Int? {
        groups.first { $0.warmth != nil && $0.fixtureIDs.contains(fixture.id) }?.warmth
    }

    /// The look a note switches to, if any.
    public func look(forNote note: UInt8) -> Look? {
        looks.first { $0.note == note }
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
            if let cc = fixture.levelCC {
                guard (0...119).contains(cc), cc != masterCC else {
                    throw PatchError.invalidLevelCC(fixture.name, masterCC)
                }
            }
        }
        for look in looks {
            guard look.note <= 127 else { throw PatchError.invalidNote(look.name, 127, 1) }
            if let name = assignedNotes[Int(look.note)] {
                throw PatchError.overlappingLookNote(look.name, name, Int(look.note))
            }
            assignedNotes[Int(look.note)] = look.name
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
    case invalidLevelCC(String, Int)
    case overlappingLookNote(String, String, Int)

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
        case .invalidLevelCC: "AX1-214"
        case .overlappingLookNote: "AX1-215"
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
        case let .invalidLevelCC(fixture, master):
            message = "\(fixture) needs a level CC from 0 to 119 that isn’t the master CC (\(master))."
        case let .overlappingLookNote(look, other, note):
            message = "Look \(look) uses MIDI note \(note), which is already assigned to \(other)."
        }
        return "\(code) · \(message)"
    }
}
