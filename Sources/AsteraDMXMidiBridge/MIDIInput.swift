import CoreMIDI
import Foundation

struct MIDISource: Identifiable, Equatable {
    let id: Int32
    let name: String
}

enum MIDIEvent: Equatable, Sendable {
    case noteOn(channel: Int, note: UInt8, velocity: UInt8)
    case noteOff(channel: Int, note: UInt8)
    case controlChange(channel: Int, control: UInt8, value: UInt8)
    /// MIDI clock: 24 pulses per beat.
    case clock
    /// Start (position 0) or Song Position Pointer, in 16ths.
    case locate(sixteenths: Int)
    case stop

    fileprivate init?(_ message: MIDIUniversalMessage) {
        if message.type == .system {
            switch message.system.status.rawValue {
            case 0xF8: self = .clock
            case 0xFA: self = .locate(sixteenths: 0)
            case 0xF2: self = .locate(sixteenths: Int(message.system.songPositionPointer))
            case 0xFC: self = .stop
            default: return nil
            }
            return
        }
        guard message.type == .channelVoice1 else { return nil }
        let voice = message.channelVoice1
        let channel = Int(voice.channel) + 1
        switch voice.status {
        case .noteOn where voice.note.velocity > 0:
            self = .noteOn(channel: channel, note: voice.note.number, velocity: voice.note.velocity)
        case .noteOn, .noteOff:
            self = .noteOff(channel: channel, note: voice.note.number)
        case .controlChange:
            self = .controlChange(channel: channel, control: voice.controlChange.index,
                                  value: voice.controlChange.data)
        default:
            return nil
        }
    }
}

enum MIDIInputError: LocalizedError {
    case createClient(OSStatus)
    case createPort(OSStatus)
    case sourceUnavailable
    case connectSource(OSStatus)
    case disconnectSource(OSStatus)

    var errorDescription: String? {
        switch self {
        case .createClient(let status):
            return "AX1-301: Core MIDI could not start (\(status))."
        case .createPort(let status):
            return "AX1-302: Core MIDI could not open an input port (\(status))."
        case .sourceUnavailable:
            return "AX1-303: The selected MIDI input is unavailable."
        case .connectSource(let status):
            return "AX1-304: The selected MIDI input could not be connected (\(status))."
        case .disconnectSource(let status):
            return "AX1-305: The previous MIDI input could not be disconnected (\(status))."
        }
    }
}

@MainActor
final class MIDIInput {
    private var client: MIDIClientRef = 0
    private var port: MIDIPortRef = 0
    private var endpoints: [Int32: MIDIEndpointRef] = [:]
    private var selectedEndpoint: MIDIEndpointRef = 0
    private var selectionGeneration: UInt = 0
    private(set) var selectedSourceID: Int32?
    private(set) var sources: [MIDISource] = []

    var onSourcesChanged: (([MIDISource]) -> Void)?
    var onMessage: ((MIDIEvent) -> Void)?
    var onSelectionLost: (() -> Void)?

    init() throws {
        let clientStatus = MIDIClientCreateWithBlock("AsteraDMXMidiBridge" as CFString, &client,
                                                      Self.notificationBlock { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.refreshSources() }
        })
        guard clientStatus == noErr else { throw MIDIInputError.createClient(clientStatus) }

        let portStatus = MIDIInputPortCreateWithProtocol(
            client, "AsteraDMXMidiBridge Input" as CFString, ._1_0, &port,
            Self.receiveBlock { [weak self] generation, events in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.selectedSourceID != nil,
                          generation == self.selectionGeneration else { return }
                    for event in events { self.onMessage?(event) }
                }
            }
        )
        guard portStatus == noErr else { throw MIDIInputError.createPort(portStatus) }
        refreshSources()
    }

    deinit {
        if port != 0 { MIDIPortDispose(port) }
        if client != 0 { MIDIClientDispose(client) }
    }

    func select(_ id: Int32?) throws {
        guard id != selectedSourceID else { return }
        let endpoint = id.flatMap { endpoints[$0] }
        if id != nil, endpoint == nil { throw MIDIInputError.sourceUnavailable }

        if selectedEndpoint != 0 {
            let status = MIDIPortDisconnectSource(port, selectedEndpoint)
            guard status == noErr else { throw MIDIInputError.disconnectSource(status) }
        }
        selectedSourceID = nil
        selectedEndpoint = 0
        selectionGeneration &+= 1
        guard let endpoint else { return }

        // RefCon identifies the connection generation and is never dereferenced.
        let context = UnsafeMutableRawPointer(bitPattern: selectionGeneration)
        let status = MIDIPortConnectSource(port, endpoint, context)
        guard status == noErr else { throw MIDIInputError.connectSource(status) }
        selectedEndpoint = endpoint
        selectedSourceID = id
    }

    private func refreshSources() {
        var currentEndpoints: [Int32: MIDIEndpointRef] = [:]
        var currentSources: [MIDISource] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { continue }
            var offline: Int32 = 0
            if MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline) == noErr,
               offline != 0 { continue }

            var id: Int32 = 0
            guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &id) == noErr,
                  currentEndpoints[id] == nil else { continue }
            currentEndpoints[id] = endpoint
            var displayName: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &displayName)
            let name = displayName.map { $0.takeRetainedValue() as String } ?? "MIDI input \(index + 1)"
            currentSources.append(MIDISource(id: id, name: name))
        }

        let sourcesChanged = currentSources != sources
        endpoints = currentEndpoints
        sources = currentSources
        if let selectedSourceID, currentEndpoints[selectedSourceID] != selectedEndpoint {
            MIDIPortDisconnectSource(port, selectedEndpoint)
            self.selectedSourceID = nil
            selectedEndpoint = 0
            selectionGeneration &+= 1
            onSelectionLost?()
        }
        if sourcesChanged { onSourcesChanged?(sources) }
    }

    private nonisolated static func notificationBlock(
        _ notify: @escaping @Sendable () -> Void
    ) -> MIDINotifyBlock {
        { notification in
            switch notification.pointee.messageID {
            case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved, .msgPropertyChanged:
                notify()
            default:
                break
            }
        }
    }

    private nonisolated static func receiveBlock(
        _ deliver: @escaping @Sendable (UInt, [MIDIEvent]) -> Void
    ) -> MIDIReceiveBlock {
        { list, context in
            guard let context else { return }
            var events: [MIDIEvent] = []
            withUnsafeMutablePointer(to: &events) { buffer in
                MIDIEventListForEachEvent(list, { visitorContext, _, message in
                    guard let event = MIDIEvent(message), let visitorContext else { return }
                    visitorContext.assumingMemoryBound(to: [MIDIEvent].self).pointee.append(event)
                }, buffer)
            }
            if !events.isEmpty { deliver(UInt(bitPattern: context), events) }
        }
    }
}
