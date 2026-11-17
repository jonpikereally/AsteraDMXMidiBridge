public enum AX1Profile: Int, Codable, CaseIterable, Identifiable, Sendable {
    case rgb = 1
    case rgbw = 2
    case dimRGB = 4
    case dimRGBW = 5
    case rgb16 = 42

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .rgb: "RGB"
        case .rgbw: "RGBW"
        case .dimRGB: "DIM RGB"
        case .dimRGBW: "DIM RGBW"
        case .rgb16: "RGB RGB (16 pixels)"
        }
    }

    public var pixelCount: Int { self == .rgb16 ? 16 : 1 }
    public var hasDimmer: Bool { self == .dimRGB || self == .dimRGBW }
    public var hasWhite: Bool { self == .rgbw || self == .dimRGBW }
    public var slotCount: Int { pixelCount * slotsPerPixel }
    public var maximumStartAddress: Int { 513 - slotCount }

    var slotsPerPixel: Int { 3 + (hasDimmer ? 1 : 0) + (hasWhite ? 1 : 0) }
}
