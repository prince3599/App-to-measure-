import Foundation

/// The app's own floor plan model. Independent of RoomPlan so other capture modes can feed it later.
/// All lengths are in metres.
public struct FloorPlan: Codable, Equatable, Sendable {
    public var walls: [Wall]
    public var openings: [Opening]
    public var objects: [PlanObject]
    /// Tallest scanned wall, or 0 when unknown.
    public var ceilingHeight: Double

    public init(walls: [Wall] = [], openings: [Opening] = [], objects: [PlanObject] = [], ceilingHeight: Double = 0) {
        self.walls = walls
        self.openings = openings
        self.objects = objects
        self.ceilingHeight = ceilingHeight
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

    /// Typical exterior wall (2x6 framing plus finishes). Interior walls get their real thickness when both rooms are scanned.
    public static let defaultThickness = 0.15
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
    /// 0 when unknown.
    public var height: Double
    /// Doors: hinge at the wall-end side of the opening instead of the wall-start side.
    public var hingeAtEnd: Bool
    /// Doors: swing out of the room instead of into it.
    public var swingsOut: Bool
    /// Doors: number of leaves (1 single, 2 double, ...).
    public var leaves: Int

    public init(kind: OpeningKind, wallIndex: Int, offset: Double, width: Double, height: Double = 0,
                hingeAtEnd: Bool = false, swingsOut: Bool = false, leaves: Int = 1) {
        self.kind = kind
        self.wallIndex = wallIndex
        self.offset = offset
        self.width = width
        self.height = height
        self.hingeAtEnd = hingeAtEnd
        self.swingsOut = swingsOut
        self.leaves = leaves
    }

    // Newer fields are optional so plans saved by earlier versions still load.
    private enum CodingKeys: String, CodingKey {
        case kind, wallIndex, offset, width, height, hingeAtEnd, swingsOut, leaves
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(OpeningKind.self, forKey: .kind)
        wallIndex = try c.decode(Int.self, forKey: .wallIndex)
        offset = try c.decode(Double.self, forKey: .offset)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 0
        hingeAtEnd = try c.decodeIfPresent(Bool.self, forKey: .hingeAtEnd) ?? false
        swingsOut = try c.decodeIfPresent(Bool.self, forKey: .swingsOut) ?? false
        leaves = try c.decodeIfPresent(Int.self, forKey: .leaves) ?? 1
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

extension FloorPlan {
    /// The room's floor outline, following walls around their joined corners.
    /// Falls back to the convex hull of the wall ends when the walls don't form a closed loop.
    public var outline: [Point2] {
        closedWallLoop ?? convexHull(walls.flatMap { [$0.line.start, $0.line.end] })
    }

    /// Floor area inside the walls, in square metres.
    public var area: Double {
        let p = outline
        guard p.count >= 3 else { return 0 }
        return abs(signedArea(p))
    }

    /// Where to put the room's label: the outline's centroid.
    public var labelPoint: Point2 {
        let p = outline
        let a = signedArea(p)
        guard p.count >= 3, abs(a) > 1e-9 else { return centroid }
        var c = Point2.zero
        for i in p.indices {
            let q0 = p[i], q1 = p[(i + 1) % p.count]
            c = c + (q0 + q1) * q0.cross(q1)
        }
        return c / (6 * a)
    }

    /// Overall interior width and depth, measured along the longest wall.
    public var size: (width: Double, depth: Double) {
        guard let longest = walls.max(by: { $0.line.length < $1.line.length }) else { return (0, 0) }
        let u = longest.line.direction, v = u.perpendicular
        let pts = outline
        guard let first = pts.first else { return (0, 0) }
        var lo = Point2(first.dot(u), first.dot(v)), hi = lo
        for p in pts {
            lo = Point2(min(lo.x, p.dot(u)), min(lo.y, p.dot(v)))
            hi = Point2(max(hi.x, p.dot(u)), max(hi.y, p.dot(v)))
        }
        return (hi.x - lo.x, hi.y - lo.y)
    }

    private var closedWallLoop: [Point2]? {
        guard walls.count >= 3 else { return nil }
        let corners = PlanGeometry.corners(of: walls, tolerance: 0.01)
        func partner(_ e: PlanGeometry.WallEnd) -> PlanGeometry.WallEnd? {
            for c in corners {
                if c.a == e { return c.b }
                if c.b == e { return c.a }
            }
            return nil
        }
        var points: [Point2] = []
        var wall = 0, forward = true
        var visited = Set<Int>()
        while !visited.contains(wall) {
            visited.insert(wall)
            let line = walls[wall].line
            points.append(forward ? line.start : line.end)
            guard let next = partner(PlanGeometry.WallEnd(wall: wall, atEnd: forward)) else { return nil }
            wall = next.wall
            forward = !next.atEnd
        }
        return wall == 0 && points.count >= 3 ? points : nil
    }
}

func signedArea(_ p: [Point2]) -> Double {
    guard p.count >= 3 else { return 0 }
    var sum = 0.0
    for i in p.indices {
        sum += p[i].cross(p[(i + 1) % p.count])
    }
    return sum / 2
}

func convexHull(_ points: [Point2]) -> [Point2] {
    let pts = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
    guard pts.count >= 3 else { return pts }
    func half(_ seq: [Point2]) -> [Point2] {
        var h: [Point2] = []
        for p in seq {
            while h.count >= 2 && (h[h.count - 1] - h[h.count - 2]).cross(p - h[h.count - 2]) <= 0 {
                h.removeLast()
            }
            h.append(p)
        }
        return h
    }
    let lower = half(pts), upper = half(pts.reversed())
    return Array(lower.dropLast()) + Array(upper.dropLast())
}
