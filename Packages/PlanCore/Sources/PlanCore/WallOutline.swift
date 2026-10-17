import Foundation

/// Wall line work drawn as the outline of every wall band merged together, minus the door and
/// window cuts. Walls then meet cleanly at corners and between rooms: lines never cross, a wall two
/// rooms share is one solid wall, and each opening gets its jambs.
enum WallOutline {
    /// A wall band (or cut) as a simple polygon, tagged with the wall it came from.
    struct Shape {
        var polygon: [Point2]
        var wall: WallRef?
    }

    /// The boundary of (union of `solids`) minus (union of `cuts`), as merged line segments.
    static func boundary(solids: [Shape], cuts: [Shape]) -> [Segment2] {
        let solidPolys = solids.map(\.polygon).filter { $0.count >= 3 }
        let cutPolys = cuts.map(\.polygon).filter { $0.count >= 3 }
        let edges = (solidPolys + cutPolys).flatMap { p in
            p.indices.map { Segment2(p[$0], p[($0 + 1) % p.count]) }
        }.filter { $0.length > 1e-6 }

        func filled(_ q: Point2) -> Bool {
            solidPolys.contains { contains($0, q) } && !cutPolys.contains { contains($0, q) }
        }

        var out: [Segment2] = []
        for (i, e) in edges.enumerated() {
            let length = e.length, d = e.direction, n = d.perpendicular
            var ts: [Double] = [0, length]
            for (j, f) in edges.enumerated() where j != i {
                if let t = crossing(e, f) { ts.append(t) }
                for p in [f.start, f.end] where e.distance(to: p) < 1e-7 { ts.append(e.distanceAlong(p)) }
            }
            ts = ts.map { min(max($0, 0), length) }.sorted()

            var run: (Double, Double)?
            func flush() {
                if let r = run, r.1 - r.0 > 1e-5 { out.append(Segment2(e.point(atDistance: r.0), e.point(atDistance: r.1))) }
                run = nil
            }
            for k in 0..<(ts.count - 1) {
                let a = ts[k], b = ts[k + 1]
                guard b - a > 1e-7 else { continue }
                let m = e.point(atDistance: (a + b) / 2)
                let eps = 1e-4
                var draw = filled(m + n * eps) != filled(m - n * eps)
                // Two edges lying on top of each other: only the first one draws.
                if draw, edges.prefix(i).contains(where: { abs($0.direction.cross(d)) < 1e-6 && $0.distance(to: m) < 1e-7 }) {
                    draw = false
                }
                if draw {
                    if let r = run, abs(r.1 - a) < 1e-7 { run = (r.0, b) } else { flush(); run = (a, b) }
                } else {
                    flush()
                }
            }
            flush()
        }
        return out
    }

    /// Distance along `e` where it crosses `f` (not parallel), or nil.
    private static func crossing(_ e: Segment2, _ f: Segment2) -> Double? {
        let r = e.vector, s = f.vector
        let denom = r.cross(s)
        guard abs(denom) > 1e-12 else { return nil }
        let w = f.start - e.start
        let t = w.cross(s) / denom, u = w.cross(r) / denom
        guard t >= -1e-9, t <= 1 + 1e-9, u >= -1e-9, u <= 1 + 1e-9 else { return nil }
        return t * e.length
    }

    /// Nearest distance along a ray to any edge of the shapes, ignoring shapes of `exclude`.
    static func rayHit(from p: Point2, direction d: Point2, shapes: [Shape], exclude: WallRef) -> Double? {
        var best: Double?
        for s in shapes where s.wall != exclude {
            let poly = s.polygon
            for k in poly.indices {
                if let t = PlanGeometry.rayDistance(from: p, direction: d, to: Segment2(poly[k], poly[(k + 1) % poly.count])),
                   best == nil || t < best! {
                    best = t
                }
            }
        }
        return best
    }
}
