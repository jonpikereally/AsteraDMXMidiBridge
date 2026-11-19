import AppKit
import AX1Core
import SwiftUI

enum OutputMode: String, CaseIterable, Identifiable {
    case artnet, usb
    var id: Self { self }
    var title: String {
        switch self {
        case .artnet: return "Art-Net"
        case .usb: return "ENTTEC Open DMX USB"
        }
    }
}

struct ConsoleIssue: Identifiable {
    let id = UUID()
    let message: String
}

enum UpdateStatus {
    case checking
    case checked(UpdateChecker.CheckResult)
    case installing(String)

    var message: String {
        switch self {
        case .checking: return "Checking GitHub for updates…"
        case .installing(let version): return "Downloading and installing version \(version)…"
        case .checked(.current): return "You have the latest available version."
        case .checked(.available(let version, _)): return "Version \(version) is available."
        case .checked(.noRelease): return "There are no published releases yet."
        }
    }

    var hasUpdate: Bool {
        if case .checked(.available) = self { return true }
        return false
    }
}

struct LearnedNote: Identifiable {
    let id = UUID()
    let fixtureID: UUID
    let note: UInt8
}

private struct NoteKey: Hashable {
    let channel: Int
    let note: UInt8
}

@MainActor final class ConsoleModel: ObservableObject {
    @Published private(set) var config: BridgeConfig
    @Published private(set) var engine = LightingEngine()
    @Published private(set) var sources: [MIDISource] = []
    @Published private(set) var sourceID: Int32?
    @Published private(set) var live = false
    @Published private(set) var usbStarting = false
    @Published private(set) var usbClosing = false
    @Published private(set) var demo = false
    @Published private(set) var recent = "Waiting for input"
    @Published private(set) var issue: ConsoleIssue?
    @Published private(set) var updateStatus: UpdateStatus?
    @Published private(set) var learned: LearnedNote?
    @Published var learning: UUID?
    @Published private(set) var pads: Set<UUID> = []
    @Published private(set) var usbPorts: [String] = []
    @Published var usbPath: String {
        didSet { UserDefaults.standard.set(usbPath, forKey: "openDMXPath") }
    }
    @Published var outputMode: OutputMode {
        didSet { UserDefaults.standard.set(outputMode.rawValue, forKey: "outputMode") }
    }
    @Published var host: String
    @Published var universe: String

    private let artnet = ArtNetOutput()
    private let usb = OpenDMXOutput()
    private var activeMode: OutputMode?
    private var midi: MIDIInput?
    private var timer: Timer?
    private var demoTimer: Timer?
    private var usbScanTimer: Timer?
    private var quitReply: (() -> Void)?
    private var updateTask: Task<Void, Never>?
    private var midiStarts: [NoteKey: UInt64] = [:]
    /// Uptime of the last MIDI clock pulse, and of the last output frame (for motion without clock).
    private var lastClock: UInt64 = 0
    private var lastTick: UInt64 = 0
    /// Motion time. Kept out of the published engine so clock pulses don't redraw the window; it's copied into the
    /// engine on each output frame while a moving look shows.
    private var clockRunning = false
    private var clockBeats: Double = 0
    private var freeBeats: Double = 0
    private var lastShownMotion: LookMotion?
    private var demoStep = 0
    private var didStart = false

