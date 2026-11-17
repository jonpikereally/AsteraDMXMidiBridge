import Foundation

public enum ArtNet {
    public static let port: UInt16 = 6454
    public static let portAddresses = 0...32767

    public static func dmx(universe: Int, sequence: UInt8, slots: [UInt8]) -> Data? {
        guard portAddresses.contains(universe), (2...512).contains(slots.count), slots.count.isMultiple(of: 2)
        else { return nil }

        // ArtDmx carries the zero start code implicitly. Only the channel values follow the header.
        var packet = Data("Art-Net\0".utf8)
        packet.append(contentsOf: [
            0x00, 0x50, // OpDmx, low byte first
            0x00, 0x0e, // Protocol version 14, high byte first
            sequence, 0x00,
            UInt8(truncatingIfNeeded: universe), UInt8(universe >> 8),
            UInt8(slots.count >> 8), UInt8(truncatingIfNeeded: slots.count),
        ])
        packet.append(contentsOf: slots)
        return packet
    }
}
