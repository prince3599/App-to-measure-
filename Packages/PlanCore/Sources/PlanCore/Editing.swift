import Foundation

/// A rotation about `pivot` followed by a translation, used to place rooms on a floor.
public struct RigidTransform: Equatable, Sendable {
    public var angle: Double
    public var pivot: Point2
    public var translation: Point2

    public init(angle: Double = 0, pivot: Point2 = .zero, translation: Point2 = .zero) {
        self.angle = angle
        self.pivot = pivot
        self.translation = translation
    }

    public func apply(_ p: Point2) -> Point2 {
        rotate(p - pivot) + pivot + translation
    }

    public func rotate(_ v: Point2) -> Point2 {
        let c = cos(angle), s = sin(angle)
        return Point2(v.x * c - v.y * s, v.x * s + v.y * c)
    }
}

extension FloorPlan {
    public func transformed(by t: RigidTransform) -> FloorPlan {
        var plan = self
        for i in plan.walls.indices {
            plan.walls[i].line = Segment2(t.apply(walls[i].line.start), t.apply(walls[i].line.end))
        }
        for i in plan.objects.indices {
            plan.objects[i].center = t.apply(objects[i].center)
            plan.objects[i].rotation += t.angle
        }
        return plan
    }

    /// Changes one wall's length by moving its end. The wall joined at that end moves with it,
    /// and the wall beyond that stretches, so a rectangular room stays rectangular.
    public func settingLength(ofWall index: Int, to length: Double) -> FloorPlan {
        guard walls.indices.contains(index), length > 0.05 else { return self }
        let line = walls[index].line
        let shift = line.direction * (length - line.length)
        guard shift.length > 1e-9 else { return self }

        let corners = PlanGeometry.corners(of: walls, tolerance: 0.01)
        func partner(_ e: PlanGeometry.WallEnd) -> PlanGeometry.WallEnd? {
            for c in corners {
                if c.a == e { return c.b }
                if c.b == e { return c.a }
            }
            return nil
        }
        var plan = self
        func move(_ e: PlanGeometry.WallEnd) {
            if e.atEnd { plan.walls[e.wall].line.end = plan.walls[e.wall].line.end + shift }
            else { plan.walls[e.wall].line.start = plan.walls[e.wall].line.start + shift }
        }

        move(PlanGeometry.WallEnd(wall: index, atEnd: true))
        if let next = partner(PlanGeometry.WallEnd(wall: index, atEnd: true)), next.wall != index {
            move(next)
            let far = PlanGeometry.WallEnd(wall: next.wall, atEnd: !next.atEnd)
            move(far)
            if let beyond = partner(far), beyond.wall != index, beyond.wall != next.wall {
                move(beyond)
            }
        }
        plan.reanchorOpenings(from: self)
        return plan
    }

    /// Keeps each opening at the same place on its wall after the wall's ends moved.
    mutating func reanchorOpenings(from old: FloorPlan) {
        for i in openings.indices {
            let o = openings[i]
            guard old.walls.indices.contains(o.wallIndex) else { continue }
            let before = old.walls[o.wallIndex].line, after = walls[o.wallIndex].line
            let half = min(o.width, after.length) / 2
            let offset = after.distanceAlong(before.point(atDistance: o.offset))
            openings[i].offset = min(max(offset, half), after.length - half)
        }
    }
}

// MARK: - Wall points

extension FloorPlan {
    /// Wall ends, with ends that meet at a corner listed once.
    public var points: [Point2] {
        var out: [Point2] = []
        for w in walls {
            for p in [w.line.start, w.line.end] where !out.contains(where: { $0.distance(to: p) < 0.02 }) {
                out.append(p)
            }
        }
        return out
    }

    /// Splits a wall in two at the point nearest `p`, so each part can be moved or measured on its own.
    /// Returns nil when the point is too close to an end.
    public func splittingWall(_ index: Int, at p: Point2) -> FloorPlan? {
        guard walls.indices.contains(index) else { return nil }
        let line = walls[index].line
        let d = line.distanceAlong(p)
        guard d > 0.1, d < line.length - 0.1 else { return nil }
        let q = line.point(atDistance: d)

        var plan = self
        plan.walls[index].line = Segment2(line.start, q)
        var second = walls[index]
        second.line = Segment2(q, line.end)
        plan.walls.insert(second, at: index + 1)
        for i in plan.openings.indices {
            if plan.openings[i].wallIndex > index {
                plan.openings[i].wallIndex += 1
            } else if plan.openings[i].wallIndex == index, plan.openings[i].offset > d {
                plan.openings[i].wallIndex = index + 1
                plan.openings[i].offset -= d
            }
        }
        return plan
    }

