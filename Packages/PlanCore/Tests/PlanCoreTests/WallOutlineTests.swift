import XCTest
@testable import PlanCore

final class WallOutlineTests: XCTestCase {
    private func square(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> WallOutline.Shape {
        WallOutline.Shape(polygon: [Point2(x0, y0), Point2(x1, y0), Point2(x1, y1), Point2(x0, y1)], wall: nil)
    }

    private func perimeter(_ lines: [Segment2]) -> Double { lines.map(\.length).reduce(0, +) }

    func testOverlappingWallsDrawOneOutline() {
        let lines = WallOutline.boundary(solids: [square(0, 0, 2, 2), square(1, 1, 3, 3)], cuts: [])
        XCTAssertEqual(perimeter(lines), 12, accuracy: 1e-9)
    }

    func testCutsLeaveJambs() {
        let lines = WallOutline.boundary(solids: [square(0, 0, 4, 1)], cuts: [square(1, -1, 2, 2)])
        XCTAssertEqual(perimeter(lines), 10, accuracy: 1e-9)
    }

    func testTouchingWallsHideTheirJoint() {
        let lines = WallOutline.boundary(solids: [square(0, 0, 2, 1), square(2, 0, 4, 1), square(1, 0, 3, 1)], cuts: [])
        XCTAssertEqual(perimeter(lines), 10, accuracy: 1e-9)
    }

    func testNoWallLineInsideAnotherWall() {
        let floor = SampleData.house.floors[0]
        let items = PlanDrawing().items(for: floor).filter { $0.layer == .wall }
        // Every wall line lies on the room-side face of some room, or outside every room.
        for item in items {
            guard case let .line(a, b) = item.primitive else { continue }
            let m = (a + b) / 2
            for room in floor.rooms {
                let outline = room.plan.outline
                let onFace = room.plan.walls.contains { $0.line.distance(to: m) < 1e-6 }
                XCTAssertFalse(contains(outline, m) && !onFace, "wall line inside \(room.name)")
            }
        }
    }

    func testStandardWallThicknesses() {
        let floor = SampleData.house.floors[0]
        var drawing = PlanDrawing()
        drawing.interiorWallThickness = 0.127
        drawing.exteriorWallThickness = 0.254
        let lines: [(Point2, Point2)] = drawing.items(for: floor).compactMap {
            guard $0.layer == .wall, case let .line(a, b) = $0.primitive else { return nil }
            return (a, b)
        }
        func hasVerticalLine(atX x: Double) -> Bool {
            lines.contains { abs($0.0.x - x) < 1e-6 && abs($0.1.x - x) < 1e-6 && abs($0.0.y - $0.1.y) > 0.5 }
        }
        // Outside face of the living room's left wall, 10" out.
        XCTAssertTrue(hasVerticalLine(atX: -0.254))
        // Living room and kitchen faces are at 5.00 and 5.12: a 5" wall centred between them.
        XCTAssertTrue(hasVerticalLine(atX: 5.06 - 0.0635))
        XCTAssertTrue(hasVerticalLine(atX: 5.06 + 0.0635))
        XCTAssertFalse(hasVerticalLine(atX: 5.0))
    }
}
