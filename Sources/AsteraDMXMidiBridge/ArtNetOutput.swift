import AX1Core
import Darwin
import Foundation

enum ArtNetOutputError: LocalizedError {
    case invalidDestination
    case invalidUniverse
    case socket(Int32)
    case notArmed
    case invalidFrame
    case send(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidDestination:
            return "AX1-306: Enter a unicast IPv4 address for the Art-Net destination."
        case .invalidUniverse:
            return "AX1-307: The Art-Net Port-Address must be in 0–32767."
        case .socket(let status):
            return "AX1-308: The Art-Net UDP socket could not be opened (\(String(cString: strerror(status))))."
        case .notArmed:
            return "AX1-309: Arm Art-Net output before sending DMX."
        case .invalidFrame:
            return "AX1-310: Art-Net expected exactly 512 DMX slots."
        case .send(let status):
            return "AX1-311: The Mac could not send the Art-Net packet (\(String(cString: strerror(status))))."
        }
    }
}

@MainActor
final class ArtNetOutput {
    private var descriptor: Int32 = -1
    private var target = sockaddr_in()
    private var universe = 0
    private var sequence: UInt8 = 1

    deinit {
        if descriptor >= 0 { close(descriptor) }
    }

    func arm(host: String, universe: Int) throws {
        guard (0...0x7fff).contains(universe) else { throw ArtNetOutputError.invalidUniverse }
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var address = in_addr()
        guard !host.contains("\0"), inet_pton(AF_INET, host, &address) == 1 else {
            throw ArtNetOutputError.invalidDestination
        }
        let firstOctet = UInt32(bigEndian: address.s_addr) >> 24
        guard (1...223).contains(firstOctet) else { throw ArtNetOutputError.invalidDestination }

        disarm()
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw ArtNetOutputError.socket(errno) }
        if fcntl(fd, F_SETFL, O_NONBLOCK) == -1 {
            let status = errno
            close(fd)
            throw ArtNetOutputError.socket(status)
        }

        if firstOctet != 127 {
            // Use the Art-Net source port on the network. Loopback uses an ephemeral port so a
            // local receiver such as QLC+ can listen on the same Mac.
            var source = Self.socketAddress(in_addr(s_addr: INADDR_ANY))
            let result = withUnsafePointer(to: &source) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if result != 0 {
                let status = errno
                close(fd)
                throw ArtNetOutputError.socket(status)
            }
        }

        descriptor = fd
        target = Self.socketAddress(address)
        self.universe = universe
    }

    // Success means the local kernel accepted the datagram. UDP has no receipt confirmation.
    func send(_ slots: [UInt8]) throws {
        guard descriptor >= 0 else { throw ArtNetOutputError.notArmed }
        guard slots.count == 512,
              let packet = ArtNet.dmx(universe: universe, sequence: sequence, slots: slots) else {
            throw ArtNetOutputError.invalidFrame
        }
        let result = withUnsafePointer(to: &target) { address in
            address.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                packet.withUnsafeBytes { buffer in
                    sendto(descriptor, buffer.baseAddress, buffer.count, 0, address,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard result == packet.count else { throw ArtNetOutputError.send(result < 0 ? errno : EIO) }
        sequence = sequence == .max ? 1 : sequence + 1
    }

    func disarm() {
        if descriptor >= 0 { close(descriptor) }
        descriptor = -1
    }

    private static func socketAddress(_ address: in_addr) -> sockaddr_in {
        var result = sockaddr_in()
        result.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        result.sin_family = sa_family_t(AF_INET)
        result.sin_port = ArtNet.port.bigEndian
        result.sin_addr = address
        return result
    }
}