    /// Moves every wall end at `point` to `target`. The walls meeting there follow,
    /// and doors and windows stay where they were on their walls.
    public func movingPoint(_ point: Point2, to target: Point2, tolerance: Double = 0.02) -> FloorPlan {
        var plan = self
        for i in plan.walls.indices {
            if walls[i].line.start.distance(to: point) <= tolerance { plan.walls[i].line.start = target }
            if walls[i].line.end.distance(to: point) <= tolerance { plan.walls[i].line.end = target }
        }
        plan.walls.removeAll { $0.line.length < 0.01 }
        guard plan.walls.count == walls.count else { return self }
        plan.reanchorOpenings(from: self)
        return plan
    }

    /// Joins the two walls that meet at `point` back into one wall. Returns nil unless exactly two walls meet there.
    public func removingPoint(_ point: Point2, tolerance: Double = 0.02) -> FloorPlan? {
        let ends = walls.indices.flatMap { i -> [(wall: Int, atEnd: Bool)] in
            var e: [(wall: Int, atEnd: Bool)] = []
            if walls[i].line.start.distance(to: point) <= tolerance { e.append((i, false)) }
            if walls[i].line.end.distance(to: point) <= tolerance { e.append((i, true)) }
            return e
        }
        guard ends.count == 2, ends[0].wall != ends[1].wall else { return nil }
        let (a, b) = ends[0].wall < ends[1].wall ? (ends[0], ends[1]) : (ends[1], ends[0])
        let farA = a.atEnd ? walls[a.wall].line.start : walls[a.wall].line.end
        let farB = b.atEnd ? walls[b.wall].line.start : walls[b.wall].line.end
        // Keep wall a's direction where possible so its openings keep their side.
        let joined = a.atEnd ? Segment2(farA, farB) : Segment2(farB, farA)
        guard joined.length > 0.05 else { return nil }

        var plan = self
        plan.walls[a.wall].line = joined
        plan.walls.remove(at: b.wall)
        for i in plan.openings.indices {
            let o = openings[i]
            if o.wallIndex == a.wall || o.wallIndex == b.wall {
                let c = walls[o.wallIndex].line.point(atDistance: o.offset)
                let half = min(o.width, joined.length) / 2
                plan.openings[i].wallIndex = a.wall
                plan.openings[i].offset = min(max(joined.distanceAlong(c), half), joined.length - half)
            } else if o.wallIndex > b.wall {
                plan.openings[i].wallIndex -= 1
            }
        }
        return plan
    }
}

extension Floor {
    /// The wall end (corner or added point) nearest `p`, within `tolerance`.
    public func pointHit(at p: Point2, tolerance: Double) -> (room: Int, point: Point2)? {
        var best: (Double, Int, Point2)?
        for (r, room) in rooms.enumerated() {
            for q in room.plan.points {
                let d = q.distance(to: p)
                if d <= tolerance, best == nil || d < best!.0 { best = (d, r, q) }
            }
        }
        return best.map { ($0.1, $0.2) }
    }

    public func movingPoint(room: Int, point: Point2, by delta: Point2) -> Floor {
        guard rooms.indices.contains(room) else { return self }
        var floor = self
        floor.rooms[room].plan = rooms[room].plan.movingPoint(point, to: point + delta)
        return floor
    }
}

extension Room {
    public func transformed(by t: RigidTransform) -> Room {
        var room = self
        room.plan = plan.transformed(by: t)
        room.scan = scan?.map { item in
            var item = item
            item.center = t.apply(item.center)
            item.direction = t.rotate(item.direction)
            return item
        }
        return room
    }
}

public enum FloorHit: Equatable, Sendable {
    case opening(room: Int, index: Int)
    case wall(WallRef)
    case room(Int)
}

extension Floor {
    public func movingRoom(_ index: Int, by delta: Point2) -> Floor {
        guard rooms.indices.contains(index) else { return self }
        var floor = self
        floor.rooms[index] = rooms[index].transformed(by: RigidTransform(translation: delta))
        return floor
    }

    /// Rotates a room about its own centre.
    public func rotatingRoom(_ index: Int, by angle: Double) -> Floor {
        guard rooms.indices.contains(index) else { return self }
        var floor = self
        floor.rooms[index] = rooms[index].transformed(by: RigidTransform(angle: angle, pivot: rooms[index].plan.labelPoint))
        return floor
    }

