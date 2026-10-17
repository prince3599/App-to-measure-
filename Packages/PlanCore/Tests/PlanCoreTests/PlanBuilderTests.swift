import XCTest
@testable import PlanCore

final class PlanBuilderTests: XCTestCase {
    static let sampleItems = SampleData.bedroomItems

    func testCornersAreJoined() {
        let plan = PlanBuilder().build(from: Self.sampleItems)
        XCTAssertEqual(plan.walls.count, 4)
        let expected: [(Point2, Point2)] = [
            (Point2(0, 0), Point2(4, 0)),
            (Point2(4, 0), Point2(4, 3.2)),
            (Point2(4, 3.2), Point2(0, 3.2)),
            (Point2(0, 3.2), Point2(0, 0)),
        ]
        for (wall, (s, e)) in zip(plan.walls, expected) {
            XCTAssertEqual(wall.line.start.distance(to: s), 0, accuracy: 1e-9)
            XCTAssertEqual(wall.line.end.distance(to: e), 0, accuracy: 1e-9)
        }
    }

    func testOpeningsAttachToNearestWall() {
        let plan = PlanBuilder().build(from: Self.sampleItems)
        XCTAssertEqual(plan.openings, [
            Opening(kind: .door, wallIndex: 0, offset: 0.8, width: 0.9),
            Opening(kind: .window, wallIndex: 1, offset: 1.8, width: 1.2),
        ])
    }

    func testObjectsKeepSizeAndLabel() {
        let plan = PlanBuilder().build(from: Self.sampleItems)
        XCTAssertEqual(plan.objects.count, 1)
        XCTAssertEqual(plan.objects[0].label, "bed")
        XCTAssertEqual(plan.objects[0].width, 2.0)
        XCTAssertEqual(plan.objects[0].depth, 1.6)
    }

    func testOuterFacesMeetAtCorners() {
        let plan = PlanBuilder().build(from: Self.sampleItems)
        let faces = PlanGeometry.outerFaces(of: plan)
        XCTAssertEqual(faces[0].start.distance(to: Point2(-0.1, -0.1)), 0, accuracy: 1e-9)
        XCTAssertEqual(faces[0].end.distance(to: Point2(4.1, -0.1)), 0, accuracy: 1e-9)
    }
}
