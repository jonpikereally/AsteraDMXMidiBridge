public struct LightingEngine: Sendable {
    private var heldNotes: [Int: [UInt8: UInt8]] = [:]
    public private(set) var master: UInt8 = 127
    public private(set) var blackout = false

    public init() {}

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
                clearNotes()
            }
        case UInt8(clamping: config.masterCC) where (0...119).contains(config.masterCC):
            setMaster(value)
        default:
            break
        }
    }

    public mutating func setMaster(_ value: UInt8) {
        master = min(value, 127)
    }

    public mutating func setBlackout(_ flag: Bool) {
        blackout = flag
    }

    public mutating func clearNotes() {
        heldNotes.removeAll()
    }

    public func frame(config: BridgeConfig) -> [UInt8] {
        var slots = [UInt8](repeating: 0, count: 512)
        guard !blackout, master > 0 else { return slots }

        let active = levels
        for fixture in config.fixtures where fixture.enabled {
            let profile = fixture.profile
            guard (1...profile.maximumStartAddress).contains(fixture.address),
                  Int(fixture.note) <= fixture.maximumBaseNote else { continue }

            if profile.isEffect {
                // Effect settings are sent continuously so the program keeps running;
                // the note only opens the dimmer on channel 1.
                let start = fixture.address - 1
                let velocity = active[fixture.note] ?? 0
                slots[start] = velocity > 0 ? RGB.scaledComponent(255, velocity: velocity, master: master) : 0
                for (offset, value) in fixture.effect.slots(color1: fixture.color).enumerated() {
                    slots[start + 1 + offset] = value
                }
                continue
            }

            for pixel in 0..<profile.pixelCount {
                let note = fixture.independentPixels ? fixture.note + UInt8(pixel) : fixture.note
                guard let velocity = active[note] else { continue }
                var slot = fixture.address - 1 + pixel * profile.slotsPerPixel
                if profile.hasDimmer {
                    slots[slot] = RGB.scaledComponent(255, velocity: velocity, master: master)
                    slot += 1
                }
                let color = profile.hasDimmer ? fixture.color : fixture.color.scaled(velocity: velocity, master: master)
                slots[slot] = color.r
                slots[slot + 1] = color.g
                slots[slot + 2] = color.b
                if profile.hasWhite {
                    slots[slot + 3] = profile.hasDimmer
                        ? fixture.white
                        : RGB.scaledComponent(fixture.white, velocity: velocity, master: master)
                }
            }
        }
        return slots
    }
}
