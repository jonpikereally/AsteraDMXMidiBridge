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

    private func effectRig() -> BridgeConfig {
        var config = BridgeConfig.defaults
        config.fixtures = Array(config.fixtures.prefix(2))
        for i in config.fixtures.indices {
            config.fixtures[i].profile = .effectRGB
            config.fixtures[i].address = 1 + i * 21
        }
        config.fixtures[0].levelCC = 20
        config.fixtures[1].levelCC = 21
        config.fixtures[1].followsLooks = false
        config.looks = [Look(name: "Gold Big", note: 60, color: RGB(255, 153, 13),
                             effect: EffectSettings(program: 40, speed: 200, colors: [RGB(51, 31, 3), RGB(0, 0, 0), RGB(0, 0, 0)]))]
        return config
    }

    func testLevelCCDrivesTheDimmerAndLookNotesSwitchOnlyFollowers() throws {
        let config = effectRig()
        XCTAssertNoThrow(try config.validated(requireHost: false))
        var engine = LightingEngine()
        XCTAssertEqual(engine.frame(config: config)[0], 0)

        engine.controlChange(20, value: 127, config: config)
        engine.controlChange(21, value: 64, config: config)
        var frame = engine.frame(config: config)
        XCTAssertEqual(frame[0], 255)
        XCTAssertEqual(frame[21], 129)
        XCTAssertEqual(Array(frame[9...11]), [255, 73, 59])     // fixture colour before any look

        engine.selectLook(config.looks[0].id)
        frame = engine.frame(config: config)
        XCTAssertEqual(frame[2], 40)                              // program
        XCTAssertEqual(Array(frame[9...14]), [255, 153, 13, 51, 31, 3])
        XCTAssertEqual(Array(frame[30...32]), [255, 153, 42])    // the front fixture keeps its own colour
        XCTAssertEqual(frame[23], 0)

        // a held note above the CC wins; the master scales both
        engine.controlChange(20, value: 10, config: config)
        engine.noteOn(36, velocity: 127)
        XCTAssertEqual(engine.frame(config: config)[0], 255)
        engine.controlChange(7, value: 0, config: config)
        XCTAssertEqual(engine.frame(config: config)[0], 0)

        engine.controlChange(7, value: 127, config: config)
        engine.controlChange(123, value: 0, config: config)
        XCTAssertEqual(engine.frame(config: config)[0], 0)
        XCTAssertEqual(engine.activeLook, config.looks[0].id)    // all-notes-off keeps the look
    }

    func testFlashLooksShowOnlyWhileHeldThenTheLookUnderneathReturns() throws {
        var config = effectRig()
        let red = Look(name: "Red Flash", note: 96, color: RGB(255, 0, 0), flash: true)
        let blue = Look(name: "Blue Calm", note: 61, color: RGB(0, 0, 255))
        config.looks += [red, blue]
        XCTAssertNoThrow(try config.validated(requireHost: false))
        var engine = LightingEngine()
        func colour() -> [UInt8] { Array(engine.frame(config: config)[9...11]) }
        func front() -> [UInt8] { Array(engine.frame(config: config)[30...32]) }

        engine.selectLook(config.looks[0].id)                       // Gold Big underneath
        XCTAssertEqual(colour(), [255, 153, 13])
        engine.holdFlash(red.id)
        XCTAssertEqual(engine.activeLook, red.id)
        XCTAssertEqual(engine.baseLook, config.looks[0].id)
        XCTAssertEqual(colour(), [255, 0, 0])
        XCTAssertEqual(engine.frame(config: config)[2], 0)          // the flash's own program, not Gold Big's
        XCTAssertEqual(front(), [255, 153, 42])                     // the front fixture doesn't follow looks
        engine.releaseFlash(red.id)
        XCTAssertEqual(colour(), [255, 153, 13])
        XCTAssertEqual(engine.frame(config: config)[2], 40)

        // a look note during a flash becomes the look underneath
        engine.holdFlash(red.id)
        engine.selectLook(blue.id)
        XCTAssertEqual(colour(), [255, 0, 0])
        engine.releaseFlash(red.id)
        XCTAssertEqual(colour(), [0, 0, 255])

        // clearing notes and all-notes-off end flashes but keep the look underneath
        engine.holdFlash(red.id)
        engine.clearNotes()
        XCTAssertEqual(engine.activeLook, blue.id)
        engine.holdFlash(red.id)
        engine.controlChange(123, value: 0, config: config, channel: 1)
        XCTAssertEqual(engine.activeLook, blue.id)
        XCTAssertEqual(engine.heldFlashes, [])

        // the flag survives a patch round trip, and looks saved without it aren't flashes
        let file = try PatchFile.export(config)
        let loaded = try PatchFile.load(file, into: .defaults)
        XCTAssertEqual(loaded.looks.first { $0.note == 96 }?.flash, true)
        XCTAssertEqual(loaded.looks.first { $0.note == 61 }?.flash, false)
        let old = #"{"id":"6A1F0E2C-1B3D-4C51-9A01-0000000000B1","name":"Old","note":70,"color":{"r":1,"g":2,"b":3},"effect":{}}"#
        XCTAssertEqual(try JSONDecoder().decode(Look.self, from: Data(old.utf8)).flash, false)
    }

    func testGroupWarmthFixesColourToSteadyWhiteAndIgnoresLooks() throws {
        XCTAssertEqual(RGB(kelvin: 2700), RGB(255, 167, 87))
        XCTAssertEqual(RGB(kelvin: 4300), RGB(255, 213, 179))
        XCTAssertEqual(RGB(kelvin: 6500), RGB(255, 254, 250))

        var config = effectRig()
        config.fixtures[1].effect = EffectSettings(strobe: 104, program: 40, speed: 200)
        config.fixtures[1].followsLooks = true                      // the group overrides this
        config.groups = [FixtureGroup(name: "Front wash", fixtureIDs: [config.fixtures[1].id], warmth: 3200)]
        XCTAssertNoThrow(try config.validated(requireHost: false))
        var engine = LightingEngine()
        engine.selectLook(config.looks[0].id)                       // Gold Big
        engine.controlChange(21, value: 127, config: config)
        var frame = engine.frame(config: config)
        XCTAssertEqual(frame[21], 255)                              // brightness still follows CC 21
        XCTAssertEqual(Array(frame[22...24]), [0, 0, 128])          // strobe off, One Color Static, default speed
        XCTAssertEqual(Array(frame[30...32]), [255, 184, 123])      // colour 1 at 3200 K
        XCTAssertEqual(Array(frame[33...41]), [255, 184, 123, 255, 184, 123, 255, 184, 123])
        XCTAssertEqual(Array(frame[9...11]), [255, 153, 13])        // the fixture outside the group still follows looks
        let red = Look(name: "Red Flash", note: 96, color: RGB(255, 0, 0), flash: true)
        config.looks.append(red)
        engine.holdFlash(red.id)
        frame = engine.frame(config: config)
        XCTAssertEqual(Array(frame[30...32]), [255, 184, 123])      // flashes don't reach it either
        XCTAssertEqual(Array(frame[9...11]), [255, 0, 0])

        // the first group that fixes warmth wins; groups without warmth don't count
        config.groups.insert(FixtureGroup(name: "All", fixtureIDs: config.fixtures.map(\.id)), at: 0)
        config.groups.append(FixtureGroup(name: "Cool", fixtureIDs: [config.fixtures[1].id], warmth: 6500))
        XCTAssertEqual(config.warmth(of: config.fixtures[1]), 3200)
        XCTAssertNil(config.warmth(of: config.fixtures[0]))

        // saved and loaded with the patch; out-of-range values are kept in range; old groups have none
        let loaded = try PatchFile.load(try PatchFile.export(config), into: .defaults)
        XCTAssertEqual(loaded.groups.map(\.warmth), [nil, 3200, 6500])
        XCTAssertEqual(FixtureGroup(name: "Hot", warmth: 1500).warmth, 2700)
        let old = #"{"id":"6A1F0E2C-1B3D-4C51-9A01-0000000000C1","name":"Old","fixtureIDs":[],"maxLevel":80}"#
        XCTAssertNil(try JSONDecoder().decode(FixtureGroup.self, from: Data(old.utf8)).warmth)
        let far = #"{"id":"6A1F0E2C-1B3D-4C51-9A01-0000000000C2","name":"Far","warmth":9000}"#
        XCTAssertEqual(try JSONDecoder().decode(FixtureGroup.self, from: Data(far.utf8)).warmth, 6500)
    }

    func testLookAndLevelCCValidationAndPatchRoundTrip() throws {
        var config = effectRig()
        config.looks[0].note = 37
        XCTAssertThrowsError(try config.validated(requireHost: false)) {
            XCTAssertEqual(($0 as? PatchError)?.code, "AX1-215")
        }
        config.looks[0].note = 60
        config.fixtures[0].levelCC = 7
        XCTAssertThrowsError(try config.validated(requireHost: false)) {
            XCTAssertEqual(($0 as? PatchError)?.code, "AX1-214")
        }
        config.fixtures[0].levelCC = 20
        let imported = try PatchFile.load(try PatchFile.export(config), into: .defaults)
        XCTAssertEqual(imported.looks, config.looks)
        XCTAssertEqual(imported.fixtures, config.fixtures)

        // a version 1 patch without looks or level CCs still loads
        let v1 = #"{"format":"AsteraDMXMidiBridge.patch","version":1,"midiChannel":0,"masterCC":7,"fixtures":[{"id":"6A1F0E2C-1B3D-4C51-9A01-0000000000A1","name":"AX1 1","address":1,"note":36,"color":{"r":1,"g":2,"b":3},"enabled":true}]}"#
        let old = try PatchFile.load(Data(v1.utf8), into: .defaults)
        XCTAssertEqual(old.looks, [])
        XCTAssertNil(old.fixtures[0].levelCC)
        XCTAssertTrue(old.fixtures[0].followsLooks)
    }

    func testFixtureAndGroupMaximumsScaleOutput() throws {
        var config = effectRig()
        var engine = LightingEngine()
        engine.controlChange(20, value: 127, config: config)
        engine.controlChange(21, value: 127, config: config)
        XCTAssertEqual(engine.frame(config: config)[0], 255)

        config.fixtures[0].maxLevel = 50
        XCTAssertEqual(engine.frame(config: config)[0], 127)   // halves round down, like the master
        config.groups = [FixtureGroup(name: "Stage", fixtureIDs: [config.fixtures[0].id], maxLevel: 50)]
        XCTAssertEqual(config.limit(of: config.fixtures[0]), 0.25, accuracy: 1e-9)
        var frame = engine.frame(config: config)
        XCTAssertEqual(frame[0], 64)
        XCTAssertEqual(frame[21], 255)                       // the front fixture isn't in the group
        XCTAssertEqual(Array(frame[9...11]), [255, 73, 59])  // effect colours aren't dimmed, only the dimmer

        // a fixture in two groups gets both
        config.groups.append(FixtureGroup(name: "All", fixtureIDs: config.fixtures.map(\.id), maxLevel: 40))
        frame = engine.frame(config: config)
        XCTAssertEqual(frame[0], 25)
        XCTAssertEqual(frame[21], 102)

        // RGB profiles scale the colour
        var rgb = BridgeConfig.defaults
        rgb.fixtures[0].maxLevel = 50
        var e2 = LightingEngine()
        e2.noteOn(36, velocity: 127)
        XCTAssertEqual(Array(e2.frame(config: rgb)[0...2]), [127, 36, 29])
    }

    func testGroupsAndMaximumsRoundTripAndOldPatchesDefaultToFull() throws {
        var config = effectRig()
        config.fixtures[1].maxLevel = 70
        config.groups = [FixtureGroup(name: "Front", fixtureIDs: [config.fixtures[1].id], maxLevel: 30)]
        let imported = try PatchFile.load(try PatchFile.export(config), into: .defaults)
        XCTAssertEqual(imported.groups, config.groups)
        XCTAssertEqual(imported.fixtures[1].maxLevel, 70)

        let v2 = #"{"format":"AsteraDMXMidiBridge.patch","version":2,"midiChannel":0,"masterCC":7,"fixtures":[{"id":"6A1F0E2C-1B3D-4C51-9A01-0000000000A1","name":"AX1 1","address":1,"note":36,"color":{"r":1,"g":2,"b":3},"enabled":true,"maxLevel":180}]}"#
        let old = try PatchFile.load(Data(v2.utf8), into: .defaults)
        XCTAssertEqual(old.groups, [])
        XCTAssertEqual(old.fixtures[0].maxLevel, 100)        // out-of-range values are capped
    }

    func testLookMotionChasesAcrossFollowers() {
        let stage = (0..<4).map { FixturePatch(name: "S\($0 + 1)", address: 1 + $0 * 21, note: UInt8(36 + $0), color: RGB(255, 255, 255),
                                               profile: .effectRGB, levelCC: 20) }
        let front = FixturePatch(name: "F", address: 85, note: 40, color: RGB(255, 255, 255), profile: .effectRGB, levelCC: 21)
        var config = BridgeConfig(host: "", universe: 0, midiChannel: 0, masterCC: 7, fixtures: stage + [front])
        config.groups = [FixtureGroup(name: "Front", fixtureIDs: [front.id], warmth: 4300)]
        let chase = Look(name: "Chase", note: 108, color: RGB(255, 0, 0), motion: LookMotion(style: .chase, stepsPerBeat: 4))
        config.looks = [chase]
        var engine = LightingEngine()
        engine.controlChange(20, value: 127, config: config)
        engine.controlChange(21, value: 127, config: config)
        engine.selectLook(chase.id)
        for (beats, lit) in [(0.0, 0), (0.25, 1), (0.5, 2), (0.75, 3), (1.0, 0)] {
            engine.setBeats(beats)
            let frame = engine.frame(config: config)
            XCTAssertEqual(stage.map { frame[$0.address - 1] }, (0..<4).map { $0 == lit ? 255 : 0 })
            XCTAssertEqual(frame[front.address - 1], 255)
        }
    }

    func testLookMotionPatterns() {
        XCTAssertEqual(LookMotion(order: .bounce).steps(count: 4), [[0], [1], [2], [3], [2], [1]])
        XCTAssertEqual(LookMotion(order: .outsideIn).steps(count: 4), [[0, 3], [1, 2]])
        let highlight = LookMotion(style: .highlight, stepsPerBeat: 1, dim: 25)
        XCTAssertEqual(highlight.factor(index: 2, count: 4, beats: 0.5), 0.25)
        XCTAssertEqual(LookMotion(stepsPerBeat: 1, tail: 1).factor(index: 0, count: 4, beats: 1.5), 0.5, accuracy: 1e-9)
    }

    func testStoppedLevelKeepsGroupOnWhileStopped() {
        let front = FixturePatch(name: "F", address: 1, note: 40, color: RGB(255, 255, 255), profile: .effectRGB, levelCC: 21)
        var config = BridgeConfig(host: "", universe: 0, midiChannel: 0, masterCC: 7, fixtures: [front])
        config.groups = [FixtureGroup(name: "Front", fixtureIDs: [front.id], stoppedLevel: 60)]
        var engine = LightingEngine()
        engine.controlChange(21, value: 0, config: config)
        XCTAssertEqual(engine.frame(config: config)[0], 0)
        engine.setStopped(true)
        XCTAssertEqual(engine.frame(config: config)[0], 153)    // 60% of 255
        engine.controlChange(21, value: 127, config: config)
        XCTAssertEqual(engine.frame(config: config)[0], 255)
        engine.setStopped(false)
        engine.controlChange(21, value: 0, config: config)
        XCTAssertEqual(engine.frame(config: config)[0], 0)
    }
}
