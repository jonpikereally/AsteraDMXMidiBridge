import Foundation

/// A preset that MIDI can switch to. Playing the look's note gives every fixture that follows
/// looks this colour and these Effect Mode settings, until another look note arrives.
/// The note only switches the look; the dimmer still follows each fixture's note or level CC.
public struct Look: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var note: UInt8
    /// Colour 1, or the fixture colour for the RGB profiles.
    public var color: RGB
    /// Used by Effect Mode fixtures. Colours 2–4 are in `effect.colors`.
    public var effect: EffectSettings

    public init(id: UUID = UUID(), name: String, note: UInt8, color: RGB, effect: EffectSettings = EffectSettings()) {
        self.id = id
        self.name = name
        self.note = note
        self.color = color
        self.effect = effect
    }
}
