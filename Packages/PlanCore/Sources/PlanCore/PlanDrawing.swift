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

/// A room's plan with its display name.
public struct LabeledPlan: Sendable {
    public var name: String?
    public var plan: FloorPlan

    public init(name: String?, plan: FloorPlan) {
        self.name = name
        self.plan = plan
    }
}

/// Turns rooms into layered line work, shared by the on-screen preview, PDF sheets and DXF export.
/// Rooms on one floor are drawn together: walls two rooms share are drawn once, at their real thickness.
public struct PlanDrawing: Sendable {
    public var unit: LengthUnit = .millimetres
    public var textHeight = 0.12
    /// Distance of wall dimensions outside the wall's outer face.
    public var dimensionOffset = 0.60
    public var showFurniture = true
    public var showRoomLabels = true
    public var showOpeningTags = true
    public var showOverallDimensions = true

    /// Objects drawn even when furniture is hidden.
    public static let fixtures: Set<String> = [
        "toilet", "sink", "bathtub", "stove", "oven", "refrigerator", "dishwasher", "washerDryer", "fireplace", "stairs",
    ]

    public init(unit: LengthUnit = .millimetres) {
        self.unit = unit
    }

    public func items(for plan: FloorPlan) -> [DrawingItem] {
        items(for: [LabeledPlan(name: nil, plan: plan)])
    }

    public func items(for floor: Floor) -> [DrawingItem] {
        items(for: floor.rooms.map { LabeledPlan(name: $0.name, plan: $0.plan) })
    }

    public func items(for rooms: [LabeledPlan]) -> [DrawingItem] {
        let plans = rooms.map(\.plan)
        let analysis = WallAnalysis(rooms: plans)
        var out: [DrawingItem] = []
        var extent: [Point2] = []

        for (r, plan) in plans.enumerated() {
            let outer = PlanGeometry.outerFaces(of: plan)
            let joined = PlanGeometry.corners(of: plan.walls, tolerance: 0.01).flatMap { [$0.a, $0.b] }

            for (w, wall) in plan.walls.enumerated() {
                let info = analysis.info[r][w]
                let inner = wall.line, n = info.outward, length = inner.length
                let face = outer[w]
                let openings = plan.openings.filter { $0.wallIndex == w }
                let gaps = openingGaps(own: openings, info: info, inner: inner, plans: plans)
                extent += [inner.start, inner.end]

                // Room-side face, broken at openings.
                for (a, b) in subtractRanges([(0, length)], gaps) {
                    out.append(DrawingItem(layer: .wall, primitive: .line(inner.point(atDistance: a), inner.point(atDistance: b))))
                }
                // Outer face where nothing is scanned behind the wall.
                for (a, b) in subtractRanges(info.exteriorRanges(length: length), gaps) {
                    let fa = a <= 1e-6 ? 0 : face.distanceAlong(inner.point(atDistance: a) + n * info.exteriorThickness)
                    let fb = b >= length - 1e-6 ? face.length : face.distanceAlong(inner.point(atDistance: b) + n * info.exteriorThickness)
                    guard fb - fa > 1e-6 else { continue }
                    out.append(DrawingItem(layer: .wall, primitive: .line(face.point(atDistance: fa), face.point(atDistance: fb))))
                    extent += [face.point(atDistance: fa), face.point(atDistance: fb)]
                }
                // Jambs at each opening edge.
                for g in gaps {
                    for d in [g.0, g.1] where d > 1e-6 && d < length - 1e-6 {
                        let p = inner.point(atDistance: d)
                        out.append(DrawingItem(layer: .wall, primitive: .line(p, p + n * info.thickness(at: d))))
                    }
                }
                // Close free exterior wall ends.
                if !joined.contains(.init(wall: w, atEnd: false)) && info.thickness(at: 0) == info.exteriorThickness {
                    out.append(DrawingItem(layer: .wall, primitive: .line(inner.start, face.start)))
                }
                if !joined.contains(.init(wall: w, atEnd: true)) && info.thickness(at: length) == info.exteriorThickness {
                    out.append(DrawingItem(layer: .wall, primitive: .line(inner.end, face.end)))
                }

                for o in openings where !isDrawnByEarlierRoom(o, wall: inner, room: r, plans: plans) {
                    out += symbol(for: o, wall: inner, outward: n, thickness: info.thickness(at: o.offset))
                }
                if info.exteriorFraction(length: length) > 0.5 && length > 0.3 {
                    out += wallDimension(inner, outward: n, wallThickness: info.exteriorThickness)
                }
            }

            for object in plan.objects where showFurniture || Self.fixtures.contains(object.label) {
                out += objectItems(object)
            }
            if showRoomLabels {
                out += roomLabel(name: rooms[r].name, plan: plan)
            }
        }

        if showOverallDimensions, let first = plans.first, !extent.isEmpty {
            out += overallDimensions(extent: extent, axisFrom: first)
        }
        return out
    }

