import Foundation

/// One scanned room. Rooms on the same floor share one coordinate system.
public struct Room: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var plan: FloorPlan
    /// The raw scan, kept so plans can be rebuilt when the plan logic improves.
    public var scan: [ScannedItem]?

    public init(name: String, plan: FloorPlan, scan: [ScannedItem]? = nil) {
        self.name = name
        self.plan = plan
        self.scan = scan
    }
}

public struct Floor: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var rooms: [Room]

    public init(name: String, rooms: [Room] = []) {
        self.name = name
        self.rooms = rooms
    }

    /// Sum of room areas (inside the walls), in square metres.
    public var netArea: Double { rooms.map(\.plan.area).reduce(0, +) }

    public var centroid: Point2 {
        let mids = rooms.flatMap { $0.plan.walls.map(\.line.midpoint) }
        guard !mids.isEmpty else { return .zero }
        return mids.reduce(.zero, +) / Double(mids.count)
    }

    /// Scales every room on the floor so that one wall measures `length` metres.
    public func calibrated(room: Int, wall: Int, to length: Double) -> Floor {
        guard rooms.indices.contains(room), rooms[room].plan.walls.indices.contains(wall), length > 0 else { return self }
        let current = rooms[room].plan.walls[wall].line.length
        guard current > 0 else { return self }
        let factor = length / current, c = centroid
        var floor = self
        for i in floor.rooms.indices {
            floor.rooms[i].plan = rooms[i].plan.scaled(by: factor, about: c)
        }
        return floor
    }

    /// "Bedroom", "Bedroom 2", ... so names stay unique on the floor.
    public func uniqueRoomName(_ base: String) -> String {
        let names = Set(rooms.map(\.name))
        guard names.contains(base) else { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}

public struct HouseProject: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var address: String
    public var owner: String
    public var preparedBy: String
    public var unit: LengthUnit
    /// Movable furniture is usually left off permit plans; fixtures and stairs are always drawn.
    public var showFurniture: Bool
    /// Drawn thickness of walls between two scanned rooms (5" by default).
    public var interiorWallThickness: Double
    /// Drawn thickness of outside walls (10" by default).
    public var exteriorWallThickness: Double
    public var created: Date
    public var floors: [Floor]

    public init(name: String, address: String = "", owner: String = "", preparedBy: String = "",
                unit: LengthUnit = .inches, showFurniture: Bool = false,
                interiorWallThickness: Double = HouseProject.defaultInteriorWall,
                exteriorWallThickness: Double = HouseProject.defaultExteriorWall,
                created: Date = Date(), floors: [Floor] = []) {
        self.name = name
        self.address = address
        self.owner = owner
        self.preparedBy = preparedBy
        self.unit = unit
        self.showFurniture = showFurniture
        self.interiorWallThickness = interiorWallThickness
        self.exteriorWallThickness = exteriorWallThickness
        self.created = created
        self.floors = floors
    }

    public static let defaultInteriorWall = 5 * 0.0254
    public static let defaultExteriorWall = 10 * 0.0254

    private enum CodingKeys: String, CodingKey {
        case id, name, address, owner, preparedBy, unit, showFurniture, interiorWallThickness, exteriorWallThickness, created, floors
    }

    // Wall thicknesses are optional so houses saved by earlier versions still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        address = try c.decode(String.self, forKey: .address)
        owner = try c.decode(String.self, forKey: .owner)
        preparedBy = try c.decode(String.self, forKey: .preparedBy)
        unit = try c.decode(LengthUnit.self, forKey: .unit)
        showFurniture = try c.decode(Bool.self, forKey: .showFurniture)
        interiorWallThickness = try c.decodeIfPresent(Double.self, forKey: .interiorWallThickness) ?? Self.defaultInteriorWall
        exteriorWallThickness = try c.decodeIfPresent(Double.self, forKey: .exteriorWallThickness) ?? Self.defaultExteriorWall
        created = try c.decode(Date.self, forKey: .created)
        floors = try c.decode([Floor].self, forKey: .floors)
    }

    public static let suggestedFloorNames = ["Basement", "First Floor", "Second Floor", "Third Floor", "Attic"]
}

extension LengthUnit {
    public func formatArea(_ squareMetres: Double) -> String {
        switch self {
        case .millimetres: return String(format: "%.1f m2", squareMetres)
        case .inches: return String(format: "%.0f sq ft", squareMetres / (0.3048 * 0.3048))
        }
    }
}
