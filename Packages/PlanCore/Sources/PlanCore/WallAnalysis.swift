import Foundation

public struct WallRef: Equatable, Hashable, Sendable {
    public var room: Int
    public var wall: Int

    public init(room: Int, wall: Int) {
        self.room = room
        self.wall = wall
    }
}

/// A stretch of wall (distances along its room-side face) that has another scanned room behind it.
public struct SharedSpan: Equatable, Sendable {
    public var start: Double
    public var end: Double
    /// Distance to the neighbouring room's face: the real wall thickness here.
    public var thickness: Double
    public var neighbor: WallRef
}

public struct WallInfo: Equatable, Sendable {
    public var outward: Point2
    /// Thickness drawn where nothing is scanned behind the wall.
    public var exteriorThickness: Double
    public var shared: [SharedSpan]

    /// Wall thickness at a distance along the room-side face.
    public func thickness(at d: Double) -> Double {
        shared.first { d >= $0.start - 1e-6 && d <= $0.end + 1e-6 }?.thickness ?? exteriorThickness
    }

    /// Parts of the wall with nothing scanned behind them.
    public func exteriorRanges(length: Double) -> [(Double, Double)] {
        subtractRanges([(0, length)], shared.map { ($0.start, $0.end) })
    }

    public func exteriorFraction(length: Double) -> Double {
        guard length > 0 else { return 0 }
        return exteriorRanges(length: length).map { $0.1 - $0.0 }.reduce(0, +) / length
    }
}

/// Finds walls that two scanned rooms share, so a floor draws as one building
/// rather than a set of separate boxes.
public struct WallAnalysis: Sendable {
    public private(set) var info: [[WallInfo]]

    /// - Parameter maxThickness: room faces further apart than this are treated as separate walls.
    public init(rooms: [FloorPlan], maxThickness: Double = 0.45) {
        info = rooms.map { plan in
            plan.walls.map { w in
                WallInfo(outward: PlanGeometry.outwardNormal(of: w, roomCentroid: plan.centroid),
                         exteriorThickness: w.thickness, shared: [])
            }
        }
        for r in rooms.indices {
            for w in rooms[r].walls.indices {
                let line = rooms[r].walls[w].line
                let n = info[r][w].outward
                var spans: [SharedSpan] = []
                for r2 in rooms.indices where r2 != r {
                    for w2 in rooms[r2].walls.indices {
                        let other = rooms[r2].walls[w2].line
                        // Parallel (within about 11 degrees) and facing back towards this wall.
                        guard n.dot(info[r2][w2].outward) < -0.98 else { continue }
                        let d = (other.midpoint - line.start).dot(n)
                        guard d > 0.02, d <= maxThickness else { continue }
                        let a0 = line.distanceAlong(other.start), a1 = line.distanceAlong(other.end)
                        let s = max(min(a0, a1), 0), e = min(max(a0, a1), line.length)
                        guard e - s >= 0.2 else { continue }
                        spans.append(SharedSpan(start: s, end: e, thickness: d, neighbor: WallRef(room: r2, wall: w2)))
                    }
                }
                info[r][w].shared = spans.sorted { $0.start < $1.start }
            }
        }
    }
}

/// `ranges` with every interval in `cuts` removed. Both are (start, end) pairs.
func subtractRanges(_ ranges: [(Double, Double)], _ cuts: [(Double, Double)]) -> [(Double, Double)] {
    var result = ranges
    for (cs, ce) in cuts {
        result = result.flatMap { r -> [(Double, Double)] in
            if ce <= r.0 || cs >= r.1 { return [r] }
            var parts: [(Double, Double)] = []
            if cs > r.0 + 1e-6 { parts.append((r.0, min(cs, r.1))) }
            if ce < r.1 - 1e-6 { parts.append((max(ce, r.0), r.1)) }
            return parts.filter { $0.1 - $0.0 > 1e-6 }
        }
    }
    return result
}