    /// Openings in this wall, plus openings the room on the other side found in its face.
    private func openingGaps(own: [Opening], info: WallInfo, inner: Segment2, plans: [FloorPlan]) -> [(Double, Double)] {
        var gaps = own.map { ($0.offset - $0.width / 2, $0.offset + $0.width / 2) }
        for span in info.shared {
            let neighbor = plans[span.neighbor.room]
            let line = neighbor.walls[span.neighbor.wall].line
            for o in neighbor.openings where o.wallIndex == span.neighbor.wall {
                let t = inner.distanceAlong(line.point(atDistance: o.offset))
                gaps.append((t - o.width / 2, t + o.width / 2))
            }
        }
        return gaps
            .map { (max($0.0, 0), min($0.1, inner.length)) }
            .filter { $0.1 - $0.0 > 1e-6 }
    }

    /// A door between two scanned rooms shows up in both scans; only the first room draws its symbol.
    private func isDrawnByEarlierRoom(_ o: Opening, wall: Segment2, room: Int, plans: [FloorPlan]) -> Bool {
        let c = wall.point(atDistance: o.offset)
        return plans.prefix(room).contains { plan in
            plan.openings.contains { other in
                other.kind == o.kind && plan.walls[other.wallIndex].line.point(atDistance: other.offset).distance(to: c) < 0.5
            }
        }
    }

    private func symbol(for o: Opening, wall line: Segment2, outward n: Point2, thickness: Double) -> [DrawingItem] {
        let d = line.direction
        let a = line.point(atDistance: o.offset - o.width / 2)
        let b = line.point(atDistance: o.offset + o.width / 2)
        let mid = line.point(atDistance: o.offset)
        let tagHeight = textHeight * 0.75
        switch o.kind {
        case .door:
            let swing = o.swingsOut ? n : n * -1
            var items: [DrawingItem] = []
            let count = max(1, o.leaves)
            let leaf = o.width / Double(count)
            for k in 0..<count {
                let s0 = a + d * (Double(k) * leaf), s1 = s0 + d * leaf
                // Single: hinge at one side. Double: hinges at both outer edges. More: pairs meeting in the middle.
                var hingeAtStart = count == 1 ? true : k % 2 == 0
                if o.hingeAtEnd && count != 2 { hingeAtStart.toggle() }
                let hinge = hingeAtStart ? s0 : s1
                let free = (hingeAtStart ? s1 : s0) - hinge
                let (start, end) = swing.cross(free) > 0 ? (swing.angle, free.angle) : (free.angle, swing.angle)
                items.append(DrawingItem(layer: .door, primitive: .line(hinge, hinge + swing * leaf)))
                items.append(DrawingItem(layer: .door, primitive: .arc(center: hinge, radius: leaf, start: start, end: end)))
            }
            if showOpeningTags {
                let label = count > 1 ? "D \(unit.format(o.width)) (\(count))" : "D \(unit.format(o.width))"
                items.append(DrawingItem(layer: .annotation, primitive: .text(
                    at: mid + swing * 0.3, height: tagHeight, string: label,
                    rotation: readable(d.angle))))
            }
            return items
        case .window:
            var items = [1.0 / 3, 2.0 / 3].map { f in
                DrawingItem(layer: .glazing, primitive: .line(a + n * (thickness * f), b + n * (thickness * f)))
            }
            if showOpeningTags {
                let size = o.height > 0 ? "\(unit.format(o.width)) x \(unit.format(o.height))" : unit.format(o.width)
                items.append(DrawingItem(layer: .annotation, primitive: .text(
                    at: mid + n * (thickness + 0.25), height: tagHeight, string: "W \(size)",
                    rotation: readable(d.angle))))
            }
            return items
        case .opening:
            return []
        }
    }

