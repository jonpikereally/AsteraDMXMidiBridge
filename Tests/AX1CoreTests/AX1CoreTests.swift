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
}
