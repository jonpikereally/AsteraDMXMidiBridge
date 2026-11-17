import AppKit
import AX1Core
import SwiftUI
import UniformTypeIdentifiers

private let bg = Color(red: 0.055, green: 0.070, blue: 0.085)
private let panel = Color(red: 0.088, green: 0.108, blue: 0.130)
private let recess = Color(red: 0.067, green: 0.083, blue: 0.103)
private let edge = Color(red: 0.17, green: 0.20, blue: 0.235)
private let ink = Color(red: 0.93, green: 0.95, blue: 0.96)
private let muted = Color(red: 0.58, green: 0.64, blue: 0.69)
private let accent = Color(red: 0.77, green: 0.99, blue: 0.42)
private let danger = Color(red: 1, green: 0.50, blue: 0.46)
private let errorHelp = "Check the Error list page for this code."

@main
struct AsteraDMXMidiBridgeApp: App {
    @StateObject private var model = ConsoleModel()
    @NSApplicationDelegateAdaptor(BridgeAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ConsoleView(model: model).onAppear { delegate.model = model; model.start() }
                .preferredColorScheme(.dark)
                .frame(minWidth: 960, minHeight: 690)
        }
        .defaultSize(width: 1170, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { model.checkForUpdates() }
            }
            CommandMenu("Output") {
                Button(model.engine.blackout ? "Release Blackout" : "Blackout") {
                    model.toggleBlackout()
                }.keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Clear Held Notes") { model.clearNotes() }
                    .keyboardShortcut(".", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class BridgeAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: ConsoleModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let deferred = model?.prepareToQuit { sender.reply(toApplicationShouldTerminate: true) } ?? false
        return deferred ? .terminateLater : .terminateNow
    }
}

private enum ConsolePage: String, CaseIterable {
    case console = "Console", patch = "Fixture patch", errors = "Error list"
}

struct ConsoleView: View {
    @ObservedObject var model: ConsoleModel
    @State private var page: ConsolePage = .console
    @State private var edit: BridgeConfig = .defaults
    @State private var patchSaved = false
    @State private var patchNote: String?

    var body: some View {
        VStack(spacing: 0) {
            masthead
            navigation
            if let issue = model.issue { errorBanner(issue) }
            if let update = model.updateStatus { updateBanner(update) }
            ScrollView {
                switch page {
                case .console: console
                case .patch: patch
                case .errors: errorIndex
                }
            }
            .scrollIndicators(.visible)
            footer
        }
        .background(bg)
        .foregroundStyle(ink)
        .tint(accent)
        .onChange(of: model.learned?.id) { _ in applyLearned() }
        .onChange(of: edit) { _ in patchSaved = false }
    }

