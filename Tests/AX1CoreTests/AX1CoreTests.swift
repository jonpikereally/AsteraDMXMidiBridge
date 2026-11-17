import Foundation
import XCTest
import AX1Core

final class AX1CoreTests: XCTestCase {
    func testArtDmxUsesProtocolByteOrderAndNoStartCodeByte() throws {
        var slots = [UInt8](repeating: 0, count: 512)
        slots[0] = 24
        slots[511] = 90
        let data = try XCTUnwrap(ArtNet.dmx(universe: 0x72B4, sequence: 18, slots: slots))

        XCTAssertEqual(data.count, 530)
        XCTAssertEqual(Array(data.prefix(18)), [65, 114, 116, 45, 78, 101, 116, 0, 0, 80, 0, 14, 18, 0, 180, 114, 2, 0])
        XCTAssertEqual(Array(data.dropFirst(18)), slots)
        XCTAssertNil(ArtNet.dmx(universe: 32768, sequence: 1, slots: slots))
        XCTAssertNil(ArtNet.dmx(universe: 0, sequence: 1, slots: [0, 0, 0]))
    }

    func testPatchUsesWidthsAndNoteRangesForOverlapChecks() throws {
        var config = BridgeConfig.defaults
        config.host = "127.0.0.1"
        config.fixtures[0].profile = .rgb16
        config.fixtures[0].independentPixels = true

        XCTAssertThrowsError(try config.validated()) { error in
            XCTAssertEqual(error as? PatchError, .overlappingAddress("AX1 2", "AX1 1", 4))
        }
        config.fixtures = Array(config.fixtures.prefix(2))
        config.fixtures[1].address = 49
        XCTAssertThrowsError(try config.validated()) { error in
            XCTAssertEqual(error as? PatchError, .overlappingNote("AX1 2", "AX1 1", 37))
        }
        config.fixtures[1].note = 52
        XCTAssertNoThrow(try config.validated())

        config.fixtures[0].address = 466
        XCTAssertThrowsError(try config.validated()) { error in
            XCTAssertEqual((error as? PatchError)?.code, "AX1-206")
        }
        config.fixtures[0].address = 465
        config.fixtures[0].note = 113
        XCTAssertThrowsError(try config.validated()) { error in
            XCTAssertEqual((error as? PatchError)?.code, "AX1-207")
        }
        config.fixtures[0].note = 112
        XCTAssertNoThrow(try config.validated())
    }

    func testPreviewMayOmitDestinationAndLiveOutputNeedsUnicastIPv4() throws {
        var config = BridgeConfig.defaults
        XCTAssertNoThrow(try config.validated(requireHost: false))
        XCTAssertThrowsError(try config.validated()) { error in
            XCTAssertEqual(error as? PatchError, .missingHost)
        }
        for host in ["0.0.0.0", "255.255.255.255", "224.20.1.8", "192.168.1.256", "192.168.0.001", "localhost"] {
            config.host = host
            XCTAssertThrowsError(try config.validated(), host) { error in
                XCTAssertEqual(error as? PatchError, .invalidHost)
            }
        }
        config.host = " 192.168.4.52 "
        XCTAssertNoThrow(try config.validated())
    }

    func testMIDIChannelsCanHoldSameNoteIndependentlyAndCCReleasesOnlyItsChannel() {
        let config = BridgeConfig.defaults
        let note = config.fixtures[0].note
        var engine = LightingEngine()
        engine.noteOn(note, velocity: 41, channel: 0)
        engine.noteOn(note, velocity: 64, channel: 6)
        engine.noteOn(note, velocity: 127, channel: 9)
        XCTAssertEqual(engine.levels[note], 127)

        engine.noteOn(note, velocity: 0, channel: 9)
        XCTAssertEqual(engine.levels[note], 64)
        engine.controlChange(123, value: 0, config: config, channel: 6)
        XCTAssertEqual(engine.levels[note], 41)
        engine.noteOff(note, channel: 0)
        XCTAssertNil(engine.levels[note])
    }

