import Foundation

/// A 2D point in plan space, in metres. +x is east, +y is north (top of the drawing).
public struct Point2: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point2(0, 0)

    public static func + (a: Point2, b: Point2) -> Point2 { Point2(a.x + b.x, a.y + b.y) }
    public static func - (a: Point2, b: Point2) -> Point2 { Point2(a.x - b.x, a.y - b.y) }
    public static func * (a: Point2, s: Double) -> Point2 { Point2(a.x * s, a.y * s) }
    public static func / (a: Point2, s: Double) -> Point2 { Point2(a.x / s, a.y / s) }

    public var length: Double { (x * x + y * y).squareRoot() }
    public var normalized: Point2 { length > 0 ? self / length : self }
    /// Rotated 90 degrees counter-clockwise.
    public var perpendicular: Point2 { Point2(-y, x) }
    /// Angle from +x axis, in radians.
    public var angle: Double { atan2(y, x) }

    public func dot(_ o: Point2) -> Double { x * o.x + y * o.y }
    public func cross(_ o: Point2) -> Double { x * o.y - y * o.x }
    public func distance(to o: Point2) -> Double { (self - o).length }
}

public struct Segment2: Codable, Equatable, Sendable {
    public var start: Point2
    public var end: Point2

    public init(_ start: Point2, _ end: Point2) {
        self.start = start
        self.end = end
    }

    public var vector: Point2 { end - start }
    public var length: Double { vector.length }
    public var direction: Point2 { vector.normalized }
    public var midpoint: Point2 { (start + end) / 2 }

    /// Parameter along the segment (0 at start, `length` at end) of the closest point to `p`, unclamped.
    public func distanceAlong(_ p: Point2) -> Double { (p - start).dot(direction) }

    public func point(atDistance d: Double) -> Point2 { start + direction * d }

    public func distance(to p: Point2) -> Double {
        let t = min(max(distanceAlong(p), 0), length)
        return point(atDistance: t).distance(to: p)
    }

    public func offset(by d: Double, along normal: Point2) -> Segment2 {
        Segment2(start + normal * d, end + normal * d)
    }

    /// Intersection of the two infinite lines, or nil when they are (nearly) parallel.
    public func lineIntersection(_ o: Segment2) -> Point2? {
        let r = vector, s = o.vector
        let denom = r.cross(s)
        guard abs(denom) > 1e-9 * r.length * s.length else { return nil }
        let t = (o.start - start).cross(s) / denom
        return start + r * t
    }
}
