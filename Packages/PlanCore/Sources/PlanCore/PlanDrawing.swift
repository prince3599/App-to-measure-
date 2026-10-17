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
    /// When set, walls between two scanned rooms are drawn this thick, centred between the two room faces.
    public var interiorWallThickness: Double?
    /// When set, outside walls are drawn this thick instead of each wall's own thickness.
    /// A wall's own `thicknessOverride` wins over both settings.
    public var exteriorWallThickness: Double?

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

        let (solids, cuts) = wallShapes(plans: plans, analysis: analysis)
        for line in WallOutline.boundary(solids: solids, cuts: cuts) {
            out.append(DrawingItem(layer: .wall, primitive: .line(line.start, line.end)))
        }
        var extent = solids.flatMap(\.polygon)

        for (r, plan) in plans.enumerated() {
            for (w, wall) in plan.walls.enumerated() {
                let info = analysis.info[r][w]
                let inner = wall.line, n = info.outward, length = inner.length
                extent += [inner.start, inner.end]
                for o in plan.openings where o.wallIndex == w && !isDrawnByEarlierRoom(o, wall: inner, room: r, plans: plans) {
                    out += symbol(for: o, wall: inner, outward: n, thickness: reach(info, at: o.offset, wall: wall))
                }
                if info.exteriorFraction(length: length) > 0.5 && length > 0.3 {
                    out += wallDimension(inner, outward: n, wallThickness: drawnThickness(wall, info))
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

    /// How far the drawn wall reaches out from the room face at a distance along it.
    private func reach(_ info: WallInfo, at d: Double, wall: Wall) -> Double {
        if let span = info.shared.first(where: { d >= $0.start - 1e-6 && d <= $0.end + 1e-6 }) {
            return span.thickness
        }
        return drawnThickness(wall, info)
    }

    /// Thickness an outside wall is drawn at.
    private func drawnThickness(_ wall: Wall, _ info: WallInfo) -> Double {
        wall.thicknessOverride ?? exteriorWallThickness ?? info.exteriorThickness
    }

    /// Every wall as filled bands (room face to outer face, mitred at corners), and every door,
    /// window and opening as a cut through the wall.
    private func wallShapes(plans: [FloorPlan], analysis: WallAnalysis) -> (solids: [WallOutline.Shape], cuts: [WallOutline.Shape]) {
        var solids: [WallOutline.Shape] = []
        var cuts: [WallOutline.Shape] = []
        // Free wall ends: the wall, the end on its room face, the matching outer point, and the direction away from the wall.
        var freeEnds: [(WallRef, Point2, Point2, Point2)] = []

        for (r, plan) in plans.enumerated() {
            let outer = PlanGeometry.outerFaces(of: plan, thicknesses: plan.walls.indices.map { drawnThickness(plan.walls[$0], analysis.info[r][$0]) })
            let corners = PlanGeometry.corners(of: plan.walls, tolerance: 0.01)
            let joined = corners.flatMap { [$0.a, $0.b] }
            func partner(_ e: PlanGeometry.WallEnd) -> PlanGeometry.WallEnd? {
                for c in corners {
                    if c.a == e { return c.b }
                    if c.b == e { return c.a }
                }
                return nil
            }
            func thickness(at e: PlanGeometry.WallEnd) -> Double {
                reach(analysis.info[r][e.wall], at: e.atEnd ? plan.walls[e.wall].line.length : 0, wall: plan.walls[e.wall])
            }
            func isExterior(_ e: PlanGeometry.WallEnd) -> Bool {
                let info = analysis.info[r][e.wall]
                return info.thickness(at: e.atEnd ? plan.walls[e.wall].line.length : 0) == info.exteriorThickness
            }
            for (w, wall) in plan.walls.enumerated() {
                let ref = WallRef(room: r, wall: w)
                let info = analysis.info[r][w]
                let inner = wall.line, n = info.outward, length = inner.length, face = outer[w]
                guard length > 1e-6 else { continue }
                let t = drawnThickness(wall, info)

                // Room-face and outer points at a wall end: mitred where two outside walls meet,
                // carried square past the corner where the other wall is shared, square at a free end.
                func endPoints(_ atEnd: Bool) -> (Point2, Point2) {
                    let end = PlanGeometry.WallEnd(wall: w, atEnd: atEnd)
                    let base = atEnd ? inner.end : inner.start
                    guard let other = partner(end) else { return (base, base + n * t) }
                    if isExterior(end) && isExterior(other) { return (base, atEnd ? face.end : face.start) }
                    let e = thickness(at: other)
                    let q = inner.point(atDistance: atEnd ? length + e : -e)
                    return (q, q + n * t)
                }
                func outerPoint(_ d: Double) -> Point2 {
                    face.point(atDistance: face.distanceAlong(inner.point(atDistance: d) + n * t))
                }
                for (a, b) in info.exteriorRanges(length: length) {
                    let (ia, oa) = a <= 1e-6 ? endPoints(false) : (inner.point(atDistance: a), outerPoint(a))
                    let (ib, ob) = b >= length - 1e-6 ? endPoints(true) : (inner.point(atDistance: b), outerPoint(b))
                    solids.append(.init(polygon: [ia, ib, ob, oa], wall: ref))
                }
                for span in info.shared {
                    // Out to the neighbouring room's face, even when the two faces aren't quite parallel.
                    let neighbor = plans[span.neighbor.room].walls[span.neighbor.wall].line
                    let a = inner.point(atDistance: span.start), b = inner.point(atDistance: span.end)
                    func across(_ p: Point2) -> Point2 {
                        guard let q = Segment2(p, p + n).lineIntersection(neighbor), (q - p).dot(n) > 0 else { return p + n * span.thickness }
                        return q
                    }
                    // The wall fills the space between the two rooms.
                    solids.append(.init(polygon: [a, b, across(b), across(a)], wall: ref))
                    // A plain partition is then trimmed to the standard thickness, equally from both rooms.
                    // Thicker gaps (a chimney, a duct, a bump in the wall) stay solid.
                    let chosen = wall.thicknessOverride ?? plans[span.neighbor.room].walls[span.neighbor.wall].thicknessOverride
                    if let ti = chosen ?? interiorWallThickness, span.thickness > ti + 0.005, span.thickness <= 0.3, span.end - span.start >= 0.3 {
                        let k = (span.thickness - ti) / 2
                        cuts.append(.init(polygon: [a, b, b + n * k, a + n * k], wall: nil))
                    }
                }
                if !joined.contains(.init(wall: w, atEnd: false)) {
                    freeEnds.append((ref, inner.start, inner.start + n * reach(info, at: 0, wall: wall), inner.direction * -1))
                }
                if !joined.contains(.init(wall: w, atEnd: true)) {
                    freeEnds.append((ref, inner.end, inner.end + n * reach(info, at: length, wall: wall), inner.direction))
                }

                for o in plan.openings where o.wallIndex == w {
                    let a = max(o.offset - o.width / 2, 0), b = min(o.offset + o.width / 2, length)
                    guard b - a > 1e-3 else { continue }
                    let depth = max(reach(info, at: o.offset, wall: wall), info.thickness(at: o.offset)) + 0.05
                    let p = inner.point(atDistance: a), q = inner.point(atDistance: b)
                    cuts.append(.init(polygon: [p - n * 0.05, q - n * 0.05, q + n * depth, p + n * depth], wall: ref))
                }
            }
        }

        // Walls never reach into a room: each room's floor is cut out of the wall bands.
        for plan in plans {
            if let floorOutline = plan.interiorOutline {
                cuts.append(.init(polygon: floorOutline, wall: nil))
            }
        }

        // A wall that stops just short of another wall is carried on to meet it.
        for (ref, p, q, dir) in freeEnds {
            let mid = (p + q) / 2
            guard !solids.contains(where: { $0.wall != ref && contains($0.polygon, mid + dir * 1e-3) }) else { continue }
            let hits = [p, q].compactMap { WallOutline.rayHit(from: $0, direction: dir, shapes: solids, exclude: ref) }
            guard let reach = hits.min(), reach <= 0.35 else { continue }
            let e = reach + 0.01
            solids.append(.init(polygon: [p, p + dir * e, q + dir * e, q], wall: ref))
        }
        return (solids, cuts)
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
