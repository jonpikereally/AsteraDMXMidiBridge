import Foundation

/// A named set of fixtures with its own maximum brightness. A fixture can be in several groups;
/// its output is scaled by its own maximum and by every group it is in.
public struct FixtureGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var fixtureIDs: [UUID]
    /// Maximum brightness, 0–100 percent.
    public var maxLevel: UInt8

    public init(id: UUID = UUID(), name: String, fixtureIDs: [UUID] = [], maxLevel: UInt8 = 100) {
        self.id = id
        self.name = name
        self.fixtureIDs = fixtureIDs
        self.maxLevel = min(maxLevel, 100)
    }

    private enum CodingKeys: String, CodingKey { case id, name, fixtureIDs, maxLevel }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            name: try values.decode(String.self, forKey: .name),
            fixtureIDs: try values.decodeIfPresent([UUID].self, forKey: .fixtureIDs) ?? [],
            maxLevel: min(try values.decodeIfPresent(UInt8.self, forKey: .maxLevel) ?? 100, 100)
        )
    }
}
