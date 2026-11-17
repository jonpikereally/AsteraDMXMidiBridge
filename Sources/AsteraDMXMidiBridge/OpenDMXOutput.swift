import AX1FTDI
import Darwin
import Foundation

enum OpenDMXError: LocalizedError {
    case portUnavailable
    case open(Int32)
    case configure(Int32)
    case frame(Int32)
    case invalidFrame
    case notArmed
    case busy
    case directOpen(Int32)
    case directFrame(Int32)

    var errorDescription: String? {
        switch self {
        case .portUnavailable:
            return "AX1-312: Select a connected ENTTEC Open DMX USB interface."
        case .open(let status):
            return "AX1-313: The Open DMX USB port could not be opened (\(String(cString: strerror(status))))."
        case .configure(let status):
            return "AX1-314: The USB serial driver could not set up DMX512 (\(String(cString: strerror(status))))."
        case .frame(let status):
            return "AX1-315: The Open DMX USB stream stopped (\(String(cString: strerror(status))))."
        case .invalidFrame:
            return "AX1-316: Open DMX USB expected exactly 512 DMX slots."
        case .notArmed:
            return "AX1-317: Arm USB output before sending DMX."
        case .busy:
            return "AX1-318: Wait for the previous USB stream to close before arming."
        case .directOpen(let status):
            return "AX1-319: Could not open the ENTTEC through direct USB (\(Self.directError(status)))."
        case .directFrame(let status):
            return "AX1-320: Direct USB stopped sending DMX (\(Self.directError(status)))."
        }
    }

    private static func directError(_ status: Int32) -> String {
        ax1_ftdi_error(status).map { String(cString: $0) } ?? "status \(status)"
    }
}

private enum OpenDMXDevice {
    static let directPrefix = "ftdi:"

    static func location(for identifier: String) -> UInt32? {
        guard identifier.hasPrefix(directPrefix) else { return nil }
        return UInt32(identifier.dropFirst(directPrefix.count), radix: 16)
    }

    static func identifier(for location: UInt32) -> String {
        directPrefix + String(location, radix: 16)
    }
}

@MainActor
final class OpenDMXOutput {
    private var session: OpenDMXSession?
    var onReady: (() -> Void)?
    var onError: ((Error) -> Void)?
    var onStopped: (() -> Void)?

    deinit { session?.stop(blackout: true) }

    static func availablePorts() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        let serial = names.filter { $0.hasPrefix("cu.usbserial") }.sorted().map { "/dev/" + $0 }
        return serial + directLocations().map(OpenDMXDevice.identifier)
    }

    private static func directLocations() -> [UInt32] {
        var locations = [UInt32](repeating: 0, count: 32)
        let count = locations.withUnsafeMutableBufferPointer {
            Int(ax1_ftdi_list($0.baseAddress, Int32($0.count)))
        }
        guard count > 0 else { return [] }
        return Array(Set(locations.prefix(count))).sorted()
    }

    static func label(for identifier: String, among ports: [String]) -> String {
        if let location = OpenDMXDevice.location(for: identifier) {
            let directCount = ports.lazy.filter { OpenDMXDevice.location(for: $0) != nil }.count
            return directCount > 1
                ? "Open DMX direct · \(String(location, radix: 16).uppercased())"
                : "Open DMX (direct USB)"
        }
        return identifier.replacingOccurrences(of: "/dev/cu.", with: "")
    }

    // Opening and configuring the port happen on the worker. onReady reports the first frame
    // written to the USB driver, and onError reports an asynchronous setup or write failure.
    func arm(path: String) throws {
        guard session == nil else { throw OpenDMXError.busy }
        guard Self.availablePorts().contains(path) else { throw OpenDMXError.portUnavailable }
        let session = OpenDMXSession()
        self.session = session

        let thread = Thread { [weak self, session] in
            var error: Error?
            do {
                try session.run(path: path) { [weak self] in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.session === session, session.isRunning else { return }
                        self.onReady?()
                    }
                }
            } catch let issue {
                error = issue
            }
            DispatchQueue.main.async { [weak self, error] in
                guard let self, self.session === session else { return }
                self.session = nil
                if let error { self.onError?(error) }
                self.onStopped?()
            }
        }
        thread.name = "AX1 Open DMX USB"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    // Replace the latest frame without blocking the UI. The serial worker sets the wire cadence.
    func send(_ slots: [UInt8]) throws {
        guard slots.count == 512 else { throw OpenDMXError.invalidFrame }
        guard let session, session.update(slots) else { throw OpenDMXError.notArmed }
    }

    func disarm(blackout: Bool = true) {
        session?.stop(blackout: blackout)
    }
}

// The serial descriptor belongs to its worker thread. The lock protects only the frame mailbox.
private final class OpenDMXSession: @unchecked Sendable {
    private static let off = [UInt8](repeating: 0, count: 513)
    private static let frameInterval: UInt64 = 1_000_000_000 / 30
    private static let wireGuard: UInt64 = 25_000_000 // 513 slots × 11 bits / 250 kbit/s plus USB margin
    private static let ioTimeout: UInt64 = 150_000_000
    // IOKit's IOSSIOSPEED is the C macro _IOW('T', 2, speed_t), which Swift cannot import.
    private static let setExactBaud = 0x8000_5402 | (UInt(MemoryLayout<speed_t>.size) << 16)

