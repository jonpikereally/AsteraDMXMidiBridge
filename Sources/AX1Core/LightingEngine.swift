import Foundation

public struct LightingEngine: Sendable {
    private var heldNotes: [Int: [UInt8: UInt8]] = [:]
    public private(set) var master: UInt8 = 127
    public private(set) var blackout = false
    /// The look chosen by the last look note that isn't a flash. Nil means each fixture uses its own patch settings.
    public private(set) var baseLook: UUID?
    /// Flash looks whose notes are held, oldest first.
    public private(set) var heldFlashes: [UUID] = []
    /// The newest held flash, otherwise the base look.
    public var activeLook: UUID? { heldFlashes.last ?? baseLook }

    /// The look whose colour and effect show: the newest held flash that isn't movement-only, otherwise the base look.
    public func colourLook(_ config: BridgeConfig) -> Look? {
        for id in ([baseLook].compactMap { $0 } + heldFlashes).reversed() {
            if let look = config.looks.first(where: { $0.id == id }), !look.motionOnly { return look }
        }
        return nil
    }

    /// The motion that shows: from the newest held flash that has one, otherwise from the base look.
    public func activeMotion(_ config: BridgeConfig) -> LookMotion? {
        for id in ([baseLook].compactMap { $0 } + heldFlashes).reversed() {
            if let motion = config.looks.first(where: { $0.id == id })?.motion { return motion }
        }
        return nil
    }
    /// The last value of each level CC (not the master CC).
    public private(set) var ccLevels: [UInt8: UInt8] = [:]
    /// Where the showing look's motion is, in beats. The app sets it from MIDI clock, or from its own timer
    /// at the look's tempo when there is no clock.
    public private(set) var beats: Double = 0

    public init() {}

    public mutating func setBeats(_ value: Double) {
        beats = max(0, value)
    }

    /// The fixtures a look's motion moves across, in patch order.
    public static func motionFixtures(_ config: BridgeConfig) -> [FixturePatch] {
        config.fixtures.filter { $0.enabled && $0.followsLooks && config.warmth(of: $0) == nil }
    }

    /// How much the showing look's motion lets this fixture through now (0–1). 1 when there is no motion.
    public func motionFactor(of fixture: FixturePatch, config: BridgeConfig) -> Double {
        guard fixture.followsLooks, config.warmth(of: fixture) == nil, let motion = activeMotion(config) else { return 1 }
        let movers = Self.motionFixtures(config)
        guard let index = movers.firstIndex(where: { $0.id == fixture.id }) else { return 1 }
        return motion.factor(index: index, count: movers.count, beats: beats)
    }

    private static func scaled(_ level: UInt8, by factor: Double) -> UInt8 {
        factor >= 1 ? level : UInt8(clamping: Int((Double(level) * max(0, factor)).rounded()))
    }

    public var levels: [UInt8: UInt8] {
        var combined = [UInt8: UInt8]()
        for notes in heldNotes.values {
            for (note, velocity) in notes {
                combined[note] = max(velocity, combined[note, default: 0])
            }
        }
        return combined
    }

    public mutating func noteOn(_ note: UInt8, velocity: UInt8, channel: Int = 1) {
        // Channel 0 is reserved for the app's test pads, independent of the selected MIDI input.
        guard note <= 127, (0...16).contains(channel) else { return }
        if velocity == 0 {
            noteOff(note, channel: channel)
        } else {
            heldNotes[channel, default: [:]][note] = min(velocity, 127)
        }
    }

    public mutating func noteOff(_ note: UInt8, channel: Int = 1) {
        heldNotes[channel]?[note] = nil
    }

    public mutating func controlChange(_ control: UInt8, value: UInt8, config: BridgeConfig, channel: Int? = nil) {
        switch control {
        case 120, 123:
            if let channel {
                heldNotes[channel] = nil
            } else {
                heldNotes.removeAll()
            }
            ccLevels.removeAll()
            heldFlashes.removeAll()
        case UInt8(clamping: config.masterCC) where (0...119).contains(config.masterCC):
            setMaster(value)
        case 0...119:
            ccLevels[control] = min(value, 127)
        default:
            break
        }
    }