    /// Interior (clear) length of a wall, dimensioned outside the building.
    private func wallDimension(_ line: Segment2, outward n: Point2, wallThickness: Double) -> [DrawingItem] {
        let near = wallThickness + 0.05, far = wallThickness + dimensionOffset + 0.05
        var items = [line.start, line.end].map { p in
            DrawingItem(layer: .dimensions, primitive: .line(p + n * near, p + n * far))
        }
        let offset = wallThickness + dimensionOffset
        items += dimensionLine(line.start + n * offset, line.end + n * offset, outward: n, label: unit.format(line.length))
        return items
    }

    private func dimensionLine(_ a: Point2, _ b: Point2, outward n: Point2, label: String) -> [DrawingItem] {
        let seg = Segment2(a, b)
        let tick = (seg.direction + n).normalized * 0.05
        return [
            DrawingItem(layer: .dimensions, primitive: .line(a, b)),
            DrawingItem(layer: .dimensions, primitive: .line(a - tick, a + tick)),
            DrawingItem(layer: .dimensions, primitive: .line(b - tick, b + tick)),
            DrawingItem(layer: .dimensions, primitive: .text(
                at: seg.midpoint + n * (textHeight * 0.8), height: textHeight, string: label,
                rotation: readable(seg.direction.angle))),
        ]
    }

    /// Overall width and depth of the floor, outside everything else.
    private func overallDimensions(extent: [Point2], axisFrom plan: FloorPlan) -> [DrawingItem] {
        guard let longest = plan.walls.max(by: { $0.line.length < $1.line.length }) else { return [] }
        let u = longest.line.direction, v = u.perpendicular
        let us = extent.map { $0.dot(u) }, vs = extent.map { $0.dot(v) }
        guard let u0 = us.min(), let u1 = us.max(), let v0 = vs.min(), let v1 = vs.max() else { return [] }
        func p(_ a: Double, _ b: Double) -> Point2 { u * a + v * b }
        let gap = dimensionOffset + 0.7
        return dimensionLine(p(u0, v0 - gap), p(u1, v0 - gap), outward: v * -1, label: unit.format(u1 - u0))
            + dimensionLine(p(u1 + gap, v0), p(u1 + gap, v1), outward: u, label: unit.format(v1 - v0))
    }

    private func objectItems(_ object: PlanObject) -> [DrawingItem] {
        let c = object.corners
        var items = (0..<4).map { k in
            DrawingItem(layer: .furniture, primitive: .line(c[k], c[(k + 1) % 4]))
        }
        if object.label == "stairs" {
            // Treads every 250 mm across the run.
            let u = Point2(cos(object.rotation), sin(object.rotation)), v = u.perpendicular
            let steps = Int(object.depth / 0.25)
            if steps > 1 {
                for k in 1..<steps {
                    let p = c[0] + v * (Double(k) * 0.25)
                    items.append(DrawingItem(layer: .furniture, primitive: .line(p, p + u * object.width)))
                }
            }
        }
        items.append(DrawingItem(layer: .furniture, primitive: .text(
            at: object.center, height: textHeight * 0.8, string: object.label.uppercased(),
            rotation: readable(object.rotation))))
        return items
    }

    private func roomLabel(name: String?, plan: FloorPlan) -> [DrawingItem] {
        guard !plan.walls.isEmpty else { return [] }
        let size = plan.size
        var lines: [(String, Double)] = []
        if let name, !name.isEmpty { lines.append((name.uppercased(), textHeight * 1.4)) }
        lines.append(("\(unit.format(size.width)) x \(unit.format(size.depth))", textHeight))
        lines.append((unit.formatArea(plan.area), textHeight))
        if plan.ceilingHeight > 0 { lines.append(("CLG \(unit.format(plan.ceilingHeight))", textHeight)) }
        let spacing = 1.6
        let total = lines.map { $0.1 * spacing }.reduce(0, +)
        var y = plan.labelPoint.y + total / 2
        return lines.map { text, h in
            y -= h * spacing / 2
            defer { y -= h * spacing / 2 }
            return DrawingItem(layer: .annotation, primitive: .text(
                at: Point2(plan.labelPoint.x, y), height: h, string: text, rotation: 0))
        }
    }

    /// Keeps text from reading upside down.
    private func readable(_ angle: Double) -> Double {
        var a = angle
        while a > .pi / 2 + 1e-9 { a -= .pi }
        while a <= -.pi / 2 + 1e-9 { a += .pi }
        return a
    }
}
