import Foundation

/// The app's own floor plan model. Independent of RoomPlan so other capture modes can feed it later.
/// All lengths are in metres.
public struct FloorPlan: Codable, Equatable, Sendable {
    public var walls: [Wall]
    public var openings: [Opening]
    public var objects: [PlanObject]

    public init(walls: [Wall] = [], openings: [Opening] = [], objects: [PlanObject] = []) {
        self.walls = walls
        self.openings = openings
        self.objects = objects
    }

    /// Mean of wall midpoints; used to decide which side of a wall is "inside".
    public var centroid: Point2 {
        guard !walls.isEmpty else { return .zero }
        return walls.map(\.line.midpoint).reduce(.zero, +) / Double(walls.count)
    }

    public var bounds: (min: Point2, max: Point2)? {
        let pts = walls.flatMap { [$0.line.start, $0.line.end] }
            + objects.flatMap { $0.corners }
        guard let first = pts.first else { return nil }
        var lo = first, hi = first
        for p in pts {
            lo = Point2(min(lo.x, p.x), min(lo.y, p.y))
            hi = Point2(max(hi.x, p.x), max(hi.y, p.y))
        }
        return (lo, hi)
    }
}

public struct Wall: Codable, Equatable, Sendable {
    /// The scanned (room-side) face of the wall.
    public var line: Segment2
    /// Thickness drawn outward from `line`.
    public var thickness: Double

    public init(line: Segment2, thickness: Double = Wall.defaultThickness) {
        self.line = line
        self.thickness = thickness
    }

    public static let defaultThickness = 0.10
}

public enum OpeningKind: String, Codable, Sendable {
    case door
    case window
    case opening
}

public struct Opening: Codable, Equatable, Sendable {
    public var kind: OpeningKind
    /// Index into `FloorPlan.walls`.
    public var wallIndex: Int
    /// Distance of the opening's centre from the wall's start point.
    public var offset: Double
    public var width: Double

    public init(kind: OpeningKind, wallIndex: Int, offset: Double, width: Double) {
        self.kind = kind
        self.wallIndex = wallIndex
        self.offset = offset
        self.width = width
    }
}

/// A piece of furniture or fixture, drawn as a labelled rectangle.
public struct PlanObject: Codable, Equatable, Sendable {
    public var label: String
    public var center: Point2
    public var width: Double
    public var depth: Double
    /// Rotation of the width axis from +x, in radians.
    public var rotation: Double

    public init(label: String, center: Point2, width: Double, depth: Double, rotation: Double) {
        self.label = label
        self.center = center
        self.width = width
        self.depth = depth
        self.rotation = rotation
    }

    public var corners: [Point2] {
        let u = Point2(cos(rotation), sin(rotation))
        let v = u.perpendicular
        let hw = width / 2, hd = depth / 2
        return [
            center - u * hw - v * hd,
            center + u * hw - v * hd,
            center + u * hw + v * hd,
            center - u * hw + v * hd,
        ]
    }
}
