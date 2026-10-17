import Foundation

/// CAD layers, named after the US National CAD Standard so they look familiar in AutoCAD.
public enum Layer: String, CaseIterable, Sendable {
    case wall = "A-WALL"
    case door = "A-DOOR"
    case glazing = "A-GLAZ"
    case furniture = "A-FURN"
    case dimensions = "A-DIMS"
    case annotation = "A-ANNO"

    /// AutoCAD Color Index.
    public var aciColor: Int {
        switch self {
        case .wall: return 7       // white/black
        case .door: return 3       // green
        case .glazing: return 4    // cyan
        case .furniture: return 8  // grey
        case .dimensions: return 1 // red
        case .annotation: return 2 // yellow
        }
    }
}

public enum Primitive: Equatable, Sendable {
    case line(Point2, Point2)
    /// Counter-clockwise from `start` to `end`, angles in radians.
    case arc(center: Point2, radius: Double, start: Double, end: Double)
    /// Centred on `at`, `rotation` in radians.
    case text(at: Point2, height: Double, string: String, rotation: Double)
}

public struct DrawingItem: Equatable, Sendable {
    public var layer: Layer
    public var primitive: Primitive
}

public enum LengthUnit: String, Codable, CaseIterable, Sendable {
    case millimetres
    case inches

    /// Drawing units per metre.
    public var scale: Double {
        switch self {
        case .millimetres: return 1000
        case .inches: return 1 / 0.0254
        }
    }

    public func format(_ metres: Double) -> String {
        switch self {
        case .millimetres:
            return String(Int((metres * 1000).rounded()))
        case .inches:
            let totalInches = Int((metres / 0.0254).rounded())
            return "\(totalInches / 12)'-\(totalInches % 12)\""
        }
    }
}

/// Turns a floor plan into layered line work, shared by the on-screen preview and DXF export.
public struct PlanDrawing: Sendable {
    public var unit: LengthUnit = .millimetres
    public var dimensionOffset = 0.30
    public var textHeight = 0.12

    public init(unit: LengthUnit = .millimetres) {
        self.unit = unit
    }

    public func items(for plan: FloorPlan) -> [DrawingItem] {
        var out: [DrawingItem] = []
        let centroid = plan.centroid
        let outer = PlanGeometry.outerFaces(of: plan)
        let joined = PlanGeometry.corners(of: plan.walls, tolerance: 0.01).flatMap { [$0.a, $0.b] }

        for (i, wall) in plan.walls.enumerated() {
            let inner = wall.line
            let n = PlanGeometry.outwardNormal(of: wall, roomCentroid: centroid)
            let openings = plan.openings.filter { $0.wallIndex == i }.sorted { $0.offset < $1.offset }
            let gaps = openings.map { ($0.offset - $0.width / 2, $0.offset + $0.width / 2) }

            // Room-side face, broken at openings.
            for (a, b) in solidRanges(length: inner.length, gaps: gaps) {
                out.append(DrawingItem(layer: .wall, primitive: .line(inner.point(atDistance: a), inner.point(atDistance: b))))
            }
            // Outer face, broken at the same openings.
            let face = outer[i]
            let outerGaps = gaps.map { g in
                (face.distanceAlong(inner.point(atDistance: g.0) + n * wall.thickness),
                 face.distanceAlong(inner.point(atDistance: g.1) + n * wall.thickness))
            }
            for (a, b) in solidRanges(length: face.length, gaps: outerGaps) {
                out.append(DrawingItem(layer: .wall, primitive: .line(face.point(atDistance: a), face.point(atDistance: b))))
            }
            // Jambs at each opening edge.
            for g in gaps {
                for d in [g.0, g.1] {
                    let p = inner.point(atDistance: d)
                    out.append(DrawingItem(layer: .wall, primitive: .line(p, p + n * wall.thickness)))
                }
            }
            // Close free wall ends.
            if !joined.contains(.init(wall: i, atEnd: false)) {
                out.append(DrawingItem(layer: .wall, primitive: .line(inner.start, face.start)))
            }
            if !joined.contains(.init(wall: i, atEnd: true)) {
                out.append(DrawingItem(layer: .wall, primitive: .line(inner.end, face.end)))
            }

            for o in openings {
                out += symbol(for: o, wall: wall, outward: n)
            }
            out += dimension(for: inner, outward: n, wallThickness: wall.thickness)
        }

        for object in plan.objects {
            let c = object.corners
            for k in 0..<4 {
                out.append(DrawingItem(layer: .furniture, primitive: .line(c[k], c[(k + 1) % 4])))
            }
            out.append(DrawingItem(layer: .furniture, primitive: .text(
                at: object.center, height: textHeight * 0.8, string: object.label.uppercased(),
                rotation: readable(object.rotation))))
        }
        return out
    }

