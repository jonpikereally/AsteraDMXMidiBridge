import Foundation

/// A named set of fixtures with its own maximum brightness. A fixture can be in several groups;
/// its output is scaled by its own maximum and by every group it is in.
///
/// A group can also fix its lights' colour to a white of a set warmth. Those lights then ignore looks
/// and take only brightness from MIDI, such as a front wash.
///
/// A group can keep its lights on while Ableton is stopped (no MIDI clock): they sit at `stoppedLevel` or above
/// until clock starts again, then MIDI alone sets their level.
public struct FixtureGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var fixtureIDs: [UUID]
    /// Maximum brightness, 0–100 percent.
    public var maxLevel: UInt8
    /// Colour temperature in kelvin (2700–6500) when the group fixes its lights' colour; nil when it doesn't.
    public var warmth: Int?
    /// Brightness (0–100 percent) the group's lights stay at least at while Ableton is stopped; nil for none.
    public var stoppedLevel: UInt8?
    /// Where a group starts when you turn the stopped level on.
    public static let defaultStoppedLevel: UInt8 = 50

    public static let warmthRange = 2700...6500
    /// Where a group starts when you turn fixed warmth on.
    public static let defaultWarmth = 4300

    public static func clampedWarmth(_ kelvin: Int) -> Int {
        min(max(kelvin, warmthRange.lowerBound), warmthRange.upperBound)
    }

    public init(id: UUID = UUID(), name: String, fixtureIDs: [UUID] = [], maxLevel: UInt8 = 100, warmth: Int? = nil,
                stoppedLevel: UInt8? = nil) {
        self.id = id
        self.name = name
        self.fixtureIDs = fixtureIDs
        self.maxLevel = min(maxLevel, 100)
        self.warmth = warmth.map(Self.clampedWarmth)
        self.stoppedLevel = stoppedLevel.map { min($0, 100) }
    }

    private enum CodingKeys: String, CodingKey { case id, name, fixtureIDs, maxLevel, warmth, stoppedLevel }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            name: try values.decode(String.self, forKey: .name),
            fixtureIDs: try values.decodeIfPresent([UUID].self, forKey: .fixtureIDs) ?? [],
            maxLevel: min(try values.decodeIfPresent(UInt8.self, forKey: .maxLevel) ?? 100, 100),
            warmth: try values.decodeIfPresent(Int.self, forKey: .warmth),
            stoppedLevel: try values.decodeIfPresent(UInt8.self, forKey: .stoppedLevel)
        )
    }
}

public extension RGB {
    /// An approximate RGB white for a colour temperature, from Tanner Helland's fit to the blackbody curve.
    /// The tube mixes it from its red, green and blue, so the kelvin value is only a guide.
    init(kelvin: Int) {
        let t = Double(min(max(kelvin, 1000), 40000)) / 100
        let red = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let green = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let blue = t >= 66 ? 255 : t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307
        func byte(_ value: Double) -> UInt8 { UInt8(min(255, max(0, value)).rounded()) }
        self.init(byte(red), byte(green), byte(blue))
    }
}