    /// Lines a room up against the nearest wall of another room: walls made parallel,
    /// faces `gap` apart (the interior wall), and corners made flush when they're close.
    /// Returns nil when no other room's wall is near enough.
    public func snappingRoom(_ index: Int, gap: Double = 0.12, maxDistance: Double = 1.0,
                             maxAngle: Double = 20 * .pi / 180) -> Floor? {
        guard rooms.indices.contains(index), rooms.count > 1 else { return nil }
        let plan = rooms[index].plan
        let pivot = plan.labelPoint
        var best: (score: Double, transform: RigidTransform)?

        for wall in plan.walls {
            let n = PlanGeometry.outwardNormal(of: wall, roomCentroid: plan.centroid)
            for (r2, other) in rooms.enumerated() where r2 != index {
                for wall2 in other.plan.walls {
                    let n2 = PlanGeometry.outwardNormal(of: wall2, roomCentroid: other.plan.centroid)
                    let target = n2 * -1
                    let angle = atan2(n.cross(target), n.dot(target))
                    guard abs(angle) <= maxAngle else { continue }

                    let rotation = RigidTransform(angle: angle, pivot: pivot)
                    let line = Segment2(rotation.apply(wall.line.start), rotation.apply(wall.line.end))
                    let nr = rotation.rotate(n)
                    let distance = (wall2.line.midpoint - line.midpoint).dot(nr)
                    guard abs(distance - gap) <= maxDistance else { continue }

                    var shift = nr * (distance - gap)
                    // Overlap along the wall after moving.
                    let a0 = wall2.line.distanceAlong(line.start + shift), a1 = wall2.line.distanceAlong(line.end + shift)
                    let overlap = min(max(a0, a1), wall2.line.length) - max(min(a0, a1), 0)
                    guard overlap > 0.3 else { continue }

                    // Make corners flush when an end is within 30 cm of the other wall's end.
                    let u = wall2.line.direction
                    var slide = 0.0, closest = 0.3
                    for p in [line.start + shift, line.end + shift] {
                        for q in [wall2.line.start, wall2.line.end] {
                            let d = (q - p).dot(u)
                            if abs(d) < closest { closest = abs(d); slide = d }
                        }
                    }
                    shift = shift + u * slide

                    let score = abs(angle) * 2 + abs(distance - gap)
                    if best == nil || score < best!.score {
                        best = (score, RigidTransform(angle: angle, pivot: pivot, translation: shift))
                    }
                }
            }
        }
        guard let best else { return nil }
        var floor = self
        floor.rooms[index] = rooms[index].transformed(by: best.transform)
        return floor
    }

    /// What's under a point: a door or window first, then a wall, then a room.
    public func hit(at p: Point2, tolerance: Double) -> FloorHit? {
        var bestOpening: (Double, Int, Int)?
        for (r, room) in rooms.enumerated() {
            for (i, o) in room.plan.openings.enumerated() where room.plan.walls.indices.contains(o.wallIndex) {
                let c = room.plan.walls[o.wallIndex].line.point(atDistance: o.offset)
                let d = c.distance(to: p)
                if d <= max(o.width / 2, tolerance), bestOpening == nil || d < bestOpening!.0 {
                    bestOpening = (d, r, i)
                }
            }
        }
        if let b = bestOpening { return .opening(room: b.1, index: b.2) }

        var bestWall: (Double, WallRef)?
        for (r, room) in rooms.enumerated() {
            for (w, wall) in room.plan.walls.enumerated() {
                let d = wall.line.distance(to: p)
                if d <= tolerance, bestWall == nil || d < bestWall!.0 { bestWall = (d, WallRef(room: r, wall: w)) }
            }
        }
        if let b = bestWall { return .wall(b.1) }

        for (r, room) in rooms.enumerated() where contains(room.plan.outline, p) {
            return .room(r)
        }
        return nil
    }

    /// Lower-left and upper-right corners of all walls.
    public var bounds: (min: Point2, max: Point2)? {
        let pts = rooms.flatMap { $0.plan.walls.flatMap { [$0.line.start, $0.line.end] } }
        guard let first = pts.first else { return nil }
        return pts.reduce((first, first)) { acc, p in
            (Point2(min(acc.0.x, p.x), min(acc.0.y, p.y)), Point2(max(acc.1.x, p.x), max(acc.1.y, p.y)))
        }
    }
}

/// Even-odd point-in-polygon test.
func contains(_ polygon: [Point2], _ p: Point2) -> Bool {
    guard polygon.count >= 3 else { return false }
    var inside = false
    var j = polygon.count - 1
    for i in polygon.indices {
        let a = polygon[i], b = polygon[j]
        if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
            inside.toggle()
        }
        j = i
    }
    return inside
}