    private func solidRanges(length: Double, gaps: [(Double, Double)]) -> [(Double, Double)] {
        var ranges: [(Double, Double)] = []
        var cursor = 0.0
        for (a, b) in gaps.sorted(by: { $0.0 < $1.0 }) {
            if a > cursor + 1e-6 { ranges.append((cursor, a)) }
            cursor = max(cursor, b)
        }
        if length > cursor + 1e-6 { ranges.append((cursor, length)) }
        return ranges
    }

    private func symbol(for o: Opening, wall: Wall, outward n: Point2) -> [DrawingItem] {
        let line = wall.line
        let d = line.direction
        let a = line.point(atDistance: o.offset - o.width / 2)
        let b = line.point(atDistance: o.offset + o.width / 2)
        switch o.kind {
        case .door:
            // Hinged at `a`, swinging into the room.
            let inward = n * -1
            let leafEnd = a + inward * o.width
            let (s, e) = inward.cross(d) > 0 ? (inward.angle, d.angle) : (d.angle, inward.angle)
            return [
                DrawingItem(layer: .door, primitive: .line(a, leafEnd)),
                DrawingItem(layer: .door, primitive: .arc(center: a, radius: o.width, start: s, end: e)),
            ]
        case .window:
            return [1.0 / 3, 2.0 / 3].map { f in
                DrawingItem(layer: .glazing, primitive: .line(a + n * (wall.thickness * f), b + n * (wall.thickness * f)))
            }
        case .opening:
            return []
        }
    }

    /// Interior (clear) length of a wall, dimensioned outside the room so it never collides with furniture.
    private func dimension(for line: Segment2, outward n: Point2, wallThickness: Double) -> [DrawingItem] {
        guard line.length > 0.05 else { return [] }
        let dimLine = line.offset(by: wallThickness + dimensionOffset, along: n)
        let tick = (line.direction + n).normalized * 0.05
        let label = dimLine.midpoint + n * (textHeight * 0.8)
        var items = [line.start, line.end].map { p in
            DrawingItem(layer: .dimensions, primitive: .line(p + n * (wallThickness + 0.05), p + n * (wallThickness + dimensionOffset + 0.05)))
        }
        items += [
            DrawingItem(layer: .dimensions, primitive: .line(dimLine.start, dimLine.end)),
            DrawingItem(layer: .dimensions, primitive: .line(dimLine.start - tick, dimLine.start + tick)),
            DrawingItem(layer: .dimensions, primitive: .line(dimLine.end - tick, dimLine.end + tick)),
            DrawingItem(layer: .dimensions, primitive: .text(
                at: label, height: textHeight, string: unit.format(line.length),
                rotation: readable(line.direction.angle))),
        ]
        return items
    }

    /// Keeps text from reading upside down.
    private func readable(_ angle: Double) -> Double {
        var a = angle
        while a > .pi / 2 + 1e-9 { a -= .pi }
        while a <= -.pi / 2 + 1e-9 { a += .pi }
        return a
    }
}
