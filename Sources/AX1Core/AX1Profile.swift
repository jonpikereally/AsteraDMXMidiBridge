public enum AX1Profile: Int, Codable, CaseIterable, Identifiable, Sendable {
    case rgb = 1
    case rgbw = 2
    case dimRGB = 4
    case dimRGBW = 5
    case effectRGB = 16
    case rgb16 = 42

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .rgb: "RGB"
        case .rgbw: "RGBW"
        case .dimRGB: "DIM RGB"
        case .dimRGBW: "DIM RGBW"
        case .effectRGB: "EFFECT MODE RGB"
        case .rgb16: "RGB RGB (16 pixels)"
        }
    }

    public var pixelCount: Int { self == .rgb16 ? 16 : 1 }
    public var hasDimmer: Bool { self == .dimRGB || self == .dimRGBW }
    public var hasWhite: Bool { self == .rgbw || self == .dimRGBW }
    /// Effect Mode profiles run Astera's built-in programs on the tube instead of direct pixel colour.
    public var isEffect: Bool { self == .effectRGB }
    public var slotCount: Int { pixelCount * slotsPerPixel }
    public var maximumStartAddress: Int { 513 - slotCount }

    var slotsPerPixel: Int {
        if self == .effectRGB { return EffectSettings.slotCount }
        return 3 + (hasDimmer ? 1 : 0) + (hasWhite ? 1 : 0)
    }
}

/// A named DMX range from Astera's AX1 profile sheet. `value` is the first value in the range,
/// which is what the app sends when the option is chosen.
public struct EffectOption: Identifiable, Equatable, Sendable {
    public let name: String
    public let range: ClosedRange<UInt8>
    public var value: UInt8 { range.lowerBound }
    public var id: UInt8 { value }

    init(_ name: String, _ range: ClosedRange<UInt8>) {
        self.name = name
        self.range = range
    }

    public static func matching(_ value: UInt8, in options: [EffectOption]) -> EffectOption? {
        options.first { $0.range.contains(value) }
    }
}

/// Channels 2–21 of Astera profile 16 "EFFECT MODE RGB" (AX1/AX1-BTB DMX Profiles V2, p. 278).
/// Channel 1, the dimmer, follows MIDI velocity and the master level.
public struct EffectSettings: Codable, Equatable, Sendable {
    public static let slotCount = 21
    /// Ch 2 values 7–255 are a variable strobe from 0.4 Hz to 25 Hz.
    public static let variableStrobe: ClosedRange<UInt8> = 7...255

    public static let strobeModes: [EffectOption] = [
        EffectOption("Off", 0...3),
        EffectOption("Random fast", 4...4),
        EffectOption("Random medium", 5...5),
        EffectOption("Random slow", 6...6),
        EffectOption("Variable", variableStrobe),
    ]

    public static let programs: [EffectOption] = [
        EffectOption("One Color Static", 0...7),
        EffectOption("Two Color Static", 8...15),
        EffectOption("Three Color Static", 16...23),
        EffectOption("Four Color Static", 24...31),
        EffectOption("One Color Fade", 32...39),
        EffectOption("Two Color Fade", 40...47),
        EffectOption("Three Color Fade", 48...55),
        EffectOption("Four Color Fade", 56...63),
        EffectOption("Simple Running", 64...71),
        EffectOption("Double Running", 72...79),
        EffectOption("Two Col Running", 80...87),
        EffectOption("Flag Running", 88...95),
        EffectOption("Double Flag Running", 96...101),
        EffectOption("Spiral 4 Color", 102...109),
        EffectOption("Spiral 2 Color", 110...117),
        EffectOption("Rainbow", 118...125),
        EffectOption("Fire", 126...133),
        EffectOption("Rotor", 134...141),
        EffectOption("Rotor Split 2", 142...149),
        EffectOption("Rotor Split 4", 150...157),
    ]

    public static let directions: [EffectOption] = [
        EffectOption("Forward, loop", 0...63),
        EffectOption("Forward once", 64...127),
        EffectOption("Reverse once", 128...190),
        EffectOption("Reverse, loop", 191...255),
    ]

    public static let sizes: [EffectOption] = [
        EffectOption("1 group", 0...63),
        EffectOption("2 groups", 64...127),
        EffectOption("3 groups", 128...190),
        EffectOption("4 groups", 191...255),
    ]

    public var strobe: UInt8
    public var program: UInt8
    public var speed: UInt8
    public var crossfade: UInt8
    public var direction: UInt8
    public var size: UInt8
    public var offset: UInt8
    public var restart: UInt8
    /// Colours 2–4. Colour 1 is the fixture's main colour.
    public var colors: [RGB]

    public static let defaultColors = [RGB(0, 120, 255), RGB(255, 0, 160), RGB(255, 200, 0)]

    public init(
        strobe: UInt8 = 0, program: UInt8 = 0, speed: UInt8 = 128, crossfade: UInt8 = 0,
        direction: UInt8 = 0, size: UInt8 = 0, offset: UInt8 = 0, restart: UInt8 = 0,
        colors: [RGB] = EffectSettings.defaultColors
    ) {
        self.strobe = strobe
        self.program = program
        self.speed = speed
        self.crossfade = crossfade
        self.direction = direction
        self.size = size
        self.offset = offset
        self.restart = restart
        self.colors = Self.normalized(colors)
    }

    private enum CodingKeys: String, CodingKey {
        case strobe, program, speed, crossfade, direction, size, offset, restart, colors
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = EffectSettings()
        self.init(
            strobe: try values.decodeIfPresent(UInt8.self, forKey: .strobe) ?? fallback.strobe,
            program: try values.decodeIfPresent(UInt8.self, forKey: .program) ?? fallback.program,
            speed: try values.decodeIfPresent(UInt8.self, forKey: .speed) ?? fallback.speed,
            crossfade: try values.decodeIfPresent(UInt8.self, forKey: .crossfade) ?? fallback.crossfade,
            direction: try values.decodeIfPresent(UInt8.self, forKey: .direction) ?? fallback.direction,
            size: try values.decodeIfPresent(UInt8.self, forKey: .size) ?? fallback.size,
            offset: try values.decodeIfPresent(UInt8.self, forKey: .offset) ?? fallback.offset,
            restart: try values.decodeIfPresent(UInt8.self, forKey: .restart) ?? fallback.restart,
            colors: try values.decodeIfPresent([RGB].self, forKey: .colors) ?? fallback.colors
        )
    }

    /// DMX values for channels 2–21, given colour 1.
    public func slots(color1: RGB) -> [UInt8] {
        var result = [strobe, program, speed, crossfade, direction, size, offset, restart]
        for color in [color1] + Self.normalized(colors) {
            result += [color.r, color.g, color.b]
        }
        return result
    }

    private static func normalized(_ colors: [RGB]) -> [RGB] {
        Array((colors + defaultColors.dropFirst(min(colors.count, defaultColors.count))).prefix(3))
    }
}