    init(preview: Bool = false) {
        let defaults = UserDefaults.standard
        let decoded = defaults.data(forKey: "config.v1").flatMap { try? JSONDecoder().decode(BridgeConfig.self, from: $0) }
        let initial = decoded.flatMap { value -> BridgeConfig? in
            guard (try? value.validated(requireHost: false)) != nil else { return nil }
            return value
        } ?? .defaults
        config = initial
        host = initial.host
        universe = String(initial.universe)
        outputMode = defaults.string(forKey: "outputMode").flatMap(OutputMode.init(rawValue:)) ?? .usb
        usbPath = defaults.string(forKey: "openDMXPath") ?? ""
        if preview {
            config = .defaults
            host = ""
            universe = "0"
            outputMode = .usb
        }
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        refreshUSB()
        let usbScanner = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshUSB() }
        }
        usbScanner.tolerance = 0.3
        usbScanTimer = usbScanner
        RunLoop.main.add(usbScanner, forMode: .common)
        usb.onReady = { [weak self] in self?.usbStarting = false }
        usb.onError = { [weak self] error in
            guard let self else { return }
            if self.activeMode == .usb { self.disarm(tryZero: false) }
            self.report(error.localizedDescription)
        }
        usb.onStopped = { [weak self] in
            guard let self else { return }
            self.usbClosing = false
            let finish = self.quitReply
            self.quitReply = nil
            finish?()
        }
        do {
            let input = try MIDIInput()
            midi = input
            sources = input.sources
            input.onSourcesChanged = { [weak self] sources in self?.sources = sources }
            input.onMessage = { [weak self] event in self?.receive(event) }
            input.onSelectionLost = { [weak self] in
                guard let self else { return }
                self.sourceID = nil
                self.clearNotes()
                self.report("AX1-104 · MIDI input disconnected. Choose a source to resume.")
            }
            if let saved = UserDefaults.standard.object(forKey: "midiSource") as? NSNumber,
               sources.contains(where: { $0.id == saved.int32Value }) {
                selectSource(saved.int32Value)
            }
        } catch { report(error.localizedDescription) }
    }

    func selectSource(_ id: Int32?) {
        guard sourceID != id else { return }
        clearNotes()
        do {
            try midi?.select(id)
            sourceID = midi?.selectedSourceID
            if let sourceID { UserDefaults.standard.set(sourceID, forKey: "midiSource") }
            else { UserDefaults.standard.removeObject(forKey: "midiSource") }
            recent = "Waiting for input"
        } catch {
            sourceID = midi?.selectedSourceID
            report(error.localizedDescription)
        }
    }

    func savePatch(_ next: BridgeConfig) -> Bool {
        guard !live else { return false }
        do {
            var updated = next
            updated.host = config.host
            updated.universe = config.universe
            try updated.validated(requireHost: false)
            stopDemo()
            clearNotes()
            if let look = engine.baseLook, !updated.looks.contains(where: { $0.id == look && !$0.flash }) {
                engine.selectLook(nil)
            }
            config = updated
            persist()
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }

    @discardableResult func saveDestination() -> Bool {
        guard !live else { return false }
        let cleaned = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(universe.trimmingCharacters(in: .whitespacesAndNewlines)), (0...32767).contains(number) else {
            report("AX1-203 · Universe must be from 0 to 32767.")
            return false
        }
        do {
            var updated = config
            updated.host = cleaned
            updated.universe = number
            try updated.validated(requireHost: outputMode == .artnet)
            config = updated
            persist()
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "config.v1")
        }
    }

    func clearNotes() {
        midiStarts.removeAll()
        engine.clearNotes()
        pads.removeAll()
        if activeMode == .usb && !usbStarting { tick() }
    }

    private func receive(_ event: MIDIEvent) {
        let channel: Int
        switch event {
        case let .noteOn(ch, _, _), let .noteOff(ch, _), let .controlChange(ch, _, _): channel = ch
        case .clock:
            lastClock = DispatchTime.now().uptimeNanoseconds
            clockRunning = true
            clockBeats += 1.0 / 24
            return
        case let .locate(sixteenths):
            clockBeats = Double(max(0, sixteenths)) / 4
            return
        case .stop:
            clockRunning = false
            return
        }
        guard config.midiChannel == 0 || config.midiChannel == channel else { return }
        switch event {
        case let .noteOn(_, note, velocity):
            recent = "CH \(channel)  ·  NOTE \(note)  ·  VEL \(velocity)"
            if let target = learning, velocity > 0 {
                learned = LearnedNote(fixtureID: target, note: note)
                learning = nil
                return
            }
            if velocity > 0, let look = config.look(forNote: note) {
                guard !demo else { return }
                if look.flash {
                    midiStarts[NoteKey(channel: channel, note: note)] = DispatchTime.now().uptimeNanoseconds
                    engine.holdFlash(look.id)
                    recent = "CH \(channel)  ·  FLASH  ·  \(look.name)"
                } else {
                    engine.selectLook(look.id)
                    recent = "CH \(channel)  ·  LOOK  ·  \(look.name)"
                }
                if activeMode == .usb && !usbStarting { tick() }
                return
            }
            guard !engine.blackout, !demo, !usbStarting,
                  config.fixtures.contains(where: { $0.enabled && $0.noteRange.contains(Int(note)) }) else { return }
            midiStarts[NoteKey(channel: channel, note: note)] = DispatchTime.now().uptimeNanoseconds
            engine.noteOn(note, velocity: velocity, channel: channel)
            if activeMode == .usb { tick() }
        case let .noteOff(_, note):
            releaseMIDI(NoteKey(channel: channel, note: note))
        case .clock, .locate, .stop:
            return
        case let .controlChange(_, control, value):
            if demo { return }
            if control == 120 || control == 123 {
                midiStarts = midiStarts.filter { $0.key.channel != channel }
            }
            engine.controlChange(control, value: value, config: config, channel: channel)
            if Int(control) == config.masterCC || config.fixtures.contains(where: { $0.levelCC == Int(control) }) {
                recent = "CH \(channel)  ·  CC \(control)  ·  \(value)"
            }
            if activeMode == .usb && !usbStarting { tick() }
        }
    }

    private func releaseMIDI(_ key: NoteKey) {
        guard let start = midiStarts[key] else { return }
        // A rapid tap must survive at least one nominal 30 Hz output frame.
        let deadline = start + 50_000_000
        if DispatchTime.now().uptimeNanoseconds < deadline {
            DispatchQueue.main.asyncAfter(deadline: DispatchTime(uptimeNanoseconds: deadline)) { [weak self] in
                guard let self, self.midiStarts[key] == start else { return }
                self.finishRelease(key)
            }
        } else {
            finishRelease(key)
        }
    }

    private func finishRelease(_ key: NoteKey) {
        midiStarts[key] = nil
        if let look = config.look(forNote: key.note), look.flash {
            engine.releaseFlash(look.id)
            if activeMode == .usb && !usbStarting { tick() }
            return
        }
        engine.noteOff(key.note, channel: key.channel)
        if activeMode == .usb { tick() }
    }

    func tap(_ fixture: FixturePatch) {
        guard !engine.blackout, !usbStarting, fixture.enabled else { return }
        stopDemo()
        if pads.remove(fixture.id) != nil {
            for note in fixture.noteRange { engine.noteOff(UInt8(clamping: note), channel: 0) }
        } else {
            pads.insert(fixture.id)
            for note in fixture.noteRange { engine.noteOn(UInt8(clamping: note), velocity: 127, channel: 0) }
        }
        recent = "PAD  ·  NOTE \(fixture.note)"
        if activeMode == .usb { tick() }
    }

    /// Picks a look from the console, the same as playing its note. Nil returns fixtures to their patch settings.
    func selectLook(_ id: UUID?) {
        engine.selectLook(id)
        recent = id.flatMap { id in config.looks.first { $0.id == id } }.map { "LOOK  ·  \($0.name)" } ?? "LOOK  ·  PATCH SETTINGS"
        if activeMode == .usb && !usbStarting { tick() }
    }

    /// Maximum brightness for one fixture (0–100 %). Works while output is armed and is saved straight away.
    func setFixtureMax(_ id: UUID, _ value: Int) {
        guard let index = config.fixtures.firstIndex(where: { $0.id == id }) else { return }
        config.fixtures[index].maxLevel = UInt8(clamping: min(100, max(0, value)))
        persist()
        if activeMode == .usb && !usbStarting { tick() }
    }

    /// Maximum brightness for a group (0–100 %). Works while output is armed and is saved straight away.
    func setGroupMax(_ id: UUID, _ value: Int) {
        guard let index = config.groups.firstIndex(where: { $0.id == id }) else { return }
        config.groups[index].maxLevel = UInt8(clamping: min(100, max(0, value)))
        persist()
        if activeMode == .usb && !usbStarting { tick() }
    }

    /// Warmth (kelvin) for a group that fixes warmth. Works while output is armed and is saved straight away.
    func setGroupWarmth(_ id: UUID, _ kelvin: Int) {
        guard let index = config.groups.firstIndex(where: { $0.id == id }), config.groups[index].warmth != nil else { return }
        config.groups[index].warmth = FixtureGroup.clampedWarmth(kelvin)
        persist()
        if activeMode == .usb && !usbStarting { tick() }
    }

    func setMaster(_ value: UInt8) {
        engine.setMaster(value)
        if activeMode == .usb && !usbStarting { tick() }
    }

    /// Darkens one group's lights (or brings them back). MIDI keeps being tracked underneath. Not saved.
    func toggleGroupBlackout(_ id: UUID) {
        engine.setGroupBlackout(id, !engine.blackedOutGroups.contains(id))
        if live && !usbStarting { tick() }
    }

    func toggleBlackout() {
        if !engine.blackout {
            stopDemo()
            clearNotes()
        }
        engine.setBlackout(!engine.blackout)
        if engine.blackout && live { tick() }
    }

    /// Lights each enabled fixture in turn. Disarmed, it shows on the deck only; armed (live preview), the
    /// frames go out over DMX so every tube can be checked. MIDI is ignored while it runs.
    func toggleDemo() {
        if demo { stopDemo(); return }
        guard !engine.blackout, !usbStarting, !usbClosing else { return }
        clearNotes()
        demo = true
        demoStep = 0
        playDemoStep()
        let timer = Timer(timeInterval: live ? 0.5 : 0.30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.playDemoStep() }
        }
        demoTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func playDemoStep() {
        let active = config.fixtures.filter(\.enabled)
        guard demo && !active.isEmpty else { return }
        clearNotes()
        for note in active[demoStep % active.count].noteRange {
            engine.noteOn(UInt8(clamping: note), velocity: 127, channel: 0)
        }
        if active.count > 1 {
            for note in active[(demoStep + active.count - 1) % active.count].noteRange {
                engine.noteOn(UInt8(clamping: note), velocity: 34, channel: 0)
            }
        }
        demoStep = (demoStep + 1) % active.count
        recent = live ? "LIVE PREVIEW  ·  \(active[(demoStep + active.count - 1) % active.count].name.uppercased())" : "PREVIEW  ·  RUNNING"
    }

    func stopDemo() {
        guard demo else { return }
        demoTimer?.invalidate()
        demoTimer = nil
        demo = false
        clearNotes()
        recent = "Preview stopped"
    }

    func refreshUSB() {
        guard !live, !usbClosing, outputMode == .usb else { return }
        let found = OpenDMXOutput.availablePorts()
        if found != usbPorts { usbPorts = found }
        let selection = found.contains(usbPath) ? usbPath : (found.count == 1 ? found[0] : "")
        if selection != usbPath { usbPath = selection }
    }

    func toggleLive() {
        if live { disarm(); return }
        stopDemo()
        clearNotes()
        learning = nil
        issue = nil
        do {
            try config.validated(requireHost: false)
            switch outputMode {
            case .artnet:
                guard saveDestination() else { return }
                try artnet.arm(host: config.host, universe: config.universe)
            case .usb:
                refreshUSB()
                guard !usbPath.isEmpty else {
                    report("AX1-105 · Choose your Open DMX USB interface. Reconnect it if it’s missing.")
                    return
                }
                try usb.arm(path: usbPath)
                usbStarting = true
            }
            activeMode = outputMode
            live = true
            // Every enabled fixture gets frames straight away: its colour and effect settings, with the dimmer
            // at 0 until MIDI (or a click on the deck) sets a level.
            tick()
            guard live else { return }
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } catch {
            report(error.localizedDescription)
        }
    }

    private func tick() {
        guard live, let activeMode else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        if clockRunning, now &- lastClock > 500_000_000 { clockRunning = false }
        let motion = engine.activeMotion(config)
        if !clockRunning {
            // Without clock a new motion starts from its first step, at its own tempo. Colour changes under it don't restart it.
            if motion != lastShownMotion { freeBeats = 0 }
            else if lastTick != 0, now > lastTick, let motion { freeBeats += Double(now - lastTick) / 1e9 * max(1, motion.bpm) / 60 }
        }
        lastShownMotion = motion
        lastTick = now
        if motion != nil { engine.setBeats(clockRunning ? clockBeats : freeBeats) }
        do {
            let frame = engine.frame(config: config)
            switch activeMode {
            case .artnet: try artnet.send(frame)
            case .usb: try usb.send(frame)
            }
        } catch {
            disarm(tryZero: false)
            report(error.localizedDescription)
        }
    }

    private func disarm(tryZero: Bool = true) {
        timer?.invalidate()
        timer = nil
        lastTick = 0
        let previous = activeMode
        activeMode = nil
        live = false
        stopDemo()
        clearNotes()
        if previous == .artnet {
            if tryZero {
                do { try artnet.send([UInt8](repeating: 0, count: 512)) }
                catch { report(error.localizedDescription) }
            }
            artnet.disarm()
        }
        if previous == .usb {
            usbStarting = false
            usbClosing = true
            usb.disarm(blackout: tryZero)
        }
    }

    func prepareToQuit(_ onDrained: @escaping () -> Void) -> Bool {
        updateTask?.cancel()
        usbScanTimer?.invalidate()
        usbScanTimer = nil
        disarm()
        stopDemo()
        guard usbClosing else { return false }
        quitReply = onDrained
        return true
    }

    func checkForUpdates() {
        guard updateTask == nil else { return }
        if issue?.message.hasPrefix("AX1-4") == true { dismissError() }
        updateStatus = .checking
        updateTask = Task { [weak self] in
            guard let self else { return }
            defer { self.updateTask = nil }
            do {
                let result = try await UpdateChecker.check(currentVersion: BuildInfo.version)
                try Task.checkCancellation()
                self.updateStatus = .checked(result)
            } catch is CancellationError {
                self.updateStatus = nil
            } catch {
                self.updateStatus = nil
                self.report(error.localizedDescription)
            }
        }
    }

    func dismissUpdateStatus() { updateStatus = nil }

    /// Downloads the available release, replaces this app with it and relaunches.
    /// Quitting goes through prepareToQuit, so live output is disarmed and blacked out first.
    func installUpdate() {
        guard updateTask == nil, case .checked(.available(let version, let download)) = updateStatus else { return }
        if issue?.message.hasPrefix("AX1-4") == true { dismissError() }
        guard let download else {
            report(UpdateInstaller.InstallError.noDownload.localizedDescription)
            return
        }
        let available = UpdateStatus.checked(.available(version: version, download: download))
        updateStatus = .installing(version)
        updateTask = Task { [weak self] in
            guard let self else { return }
            do {
                let app = try await UpdateInstaller.install(version: version, from: download, installed: BuildInfo.version)
                self.updateTask = nil
                do {
                    try UpdateInstaller.relaunch(app, version: version)
                } catch {
                    // The new version is already on disk; it opens next time the app starts.
                    self.updateStatus = nil
                    self.report(error.localizedDescription)
                    return
                }
                NSApp.terminate(nil)
            } catch is CancellationError {
                self.updateTask = nil
                self.updateStatus = available
            } catch {
                self.updateTask = nil
                self.updateStatus = available
                self.report(error.localizedDescription)
            }
        }
    }

    func openReleasePage() {
        if !NSWorkspace.shared.open(UpdateChecker.releasesURL) {
            report("AX1-407 · Could not open the GitHub Releases page in your default browser.")
        }
    }

    func report(_ message: String) { issue = ConsoleIssue(message: message) }
    func dismissError() { issue = nil }
}

enum BuildInfo {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0"
    static let number = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    static var date: String {
        guard let encoded = Bundle.main.object(forInfoDictionaryKey: "AX1BuildDate") as? String,
              let date = ISO8601DateFormatter().date(from: encoded) else { return "Development build" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