    func testRGBAndDimmerProfilesPutVelocityAndMasterOnTheRightChannels() {
        let color = RGB(255, 64, 128)
        var config = BridgeConfig.defaults
        config.fixtures = [
            FixturePatch(name: "RGB", address: 1, note: 60, color: color),
            FixturePatch(name: "RGBW", address: 4, note: 61, color: color, profile: .rgbw, white: 200),
            FixturePatch(name: "DIM RGB", address: 8, note: 62, color: color, profile: .dimRGB),
            FixturePatch(name: "DIM RGBW", address: 12, note: 63, color: color, profile: .dimRGBW, white: 200),
        ]
        var engine = LightingEngine()
        for note in UInt8(60)...63 { engine.noteOn(note, velocity: 64) }
        engine.controlChange(7, value: 64, config: config, channel: 1)

        let frame = engine.frame(config: config)
        XCTAssertEqual(Array(frame.prefix(16)), [65, 16, 33, 65, 16, 33, 51, 65, 255, 64, 128, 65, 255, 64, 128, 200])
        XCTAssertTrue(frame.dropFirst(16).allSatisfy { $0 == 0 })

        engine.setBlackout(true)
        XCTAssertTrue(engine.frame(config: config).allSatisfy { $0 == 0 })
        engine.setBlackout(false)
        engine.controlChange(120, value: 0, config: config)
        XCTAssertTrue(engine.frame(config: config).allSatisfy { $0 == 0 })
    }

    func testPixelModeCanMirrorTubeOrAddressTheLastPixelIndependently() {
        var config = BridgeConfig.defaults
        config.fixtures = [FixturePatch(name: "Tube", address: 465, note: 112, color: RGB(255, 150, 20), profile: .rgb16)]
        var engine = LightingEngine()
        engine.noteOn(112, velocity: 127)
        var frame = engine.frame(config: config)
        XCTAssertEqual(Array(frame.suffix(48)), Array(repeating: [UInt8(255), 150, 20], count: 16).flatMap { $0 })

        engine.noteOff(112)
        config.fixtures[0].independentPixels = true
        engine.noteOn(127, velocity: 127)
        frame = engine.frame(config: config)
        XCTAssertTrue(frame.dropLast(3).allSatisfy { $0 == 0 })
        XCTAssertEqual(Array(frame.suffix(3)), [255, 150, 20])
    }

    func testLegacyPatchCanStillBeRead() throws {
        let fixture = BridgeConfig.defaults.fixtures[0]
        let encoded = try JSONEncoder().encode(fixture)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "profile")
        legacy.removeValue(forKey: "white")
        legacy.removeValue(forKey: "independentPixels")
        let decoded = try JSONDecoder().decode(FixturePatch.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(fixture, decoded)
    }