    private var masthead: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill(accent).frame(width: 49, height: 49)
                HStack(spacing: 3) {
                    ForEach([14.0, 25, 33, 21, 13], id: \.self) { height in
                        Capsule().fill(bg).frame(width: 3, height: height)
                    }
                }
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("AsteraDMXMidiBridge").font(.system(size: 26, weight: .bold))
                label("MIDI  /  DMX  /  CRMX", color: muted)
            }
            Spacer()
            livePill
            Button(action: model.toggleBlackout) {
                Label(model.engine.blackout ? "Release blackout" : "Blackout", systemImage: "moon.fill")
            }
            .buttonStyle(ConsoleButton(color: danger, filled: model.engine.blackout))
            .help("Stop all fixture light. Command–Shift–B")
        }
        .padding(.horizontal, 27).padding(.vertical, 20)
    }

    private var livePill: some View {
        let blackout = model.engine.blackout
        let tint = blackout ? danger : (model.live ? accent : muted)
        return HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 7, height: 7)
            label(blackout ? "BLACKOUT" : model.usbStarting ? "STARTING USB" : model.usbClosing ? "STOPPING USB" : model.live ? "OUTPUT ARMED" : "PREVIEW ONLY", color: tint)
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(tint.opacity(0.085), in: Capsule())
        .overlay { Capsule().strokeBorder(tint.opacity(0.25)) }
        .accessibilityElement(children: .combine)
    }

    private var navigation: some View {
        HStack(spacing: 7) {
            ForEach(ConsolePage.allCases, id: \.self) { item in
                Button {
                    if item == .patch && page != .patch {
                        edit = model.config
                        patchSaved = false
                    }
                    if item != .patch { model.learning = nil }
                    page = item
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item == .console ? "rectangle.grid.2x2" : item == .patch ? "slider.horizontal.3" : "list.bullet.rectangle")
                            .accessibilityHidden(true)
                        Text(item.rawValue)
                    }.font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(page == item ? accent : muted)
                    .padding(.horizontal, 13).padding(.vertical, 10)
                    .background(page == item ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
            Spacer()
            label("ASTERA  /  PIXELTUBE AX1", color: muted)
        }
        .padding(.horizontal, 27).padding(.bottom, 12)
        .background(alignment: .bottom) { Rectangle().fill(edge).frame(height: 1) }
    }

    private var console: some View {
        HStack(alignment: .top, spacing: 19) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        label("01  /  LIVE MONITOR", color: accent)
                        Text("Fixture deck").font(.system(size: 29, weight: .semibold))
                    }
                    Spacer()
                    Button {
                        model.toggleDemo()
                    } label: {
                        Label(model.demo ? "Stop preview" : "Run preview", systemImage: model.demo ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(ConsoleButton(color: model.demo ? accent : ink))
                    .disabled(model.live || model.engine.blackout)
                    .help("Demo runs locally with output disarmed.")
                    Button { model.clearNotes() } label: { Label("Clear notes", systemImage: "xmark") }
                        .buttonStyle(ConsoleButton(color: muted))
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 125), spacing: 12), count: 4), spacing: 12) {
                    ForEach(Array(model.config.fixtures.enumerated()), id: \.element.id) { index, fixture in
                        fixtureCard(fixture, index: index)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap").foregroundStyle(accent)
                    Text("Click a fixture to latch it. MIDI notes follow velocity and release.")
                        .foregroundStyle(muted)
                }.font(.system(size: 12))
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            rack.frame(width: 300)
        }
        .padding(26)
    }

    private func fixtureCard(_ fixture: FixturePatch, index: Int) -> some View {
        let noteRange = fixture.noteRange
        let velocity = noteRange.compactMap { model.engine.levels[UInt8(clamping: $0)] }.max() ?? 0
        let level = fixture.enabled && !model.engine.blackout ? (Double(velocity) / 127) * (Double(model.engine.master) / 127) : 0
        let tint = fixtureColor(fixture)
        let tintStrength = min(1, max(0.28, level + 0.18))
        return Button {
            model.tap(fixture)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    label(String(format: "%02d", index + 1), color: muted)
                    Spacer()
                    Circle().fill(level > 0 ? tint : edge).frame(width: 7, height: 7)
                }
                HStack(spacing: 4) {
                    ForEach(0..<16) { index in
                        let pixelNote = UInt8(clamping: Int(fixture.note) + index)
                        let independentActive = (model.engine.levels[pixelNote] ?? 0) != 0
                        let on = level > 0 && (!fixture.independentPixels || fixture.profile != .rgb16 || independentActive)
                        RoundedRectangle(cornerRadius: 1.5).fill(tint.opacity(on ? tintStrength : 0.11))
                                .shadow(color: on ? tint.opacity(level * 0.5) : .clear, radius: 5)
                    }
                }.frame(height: 15)
                 .background { Capsule().fill(tint.opacity(level * 0.18)).blur(radius: 13) }
                Text(fixture.name.isEmpty ? "Tube \(index + 1)" : fixture.name)
                    .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                VStack(alignment: .leading, spacing: 4) {
                    label("DMX \(String(format: "%03d", fixture.address))   /   N \(fixture.note)", color: muted)
                    Text(fixture.enabled ? fixture.profile.displayName : "Disabled")
                        .font(.system(size: 10, weight: .medium)).lineLimit(1)
                        .foregroundStyle(fixture.enabled ? tint.opacity(0.8) : muted)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(panel.opacity(fixture.enabled ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(level > 0 ? tint.opacity(0.42) : edge) }
        }
        .buttonStyle(.plain)
        .disabled(!fixture.enabled || model.engine.blackout || model.usbStarting)
        .accessibilityLabel(fixture.name)
        .accessibilityValue(level > 0 ? "Lit" : "Off")
        .help("Latch \(fixture.name) at full velocity, or click again to release.")
    }

    private var rack: some View {
        VStack(alignment: .leading, spacing: 13) {
            label("02  /  SIGNAL ROUTING", color: accent)
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("MIDI input", icon: "pianokeys")
                Picker("MIDI input", selection: Binding(get: { model.sourceID }, set: model.selectSource)) {
                    Text("No device selected").tag(Int32?.none)
                    ForEach(model.sources) { Text($0.name).tag(Optional($0.id)) }
                }.labelsHidden().pickerStyle(.menu)
                label(model.recent, color: muted).lineLimit(1).truncationMode(.middle)
            }.padding(13).rackPanel()

            VStack(alignment: .leading, spacing: 11) {
                sectionTitle("DMX output", icon: "point.3.connected.trianglepath.dotted")
                VStack(alignment: .leading, spacing: 9) {
                    Picker("Output protocol", selection: $model.outputMode) {
                        ForEach(OutputMode.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().pickerStyle(.menu)

                    if model.outputMode == .usb {
                        HStack(spacing: 7) {
                            Picker("USB DMX interface", selection: $model.usbPath) {
                                Text(model.usbPorts.isEmpty ? "No USB DMX interface found" : "Choose a USB interface").tag("")
                                ForEach(model.usbPorts, id: \.self) { port in
                                    Text(OpenDMXOutput.label(for: port, among: model.usbPorts)).tag(port)
                                }
                            }.labelsHidden().pickerStyle(.menu)
                            Button { model.refreshUSB() } label: { Image(systemName: "arrow.clockwise") }
                                .buttonStyle(.borderless)
                                .help("Refresh USB DMX interfaces")
                                .accessibilityLabel("Refresh USB DMX interfaces")
                        }
                        Text("Open DMX USB → ART7 DMX input → AX1 via CRMX")
                            .font(.system(size: 11)).foregroundStyle(muted)
                    } else {
                        HStack(alignment: .top, spacing: 9) {
                            VStack(alignment: .leading, spacing: 4) {
                                label("IP ADDRESS", color: muted)
                                TextField("127.0.0.1", text: $model.host)
                                    .accessibilityLabel("Art-Net destination IPv4 address")
                                    .onSubmit { _ = model.saveDestination() }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                label("UNIVERSE", color: muted)
                                TextField("0", text: $model.universe)
                                    .accessibilityLabel("Art-Net universe")
                                    .onSubmit { _ = model.saveDestination() }
                            }.frame(width: 72)
                        }
                        Button("Use QLC+ loopback") {
                            model.host = "127.0.0.1"; model.universe = "0"
                            _ = model.saveDestination()
                        }.buttonStyle(.link)
                         .font(.system(size: 11))
                    }
                }.disabled(model.live)

                Button { model.toggleLive() } label: {
                    Label(model.live ? "Disarm output" : "Arm live output",
                          systemImage: model.live ? "stop.circle" : "bolt.fill")
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ConsoleButton(color: accent, filled: !model.live))
                .disabled(model.usbClosing)
                Text(model.usbStarting ? "Opening the USB DMX port…" : model.usbClosing ? "Sending final blackout frames…" : model.live ? "Sending DMX frames. Fixture status isn’t reported by the transmitter." : "Preview stays on this Mac until you arm output.")
                    .foregroundStyle(muted).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            }.padding(13).rackPanel()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionTitle("Master level", icon: "dial.medium")
                    Spacer()
                    label("\(Int((Double(model.engine.master) * 100 / 127).rounded()))%", color: accent)
                }
                Slider(value: Binding(get: { Double(model.engine.master) },
                                      set: { model.setMaster(UInt8(clamping: Int($0.rounded()))) }),
                       in: 0...127, step: 1)
                    .accessibilityLabel("Master level")
                label("MIDI CC \(model.config.masterCC)", color: muted)
            }.padding(13).rackPanel()
        }
    }

    private var patch: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    label("03  /  FIXTURE PATCH", color: accent)
                    Text("Build your rig").font(.system(size: 29, weight: .semibold))
                }
                Spacer()
                if patchSaved {
                    Label("Patch saved", systemImage: "checkmark").foregroundStyle(accent).font(.system(size: 12))
                } else if let patchNote {
                    Label(patchNote, systemImage: "doc").foregroundStyle(accent).font(.system(size: 12))
                }
                Button { importPatch() } label: { Label("Import…", systemImage: "square.and.arrow.down") }
                    .buttonStyle(ConsoleButton(color: muted)).disabled(model.live)
                    .help("Load a patch file into the editor. Click Apply patch to use it.")
                Button { exportPatch() } label: { Label("Export…", systemImage: "square.and.arrow.up") }
                    .buttonStyle(ConsoleButton(color: muted))
                    .help("Save the patch shown here as a file you can back up or share.")
                Button("Use default patch") {
                    edit = .defaults
                    model.learning = nil
                    patchSaved = false
                }.buttonStyle(ConsoleButton(color: muted)).disabled(model.live)
                Button("Apply patch") {
                    if model.savePatch(edit) { patchSaved = true; patchNote = nil; model.learning = nil }
                }.buttonStyle(ConsoleButton(color: accent, filled: true)).disabled(model.live)
            }
            Text(model.live ? "Disarm output before editing the patch." : "Set each tube to the same DMX profile and start address in AsteraApp. The app checks for overlapping addresses and notes.")
                .foregroundStyle(muted).font(.system(size: 13))
            HStack(spacing: 22) {
                Picker("MIDI channel", selection: $edit.midiChannel) {
                    Text("Omni").tag(0)
                    ForEach(1...16, id: \.self) { Text("Channel \($0)").tag($0) }
                }.frame(width: 225)
                Stepper("Master CC: \(edit.masterCC)", value: $edit.masterCC, in: 0...119)
                    .frame(width: 154)
                Spacer()
                Menu("Auto-patch") {
                    Button("Pack DMX addresses from 1") { packAddresses() }
                    Button("Pack MIDI notes from 0") { packNotes() }
                }.fixedSize()
                 .help("Pack enabled fixtures back to back using their current profiles.")
                Text("One DMX universe").font(.system(size: 12)).foregroundStyle(muted)
            }
            .disabled(model.live)
            .padding(13).rackPanel()
            VStack(spacing: 0) {
                patchHeader
                ForEach(Array(edit.fixtures.indices), id: \.self) { index in
                    patchRow(index)
                    if index != edit.fixtures.indices.last { Divider().overlay(edge.opacity(0.6)) }
                }
            }.rackPanel().disabled(model.live)
            Text("For 16-pixel RGB, All pixels mirrors one note across the tube. Note per pixel uses 16 consecutive MIDI notes, starting at the note shown. Effect Mode RGB runs Astera’s built-in programs on the tube: its note and the master level set the dimmer, and the program settings are sent continuously.")
                .foregroundStyle(muted).font(.system(size: 12))
        }
        .padding(26)
    }

    private func exportPatch() {
        do {
            try edit.validated(requireHost: false)
        } catch {
            model.report(error.localizedDescription)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "AsteraDMXMidiBridge Patch.\(PatchFile.fileExtension)"
        panel.message = "Export the fixture patch, MIDI channel and master CC."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PatchFile.export(edit).write(to: url, options: .atomic)
            patchNote = "Exported \(url.lastPathComponent)"
        } catch {
            model.report(PatchFileError.exportFailed.localizedDescription)
        }
    }

    private func importPatch() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an AsteraDMXMidiBridge patch file."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data: Data
            do { data = try Data(contentsOf: url) } catch { throw PatchFileError.unreadable }
            edit = try PatchFile.load(data, into: edit)
            model.learning = nil
            patchSaved = false
            patchNote = "Imported \(url.lastPathComponent). Click Apply patch to use it."
        } catch let error as PatchFileError {
            model.report(error.localizedDescription)
        } catch let error as PatchError {
            model.report(error.localizedDescription)
        } catch {
            model.report(PatchFileError.unreadable.localizedDescription)
        }
    }

    private func packAddresses() {
        var next = 1
        for index in edit.fixtures.indices where edit.fixtures[index].enabled {
            edit.fixtures[index].address = next
            next += edit.fixtures[index].profile.slotCount
        }
    }

    private func packNotes() {
        var next = 0
        for index in edit.fixtures.indices where edit.fixtures[index].enabled {
            edit.fixtures[index].note = UInt8(clamping: next)
            next += edit.fixtures[index].noteCount
        }
    }

    private var patchHeader: some View {
        HStack(spacing: 12) {
            label("ON", color: muted).frame(width: 28)
            label("FIXTURE", color: muted).frame(maxWidth: .infinity, alignment: .leading)
            label("ASTERA PROFILE", color: muted).frame(width: 210, alignment: .leading)
            label("DMX START", color: muted).frame(width: 92, alignment: .leading)
            label("MIDI NOTE", color: muted).frame(width: 121, alignment: .leading)
            label("COLOR", color: muted).frame(width: 106, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(recess.opacity(0.72))
    }

    private func patchRow(_ index: Int) -> some View {
        let field = $edit.fixtures[index]
        let fixture = edit.fixtures[index]
        return VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 12) {
            Toggle("Enable fixture \(index + 1)", isOn: field.enabled).labelsHidden().frame(width: 28)
            TextField("Fixture name", text: field.name)
                .accessibilityLabel("Fixture \(index + 1) name")
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 5) {
                Picker("Fixture \(index + 1) DMX profile", selection: field.profile) {
                    ForEach(AX1Profile.allCases) {
                        Text("\($0.rawValue) · \($0.displayName)  /  \($0.slotCount) ch").tag($0)
                    }
                }.labelsHidden()
                if fixture.profile == .rgb16 {
                    Picker("Pixel trigger mode", selection: field.independentPixels) {
                        Text("All pixels").tag(false)
                        Text("Note per pixel").tag(true)
                    }.labelsHidden()
                }
            }.frame(width: 210, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                TextField("Start", value: field.address, format: .number.grouping(.never))
                    .accessibilityLabel("Fixture \(index + 1) DMX start")
                    .frame(width: 58)
                label(fixture.slotCountLabel, color: muted)
            }.frame(width: 92, alignment: .leading)
            HStack(spacing: 6) {
                TextField("Note", value: field.note, format: .number.grouping(.never))
                    .accessibilityLabel("Fixture \(index + 1) MIDI note")
                    .frame(width: 43)
                Button(model.learning == fixture.id ? "Waiting…" : "Learn") {
                    model.learning = model.learning == fixture.id ? nil : fixture.id
                }
                .buttonStyle(.borderless)
                .foregroundStyle(model.learning == fixture.id ? accent : muted)
                .disabled(model.sourceID == nil)
                .help("Assign the next note from the selected MIDI input.")
            }.frame(width: 121, alignment: .leading)
            HStack(spacing: 5) {
                ColorPicker("Fixture \(index + 1) RGB", selection: Binding(
                    get: { color(fixture.color) },
                    set: { newColor in
                        if let value = NSColor(newColor).usingColorSpace(.sRGB) {
                            edit.fixtures[index].color = RGB(byte(value.redComponent), byte(value.greenComponent), byte(value.blueComponent))
                        }
                    }), supportsOpacity: false).labelsHidden()
                if fixture.profile.hasWhite {
                    Text("W").font(.system(size: 10)).foregroundStyle(muted)
                    TextField("White", value: field.white, format: .number.grouping(.never))
                        .accessibilityLabel("Fixture \(index + 1) white level")
                        .frame(width: 44)
                }
                Spacer(minLength: 0)
            }.frame(width: 106, alignment: .leading)
        }.padding(.horizontal, 14).padding(.vertical, 10)
            if fixture.profile.isEffect {
                effectPanel(index)
            }
        }
    }

    private func effectPanel(_ index: Int) -> some View {
        let effect = $edit.fixtures[index].effect
        let name = edit.fixtures[index].name
        let strobe = effect.wrappedValue.strobe
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 18) {
                effectPicker("Program", options: EffectSettings.programs, value: effect.program, fixture: name)
                    .frame(width: 250)
                effectPicker("Direction", options: EffectSettings.directions, value: effect.direction, fixture: name)
                    .frame(width: 200)
                effectPicker("Size", options: EffectSettings.sizes, value: effect.size, fixture: name)
                    .frame(width: 170)
                Spacer(minLength: 0)
            }
            HStack(spacing: 18) {
                effectPicker("Strobe", options: EffectSettings.strobeModes, value: effect.strobe, fixture: name)
                    .frame(width: 210)
                if EffectSettings.variableStrobe.contains(strobe) {
                    effectSlider("Strobe rate", value: effect.strobe, range: EffectSettings.variableStrobe, fixture: name)
                }
                effectSlider("Speed", value: effect.speed, fixture: name)
                effectSlider("Crossfade", value: effect.crossfade, fixture: name)
            }
            HStack(spacing: 18) {
                effectSlider("Offset", value: effect.offset, fixture: name)
                effectSlider("Restart", value: effect.restart, fixture: name)
                HStack(spacing: 8) {
                    label("COLOURS 2–4", color: muted)
                    ForEach(0..<3, id: \.self) { slot in
                        ColorPicker("\(name) effect colour \(slot + 2)", selection: Binding(
                            get: { color(edit.fixtures[index].effect.colors[slot]) },
                            set: { newColor in
                                if let value = NSColor(newColor).usingColorSpace(.sRGB) {
                                    edit.fixtures[index].effect.colors[slot] = RGB(byte(value.redComponent), byte(value.greenComponent), byte(value.blueComponent))
                                }
                            }), supportsOpacity: false).labelsHidden()
                            .help("Effect colour \(slot + 2). Colour 1 is the fixture colour above.")
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 54).padding(.trailing, 14).padding(.bottom, 12)
    }

    private func effectPicker(_ title: String, options: [EffectOption], value: Binding<UInt8>, fixture: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label(title.uppercased(), color: muted)
            Picker("\(fixture) \(title.lowercased())", selection: Binding(
                get: { EffectOption.matching(value.wrappedValue, in: options)?.value ?? options[0].value },
                set: { picked in
                    // Keep a variable strobe rate when Variable is picked again.
                    if let option = EffectOption.matching(picked, in: options), option.range.contains(value.wrappedValue) { return }
                    value.wrappedValue = picked
                })) {
                ForEach(options) { Text($0.name).tag($0.value) }
            }.labelsHidden()
        }
    }

    private func effectSlider(_ title: String, value: Binding<UInt8>, range: ClosedRange<UInt8> = 0...255, fixture: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                label(title.uppercased(), color: muted)
                Spacer()
                label("\(value.wrappedValue)", color: accent)
            }
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = UInt8(clamping: Int($0.rounded())) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .accessibilityLabel("\(fixture) \(title.lowercased())")
        }.frame(width: 150)
    }

    private func applyLearned() {
        guard page == .patch, let learned = model.learned,
              let index = edit.fixtures.firstIndex(where: { $0.id == learned.fixtureID }) else { return }
        edit.fixtures[index].note = learned.note
        patchSaved = false
    }

    private func updateBanner(_ update: UpdateStatus) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.down.circle").accessibilityHidden(true)
            Text(update.message)
            Spacer()
            if update.hasUpdate {
                Button("View release") { model.openReleasePage() }
                    .buttonStyle(ConsoleButton(color: muted))
                Button("Install and relaunch") { model.installUpdate() }
                    .buttonStyle(ConsoleButton(color: accent, filled: true))
                    .help("Download the update, replace this app and reopen it. Live output stops while the app restarts.")
            }
            if case .installing = update {
                ProgressView().controlSize(.small)
            }
            if case .checked = update {
                Button { model.dismissUpdateStatus() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Dismiss update status")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(update.hasUpdate ? accent : muted)
        .padding(.horizontal, 26).padding(.vertical, 7)
        .background(accent.opacity(0.06))
    }

    private func errorBanner(_ issue: ConsoleIssue) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
            Text(issue.message).lineLimit(2).help(errorHelp)
            Spacer()
            Button("Error list") { page = .errors; model.learning = nil }
                .buttonStyle(.plain).underline().help(errorHelp)
            Button { model.dismissError() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).accessibilityLabel("Dismiss error")
        }
        .font(.system(size: 12, weight: .medium)).foregroundStyle(danger)
        .padding(.horizontal, 26).padding(.vertical, 10)
        .background(danger.opacity(0.09))
        .help(errorHelp)
    }

    private var errorIndex: some View {
        VStack(alignment: .leading, spacing: 16) {
            label("04  /  TROUBLESHOOTING", color: accent)
            Text("Error list").font(.system(size: 29, weight: .semibold))
            Text("Use the code from the console to find the next check.").foregroundStyle(muted)
            VStack(spacing: 0) {
                ForEach(BridgeErrors.all, id: \.0) { entry in
                    HStack(alignment: .top, spacing: 16) {
                        label(entry.0, color: accent).frame(width: 83, alignment: .leading)
                        Text(entry.1).font(.system(size: 13)).foregroundStyle(ink).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 13).padding(.vertical, 10)
                    .help(errorHelp)
                    Divider().overlay(edge.opacity(0.45))
                }
            }.rackPanel()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(26)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform").foregroundStyle(accent)
            label("ASTERADMXMIDIBRIDGE", color: ink)
            Rectangle().fill(edge).frame(width: 1, height: 12)
            label("DMX512  /  30 FPS TARGET", color: muted)
            Spacer()
            label("V\(BuildInfo.version)  ·  BUILD \(BuildInfo.number)  ·  \(BuildInfo.date.uppercased())", color: muted)
        }
        .padding(.horizontal, 27).padding(.vertical, 11)
        .background(alignment: .top) { Rectangle().fill(edge).frame(height: 1) }
        .background(recess)
    }

    private func label(_ title: String, color: Color) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.9).foregroundStyle(color)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ink)
    }

    private func byte(_ component: CGFloat) -> UInt8 {
        UInt8(clamping: Int((min(1, max(0, component)) * 255).rounded()))
    }

    private func color(_ rgb: RGB) -> Color {
        Color(.sRGB, red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }

    private func fixtureColor(_ fixture: FixturePatch) -> Color {
        let rgb = fixture.color
        let w = fixture.profile.hasWhite ? Double(fixture.white) / 255 : 0
        if rgb == RGB(0, 0, 0) && w == 0 { return muted }
        return Color(.sRGB, red: min(1, Double(rgb.r) / 255 + w),
                     green: min(1, Double(rgb.g) / 255 + w), blue: min(1, Double(rgb.b) / 255 + w))
    }
}