    private let lock = NSLock()
    private var latest = off
    private var stopping = false
    private var remainingBlackoutFrames = 0

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !stopping
    }

    func update(_ slots: [UInt8]) -> Bool {
        let frame = [0] + slots // Null DMX start code, then 512 channel bytes.
        lock.lock()
        defer { lock.unlock() }
        guard !stopping else { return false }
        latest = frame
        return true
    }

    func stop(blackout: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopping else { return }
        stopping = true
        remainingBlackoutFrames = blackout ? 3 : 0
    }

    func run(path: String, ready: () -> Void) throws {
        guard isRunning else { return }
        if let location = OpenDMXDevice.location(for: path) {
            try runDirectUSB(location: location, ready: ready)
        } else {
            try runSerial(path: path, ready: ready)
        }
    }

    private func runDirectUSB(location: UInt32, ready: () -> Void) throws {
        var handle: OpaquePointer?
        let status = ax1_ftdi_open(location, &handle)
        guard status == 0, let handle else { throw OpenDMXError.directOpen(status) }
        defer { ax1_ftdi_close(handle) }
        try stream(ready: ready) { frame in
            let status = frame.withUnsafeBufferPointer {
                ax1_ftdi_write(handle, $0.baseAddress, Int32($0.count))
            }
            guard status == 0 else { throw OpenDMXError.directFrame(status) }
        }
    }

    private func runSerial(path: String, ready: () -> Void) throws {
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw OpenDMXError.open(errno) }
        defer { close(fd) }
        try Self.configure(fd)
        try stream(ready: ready) { try Self.transmit($0, on: fd) }
    }

    private func stream(ready: () -> Void, transmit: ([UInt8]) throws -> Void) throws {
        var first = true
        while let frame = takeFrame() {
            let frameStart = Self.now
            try transmit(frame)
            if first {
                first = false
                ready()
            }
            Self.sleep(until: frameStart + Self.frameInterval)
        }
    }

    private func takeFrame() -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }
        if !stopping { return latest }
        guard remainingBlackoutFrames > 0 else { return nil }
        remainingBlackoutFrames -= 1
        return Self.off
    }

    private static func configure(_ fd: Int32) throws {
        var metadata = stat()
        guard fstat(fd, &metadata) == 0 else { throw OpenDMXError.open(errno) }
        guard metadata.st_mode & S_IFMT == S_IFCHR else { throw OpenDMXError.open(ENOTTY) }
        guard ioctl(fd, TIOCEXCL) == 0 else { throw OpenDMXError.open(errno) }

        var line = termios()
        guard tcgetattr(fd, &line) == 0 else { throw OpenDMXError.configure(errno) }
        cfmakeraw(&line)
        let lineFlags = tcflag_t(CSIZE | PARENB | PARODD | CRTSCTS | HUPCL)
        line.c_cflag &= ~lineFlags
        line.c_cflag |= tcflag_t(CS8 | CSTOPB | CLOCAL | CREAD)
        line.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
        guard cfsetspeed(&line, speed_t(B115200)) == 0,
              tcsetattr(fd, TCSANOW, &line) == 0 else { throw OpenDMXError.configure(errno) }
        var baud: speed_t = 250_000
        guard ioctl(fd, setExactBaud, &baud) == 0 else { throw OpenDMXError.configure(errno) }
        var inactiveModemLines: Int32 = TIOCM_RTS | TIOCM_DTR
        guard ioctl(fd, TIOCMBIC, &inactiveModemLines) == 0,
              tcflush(fd, TCIOFLUSH) == 0 else { throw OpenDMXError.configure(errno) }
    }

    private static func transmit(_ frame: [UInt8], on fd: Int32) throws {
        guard ioctl(fd, TIOCSBRK) == 0 else { throw OpenDMXError.frame(errno) }
        sleep(until: now + 180_000)
        guard ioctl(fd, TIOCCBRK) == 0 else { throw OpenDMXError.frame(errno) }
        sleep(until: now + 20_000)
        try write(frame, to: fd)
        try waitForDriverQueue(on: fd)
        // The driver can report its queue empty while the FTDI chip is still shifting bytes.
        // Leave time for a full wire frame before the next BREAK or closing the USB port.
        sleep(until: now + wireGuard)
    }

    private static func write(_ frame: [UInt8], to fd: Int32) throws {
        let deadline = now + ioTimeout
        try frame.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
                if count > 0 {
                    offset += count
                    continue
                }
                let status = count < 0 ? errno : EAGAIN
                guard status == EAGAIN || status == EINTR else { throw OpenDMXError.frame(status) }
                guard now < deadline else { throw OpenDMXError.frame(ETIMEDOUT) }
                sleep(until: now + 1_000_000)
            }
        }
    }

    private static func waitForDriverQueue(on fd: Int32) throws {
        let deadline = now + ioTimeout
        while true {
            var left: Int32 = 0
            guard ioctl(fd, TIOCOUTQ, &left) == 0 else { throw OpenDMXError.frame(errno) }
            if left == 0 { return }
            guard now < deadline else { throw OpenDMXError.frame(ETIMEDOUT) }
            sleep(until: now + 1_000_000)
        }
    }

    private static var now: UInt64 { DispatchTime.now().uptimeNanoseconds }

    private static func sleep(until deadline: UInt64) {
        while true {
            let current = now
            guard current < deadline else { return }
            let remaining = deadline - current
            var request = timespec(tv_sec: Int(remaining / 1_000_000_000),
                                   tv_nsec: Int(remaining % 1_000_000_000))
            if nanosleep(&request, nil) == 0 || errno != EINTR { return }
        }
    }
}