    /// Switches every fixture that follows looks to this look. Nil returns them to their patch settings.
    /// A held flash still shows on top until it's released.
    public mutating func selectLook(_ id: UUID?) {
        baseLook = id
    }

    /// Shows a flash look while its note is held.
    public mutating func holdFlash(_ id: UUID) {
        heldFlashes.removeAll { $0 == id }
        heldFlashes.append(id)
    }

    /// Ends a flash. The look under it shows again.
    public mutating func releaseFlash(_ id: UUID) {
        heldFlashes.removeAll { $0 == id }
    }

    /// The dimmer level (0–127, before the master) for a fixture: its held note velocity or its level CC, whichever is higher.
    /// For Note per pixel, `pixel` picks the note.
    public func level(of fixture: FixturePatch, pixel: Int = 0, notes: [UInt8: UInt8]? = nil) -> UInt8 {
        let active = notes ?? levels
        let note = UInt8(clamping: Int(fixture.note) + (fixture.independentPixels ? pixel : 0))
        let cc = fixture.levelCC.flatMap { ccLevels[UInt8(clamping: $0)] } ?? 0
        return max(active[note] ?? 0, cc)
    }

    /// The colour and effect settings a fixture is showing now. A group with fixed warmth wins over looks and the
    /// fixture's own colour: a steady white at that warmth.
    public func appearance(of fixture: FixturePatch, config: BridgeConfig) -> (color: RGB, effect: EffectSettings) {
        if let kelvin = config.warmth(of: fixture) {
            let white = RGB(kelvin: kelvin)
            return (white, EffectSettings(colors: [white, white, white]))
        }
        if fixture.followsLooks, let look = colourLook(config) {
            return (look.color, look.effect)
        }
        return (fixture.color, fixture.effect)
    }

    public mutating func setMaster(_ value: UInt8) {
        master = min(value, 127)
    }

    public mutating func setBlackout(_ flag: Bool) {
        blackout = flag
    }

    /// Releases held notes and flashes and resets level CCs to 0. The base look stays.
    public mutating func clearNotes() {
        heldNotes.removeAll()
        ccLevels.removeAll()
        heldFlashes.removeAll()
    }

    public func frame(config: BridgeConfig) -> [UInt8] {
        var slots = [UInt8](repeating: 0, count: 512)
        guard !blackout, master > 0 else { return slots }

        let active = levels
        for fixture in config.fixtures where fixture.enabled {
            let profile = fixture.profile
            guard (1...profile.maximumStartAddress).contains(fixture.address),
                  Int(fixture.note) <= fixture.maximumBaseNote else { continue }

            let look = appearance(of: fixture, config: config)
            let limit = config.limit(of: fixture)
            let motion = motionFactor(of: fixture, config: config)
            if profile.isEffect {
                // Effect settings are sent continuously so the program keeps running;
                // the note or level CC only opens the dimmer on channel 1.
                let start = fixture.address - 1
                let velocity = Self.scaled(level(of: fixture, notes: active), by: motion)
                slots[start] = velocity > 0 ? RGB.scaledComponent(255, velocity: velocity, master: master, limit: limit) : 0
                for (offset, value) in look.effect.slots(color1: look.color).enumerated() {
                    slots[start + 1 + offset] = value
                }
                continue
            }

            for pixel in 0..<profile.pixelCount {
                let velocity = Self.scaled(level(of: fixture, pixel: pixel, notes: active), by: motion)
                guard velocity > 0 else { continue }
                var slot = fixture.address - 1 + pixel * profile.slotsPerPixel
                if profile.hasDimmer {
                    slots[slot] = RGB.scaledComponent(255, velocity: velocity, master: master, limit: limit)
                    slot += 1
                }
                let color = profile.hasDimmer ? look.color : look.color.scaled(velocity: velocity, master: master, limit: limit)
                slots[slot] = color.r
                slots[slot + 1] = color.g
                slots[slot + 2] = color.b
                if profile.hasWhite {
                    slots[slot + 3] = profile.hasDimmer
                        ? fixture.white
                        : RGB.scaledComponent(fixture.white, velocity: velocity, master: master, limit: limit)
                }
            }
        }
        return slots
    }
}