private extension FixturePatch {
    var slotCountLabel: String {
        let last = String(format: "%03d", min(999, max(-99, address)) + profile.slotCount - 1)
        return "END \(last)"
    }
}

private struct ConsoleButton: ButtonStyle {
    var color: Color
    var filled = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(filled ? bg : color)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(filled ? color : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(filled ? color : color.opacity(0.26)) }
            .opacity(!isEnabled ? 0.36 : configuration.isPressed ? 0.70 : 1)
            .contentShape(Rectangle())
    }
}

private extension View {
    func rackPanel() -> some View {
        self.background(panel, in: RoundedRectangle(cornerRadius: 11))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(edge).allowsHitTesting(false) }
    }
}

private enum BridgeErrors {
    static let all: [(String, String)] = [
        ("AX1-104", "The selected MIDI input disconnected. Reconnect it and choose it again; held notes were cleared."),
        ("AX1-105", "Select the Open DMX USB interface. Plug it in and click Refresh. If it stays missing, try the QLC+ route in the README."),
        ("AX1-201", "Enter the Art-Net receiver’s IPv4 address. For the QLC+ fallback, use 127.0.0.1."),
        ("AX1-202", "Enter a valid unicast IPv4 address. Multicast and broadcast destinations aren’t supported."),
        ("AX1-203", "Use a DMX universe from 0 to 32767. QLC+ Universe 1 usually corresponds to Art-Net universe 0."),
        ("AX1-204", "Use MIDI channel 1–16 or select Omni."),
        ("AX1-205", "Use a master CC from 0–119. CC 120 and 123 act as all-notes-off messages."),
        ("AX1-206", "The fixture runs past DMX slot 512, or its start address is below 1. Choose a start that leaves room for the entire profile."),
        ("AX1-207", "The note range must fit within MIDI notes 0–127. Note per pixel mode needs 16 consecutive notes."),
        ("AX1-208", "DMX slots overlap. Move one of the enabled fixtures until its entire profile has its own slots."),
        ("AX1-209", "MIDI note ranges overlap. Move one of the enabled fixtures until the ranges are separate."),
        ("AX1-210", "The patch file couldn’t be read. Export it again from AsteraDMXMidiBridge and import the new file."),
        ("AX1-211", "That file isn’t an AsteraDMXMidiBridge patch. Choose a file made with Export… on the Fixture patch page."),
        ("AX1-212", "The patch was saved by a newer version of the app. Use AsteraDMXMidiBridge → Check for Updates, then import it again."),
        ("AX1-213", "The patch couldn’t be saved in that location. Choose another folder, such as Documents, and export again."),
        ("AX1-301", "Core MIDI couldn’t start. Reconnect the controller or restart the app."),
        ("AX1-302", "The app couldn’t open a Core MIDI input port. Restart the app and check Audio MIDI Setup."),
        ("AX1-303", "The MIDI source is no longer available. Choose a connected source."),
        ("AX1-304", "The app couldn’t connect to that MIDI source. Reconnect the controller and select it again."),
        ("AX1-305", "The app couldn’t disconnect the MIDI source cleanly. Reselect a source or restart the app."),
        ("AX1-306", "Enter a valid unicast Art-Net destination. To use the QLC+ fallback, choose its loopback preset."),
        ("AX1-307", "Set the Art-Net universe between 0 and 32767."),
        ("AX1-308", "The UDP socket couldn’t open. Close the other application using the Art-Net port, or use the QLC+ loopback preset."),
        ("AX1-309", "Arm the Art-Net output before sending frames."),
        ("AX1-310", "Art-Net needs a full 512-slot frame. Restart the app if the error repeats."),
        ("AX1-311", "Check the active network connection and the Mac’s Local Network permission if available, then rearm."),
        ("AX1-312", "Select a connected ENTTEC Open DMX USB interface. Refresh the list after reconnecting the hardware."),
        ("AX1-313", "The USB port couldn’t open. Close QLC+ or other lighting software using the interface, then reconnect and rearm."),
        ("AX1-314", "The USB driver couldn’t configure DMX512. If reconnecting doesn’t help, use the QLC+ route in the README."),
        ("AX1-315", "The USB stream stopped. Check the connection and rearm. Use QLC+ if the native connection keeps failing."),
        ("AX1-316", "USB output needs a full 512-slot frame. Restart the app if the error repeats."),
        ("AX1-317", "Arm the USB output before sending frames."),
        ("AX1-318", "Wait for the USB stream to finish stopping before arming again."),
        ("AX1-319", "The direct USB connection could not open. Quit other apps using the ENTTEC and reconnect it. Try the serial entry if one is available."),
        ("AX1-320", "The direct USB stream stopped. Check the USB connection and rearm. Try QLC+ if the error repeats."),
        ("AX1-401", "The installed app version could not be read. Open a packaged release and try again."),
        ("AX1-402", "GitHub could not be reached. Check your internet connection and try again."),
        ("AX1-403", "GitHub did not respond in time. Try again shortly."),
        ("AX1-404", "GitHub is limiting update checks. Wait before trying again."),
        ("AX1-405", "GitHub returned an unexpected response. Try again later or open the project’s Releases page."),
        ("AX1-406", "The latest release has an unrecognized version. Check the project’s Releases page."),
        ("AX1-407", "The app could not open your browser. Visit the project’s Releases page from a browser."),
        ("AX1-408", "The release has no app download. Click View release and download it manually."),
        ("AX1-409", "This copy can’t update itself. Move AsteraDMXMidiBridge to Applications, open it from there and try again."),
        ("AX1-410", "You can’t write to the app’s folder. Use View release to install the update manually."),
        ("AX1-411", "The update couldn’t be downloaded. Check your internet connection and try again."),
        ("AX1-412", "The downloaded update couldn’t be unpacked. Try again, or use View release."),
        ("AX1-413", "The downloaded update failed its checks and wasn’t installed. Use View release and report the problem."),
        ("AX1-414", "The app couldn’t be replaced, so your version is unchanged. Use View release to install manually."),
        ("AX1-415", "The update is installed but the app couldn’t restart itself. Quit and open the app again.")
    ]
}
