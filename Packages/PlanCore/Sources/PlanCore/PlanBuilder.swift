import Foundation

/// A flat surface or object as seen from above, already projected into plan space.
/// The capture layer (RoomPlan today) converts its output into these.
public struct ScannedItem: Sendable {
    public enum Kind: Sendable, Equatable {
        case wall
        case door
        case window
        case opening
        case object(label: String)
    }

    public var kind: Kind
    public var center: Point2
    /// Unit vector along the item's width.
    public var direction: Point2
    public var width: Double
    /// Only meaningful for objects.
    public var depth: Double
    /// Vertical size (wall height, window height). 0 when unknown.
    public var height: Double

    public init(kind: Kind, center: Point2, direction: Point2, width: Double, depth: Double = 0, height: Double = 0) {
        self.kind = kind
        self.center = center
        self.direction = direction.normalized
        self.width = width
        self.depth = depth
        self.height = height
    }
}

public struct PlanBuilder: Sendable {
    /// Wall ends closer than this are treated as meeting at a corner.
    public var cornerTolerance: Double = 0.25
    /// Openings further than this from every wall are dropped.
    public var openingTolerance: Double = 0.30
    public var wallThickness: Double = Wall.defaultThickness

    public init() {}

    public func build(from items: [ScannedItem]) -> FloorPlan {
        var walls = items.filter { $0.kind == .wall }.map { item -> Wall in
            let half = item.direction * (item.width / 2)
            return Wall(line: Segment2(item.center - half, item.center + half), thickness: wallThickness)
        }
        joinCorners(&walls)

        var openings: [Opening] = []
        for item in items {
            let kind: OpeningKind
            switch item.kind {
            case .door: kind = .door
            case .window: kind = .window
            case .opening: kind = .opening
            default: continue
            }
            guard let nearest = walls.indices
                .min(by: { walls[$0].line.distance(to: item.center) < walls[$1].line.distance(to: item.center) }),
                walls[nearest].line.distance(to: item.center) <= openingTolerance
            else { continue }
            let wall = walls[nearest]
            let half = min(item.width, wall.line.length) / 2
            let offset = min(max(wall.line.distanceAlong(item.center), half), wall.line.length - half)
            openings.append(Opening(kind: kind, wallIndex: nearest, offset: offset, width: half * 2, height: item.height))
        }

        let objects = items.compactMap { item -> PlanObject? in
            guard case let .object(label) = item.kind else { return nil }
            return PlanObject(label: label, center: item.center, width: item.width,
                              depth: item.depth, rotation: item.direction.angle)
        }

        let ceiling = items.filter { $0.kind == .wall }.map(\.height).max() ?? 0
        return FloorPlan(walls: walls, openings: openings, objects: objects, ceilingHeight: ceiling)
    }

    /// Moves nearby wall ends onto the intersection of their walls so corners close exactly.
    func joinCorners(_ walls: inout [Wall]) {
        for corner in PlanGeometry.corners(of: walls, tolerance: cornerTolerance) {
            let a = walls[corner.a.wall].line, b = walls[corner.b.wall].line
            let p = a.lineIntersection(b)
                ?? (end(of: a, corner.a.atEnd) + end(of: b, corner.b.atEnd)) / 2
            setEnd(&walls[corner.a.wall].line, corner.a.atEnd, p)
            setEnd(&walls[corner.b.wall].line, corner.b.atEnd, p)
        }
    }

    private func end(of s: Segment2, _ atEnd: Bool) -> Point2 { atEnd ? s.end : s.start }
    private func setEnd(_ s: inout Segment2, _ atEnd: Bool, _ p: Point2) {
        if atEnd { s.end = p } else { s.start = p }
    }
}

public enum PlanGeometry {
    public struct WallEnd: Equatable, Sendable {
        public var wall: Int
        public var atEnd: Bool
    }

    public struct Corner: Equatable, Sendable {
        public var a: WallEnd
        public var b: WallEnd
    }

    /// Pairs each wall end with the closest end of another wall within `tolerance`. Each end is used once.
    public static func corners(of walls: [Wall], tolerance: Double) -> [Corner] {
        var candidates: [(Double, WallEnd, WallEnd)] = []
        for i in walls.indices {
            for j in walls.indices where j > i {
                for ea in [false, true] {
                    for eb in [false, true] {
                        let pa = ea ? walls[i].line.end : walls[i].line.start
                        let pb = eb ? walls[j].line.end : walls[j].line.start
                        let d = pa.distance(to: pb)
                        if d <= tolerance {
                            candidates.append((d, WallEnd(wall: i, atEnd: ea), WallEnd(wall: j, atEnd: eb)))
                        }
                    }
                }
            }
        }
        var used: [WallEnd] = []
        var result: [Corner] = []
        for (_, a, b) in candidates.sorted(by: { $0.0 < $1.0 }) where !used.contains(a) && !used.contains(b) {
            used += [a, b]
            result.append(Corner(a: a, b: b))
        }
        return result
    }

    /// Unit normal pointing away from the room (the side the wall thickness is drawn on).
    public static func outwardNormal(of wall: Wall, roomCentroid: Point2) -> Point2 {
        let n = wall.line.direction.perpendicular
        return n.dot(wall.line.midpoint - roomCentroid) >= 0 ? n : n * -1
    }

    /// Outer face of every wall, with ends meeting neighbouring outer faces at corners.
    public static func outerFaces(of plan: FloorPlan, tolerance: Double = 0.01) -> [Segment2] {
        let c = plan.centroid
        var faces = plan.walls.map { w in
            w.line.offset(by: w.thickness, along: outwardNormal(of: w, roomCentroid: c))
        }
        let original = faces
        for corner in corners(of: plan.walls, tolerance: tolerance) {
            guard let p = original[corner.a.wall].lineIntersection(original[corner.b.wall]) else { continue }
            for end in [corner.a, corner.b] {
                if end.atEnd { faces[end.wall].end = p } else { faces[end.wall].start = p }
            }
        }
        return faces
    }
}