    func testEffectModeRGBFollowsAsteraProfile16ChannelMap() throws {
        var config = BridgeConfig.defaults
        config.fixtures = [FixturePatch(
            name: "FX", address: 10, note: 60, color: RGB(1, 2, 3), profile: .effectRGB,
            effect: EffectSettings(
                strobe: 5, program: 118, speed: 200, crossfade: 40, direction: 191, size: 64, offset: 17, restart: 9,
                colors: [RGB(4, 5, 6), RGB(7, 8, 9), RGB(10, 11, 12)]
            )
        )]
        XCTAssertEqual(AX1Profile.effectRGB.slotCount, 21)
        XCTAssertEqual(AX1Profile.effectRGB.maximumStartAddress, 492)
        XCTAssertNoThrow(try config.validated(requireHost: false))

        var engine = LightingEngine()
        let settings: [UInt8] = [5, 118, 200, 40, 191, 64, 17, 9, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
        // Released: dimmer closed, but the program settings keep flowing.
        var frame = engine.frame(config: config)
        XCTAssertEqual(frame[9], 0)
        XCTAssertEqual(Array(frame[10..<30]), settings)
        XCTAssertEqual(frame[30], 0)
        XCTAssertEqual(frame[8], 0)

        engine.noteOn(60, velocity: 127, channel: 1)
        frame = engine.frame(config: config)
        XCTAssertEqual(frame[9], 255)
        XCTAssertEqual(Array(frame[10..<30]), settings)

        engine.setMaster(0)
        XCTAssertEqual(engine.frame(config: config), [UInt8](repeating: 0, count: 512))
    }

    func testEffectOptionsMatchDocumentedRanges() {
        XCTAssertEqual(EffectSettings.programs.count, 20)
        XCTAssertEqual(EffectOption.matching(101, in: EffectSettings.programs)?.name, "Double Flag Running")
        XCTAssertEqual(EffectOption.matching(157, in: EffectSettings.programs)?.name, "Rotor Split 4")
        XCTAssertNil(EffectOption.matching(158, in: EffectSettings.programs))
        XCTAssertEqual(EffectOption.matching(3, in: EffectSettings.strobeModes)?.name, "Off")
        XCTAssertEqual(EffectOption.matching(90, in: EffectSettings.strobeModes)?.name, "Variable")
        XCTAssertEqual(EffectOption.matching(190, in: EffectSettings.directions)?.name, "Reverse once")
        XCTAssertEqual(EffectOption.matching(191, in: EffectSettings.sizes)?.name, "4 groups")
    }

    func testSavedPatchesWithoutEffectSettingsStillLoad() throws {
        let legacy = """
        {"id":"6B1F5A3E-2C1D-4F7A-9E55-1B0C7D9A2F11","name":"AX1 1","address":1,"note":36,
         "color":{"r":255,"g":0,"b":0},"enabled":true,"profile":1,"white":0,"independentPixels":false}
        """
        let fixture = try JSONDecoder().decode(FixturePatch.self, from: Data(legacy.utf8))
        XCTAssertEqual(fixture.effect, EffectSettings())
        XCTAssertEqual(fixture.effect.colors.count, 3)
    }

    func testPatchFileRoundTripsAndKeepsDestination() throws {
        var source = BridgeConfig.defaults
        source.midiChannel = 4
        source.masterCC = 11
        source.fixtures[0].profile = .effectRGB
        source.fixtures[0].effect.program = 126
        source.fixtures = Array(source.fixtures.prefix(1))
        source.host = "10.0.0.9"

        let data = try PatchFile.export(source)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("10.0.0.9"))

        var target = BridgeConfig.defaults
        target.host = "127.0.0.1"
        target.universe = 3
        let imported = try PatchFile.load(data, into: target)
        XCTAssertEqual(imported.fixtures, source.fixtures)
        XCTAssertEqual(imported.midiChannel, 4)
        XCTAssertEqual(imported.masterCC, 11)
        XCTAssertEqual(imported.host, "127.0.0.1")
        XCTAssertEqual(imported.universe, 3)
    }

    func testPatchFileImportRejectsBadFilesWithCodes() throws {
        let base = BridgeConfig.defaults
        XCTAssertThrowsError(try PatchFile.load(Data("not json".utf8), into: base)) {
            XCTAssertEqual(($0 as? PatchFileError)?.code, "AX1-210")
        }
        XCTAssertThrowsError(try PatchFile.load(Data(#"{"format":"other","version":1}"#.utf8), into: base)) {
            XCTAssertEqual(($0 as? PatchFileError)?.code, "AX1-211")
        }
        XCTAssertThrowsError(try PatchFile.load(Data(#"{"format":"AsteraDMXMidiBridge.patch","version":99}"#.utf8), into: base)) {
            XCTAssertEqual(($0 as? PatchFileError)?.code, "AX1-212")
        }

        var overlapping = base
        overlapping.fixtures[1].address = 2
        let data = try PatchFile.export(overlapping)
        XCTAssertThrowsError(try PatchFile.load(data, into: base)) {
            XCTAssertEqual(($0 as? PatchError)?.code, "AX1-208")
        }
    }
}
