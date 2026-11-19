import Foundation

/// A preset that MIDI can switch to. Playing the look's note gives every fixture that follows
/// looks this colour and these Effect Mode settings, until another look note arrives.
/// The note only switches the look; the dimmer still follows each fixture's note or level CC.
///
/// A flash look shows only while its note is held. When the note ends, the fixtures go back to the
/// look before it.
public struct Look: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var note: UInt8
    /// Colour 1, or the fixture colour for the RGB profiles.
    public var color: RGB
    /// Used by Effect Mode fixtures. Colours 2–4 are in `effect.colors`.
    public var effect: EffectSettings
    /// Shows only while the note is held, then the previous look returns.
    public var flash: Bool
    /// Moves the light across the look's fixtures (a chase, or one brighter than the others). Nil means no movement.
    public var motion: LookMotion?
    /// Movement only: the look adds its motion but keeps the colour and effect of the look under it.
    public var motionOnly: Bool

    public init(id: UUID = UUID(), name: String, note: UInt8, color: RGB, effect: EffectSettings = EffectSettings(), flash: Bool = false,
                motion: LookMotion? = nil, motionOnly: Bool = false) {
        self.id = id
        self.name = name
        self.note = note
        self.color = color
        self.effect = effect
        self.flash = flash
        self.motion = motion
        self.motionOnly = motionOnly
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, note, color, effect, flash, motion, motionOnly
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            name: try values.decode(String.self, forKey: .name),
            note: try values.decode(UInt8.self, forKey: .note),
            color: try values.decode(RGB.self, forKey: .color),
            effect: try values.decode(EffectSettings.self, forKey: .effect),
            flash: try values.decodeIfPresent(Bool.self, forKey: .flash) ?? false,
            motion: try values.decodeIfPresent(LookMotion.self, forKey: .motion),
            motionOnly: try values.decodeIfPresent(Bool.self, forKey: .motionOnly) ?? false
        )
    }
}
