import XCTest
@testable import PlanCore

final class EditingTests: XCTestCase {
    private let floor = SampleData.house.floors[0]

    func testSnappingPutsAMisplacedRoomBack() {
        let kitchen = floor.rooms[1]
        let misplaced = floor
            .rotatingRoom(1, by: 3 * .pi / 180)
            .movingRoom(1, by: Point2(0.4, 0.25))
        let living = Floor(name: "Test", rooms: [floor.rooms[0], misplaced.rooms[1]])
        let snapped = try XCTUnwrap(living.snappingRoom(1))
        for (a, b) in zip(snapped.rooms[1].plan.walls, kitchen.plan.walls) {
            XCTAssertEqual(a.line.start.distance(to: b.line.start), 0, accuracy: 1e-6)
            XCTAssertEqual(a.line.end.distance(to: b.line.end), 0, accuracy: 1e-6)
        }
    }

    func testSnappingNeedsANearbyWall() {
        let far = floor.movingRoom(1, by: Point2(20, 0))
        XCTAssertNil(Floor(name: "Test", rooms: [far.rooms[0], far.rooms[1]]).snappingRoom(1))
    }

    func testSettingOneWallLengthKeepsTheRoomRectangular() {
        let living = floor.rooms[0].plan
        let edited = living.settingLength(ofWall: 0, to: 6)
        XCTAssertEqual(edited.walls[0].line.length, 6, accuracy: 1e-9)
        XCTAssertEqual(edited.walls[2].line.length, 6, accuracy: 1e-9)
        XCTAssertEqual(edited.walls[1].line.start.distance(to: Point2(6, 0)), 0, accuracy: 1e-9)
        XCTAssertEqual(edited.area, 24, accuracy: 1e-9)
        // The door in the top wall stays where it was.
        let door = edited.openings[3]
        XCTAssertEqual(edited.walls[door.wallIndex].line.point(atDistance: door.offset).distance(to: Point2(3.6, 4)), 0, accuracy: 1e-9)
    }

    func testHitTesting() {
        XCTAssertEqual(floor.hit(at: Point2(1.2, 0.02), tolerance: 0.2), .opening(room: 0, index: 0))
        XCTAssertEqual(floor.hit(at: Point2(0.02, 2.0), tolerance: 0.2), .wall(WallRef(room: 0, wall: 3)))
        XCTAssertEqual(floor.hit(at: Point2(6.5, 2.0), tolerance: 0.2), .room(1))
        XCTAssertNil(floor.hit(at: Point2(50, 50), tolerance: 0.2))
    }

    func testDoubleDoorDrawsTwoLeaves() {
        var plan = floor.rooms[0].plan
        plan.openings[0].leaves = 2
        let arcs = PlanDrawing().items(for: plan).filter { if case .arc = $0.primitive { return true } else { return false } }
        XCTAssertEqual(arcs.count, 4) // front door now has two leaves, plus two other doors
    }

    func testOldOpeningsStillDecode() throws {
        let json = #"{"kind":"door","wallIndex":0,"offset":1,"width":0.9,"height":2}"#
        let o = try JSONDecoder().decode(Opening.self, from: Data(json.utf8))
        XCTAssertEqual(o.leaves, 1)
        XCTAssertFalse(o.swingsOut)
    }

    func testAddingMovingAndRemovingAWallPoint() throws {
        let living = floor.rooms[0].plan
        let split = try XCTUnwrap(living.splittingWall(0, at: Point2(2.5, 0.03)))
        XCTAssertEqual(split.walls.count, living.walls.count + 1)
        XCTAssertEqual(split.walls[0].line.end.distance(to: Point2(2.5, 0)), 0, accuracy: 1e-9)
        XCTAssertEqual(split.openings[0].wallIndex, 0)
        XCTAssertEqual(split.area, living.area, accuracy: 1e-9)
        XCTAssertNil(living.splittingWall(0, at: Point2(0.05, 0)))

        let bent = split.movingPoint(Point2(2.5, 0), to: Point2(2.5, -1))
        XCTAssertEqual(bent.area, living.area + 2.5, accuracy: 1e-9)

        let restored = try XCTUnwrap(split.removingPoint(Point2(2.5, 0)))
        XCTAssertEqual(restored.walls, living.walls)
        for (a, b) in zip(restored.openings, living.openings) {
            XCTAssertEqual(a.wallIndex, b.wallIndex)
            XCTAssertEqual(a.offset, b.offset, accuracy: 1e-9)
        }

        // Removing a corner joins its two walls with a diagonal.
        let cut = try XCTUnwrap(living.removingPoint(Point2(0, 0)))
        XCTAssertEqual(cut.walls.count, 3)
        XCTAssertEqual(cut.area, 10, accuracy: 1e-9)

        let hit = try XCTUnwrap(floor.pointHit(at: Point2(4.98, 0.03), tolerance: 0.1))
        XCTAssertEqual(hit.room, 0)
        XCTAssertEqual(hit.point.distance(to: Point2(5, 0)), 0, accuracy: 1e-6)
    }

    func testClosingAndDrawingMissingWalls() throws {
        let living = floor.rooms[0].plan
        // The scan missed most of the top wall.
        var broken = living
        broken.walls[2].line = Segment2(Point2(5, 4), Point2(3.5, 4))
        broken.walls[3].line = Segment2(Point2(0, 3.0), Point2(0, 0))
        broken.openings.removeAll { $0.wallIndex == 2 }
        XCTAssertEqual(broken.freeEnds.count, 2)

        let closed = broken.closingGaps(maxGap: 4)
        XCTAssertEqual(closed.added, 1)
        XCTAssertTrue(closed.plan.freeEnds.isEmpty)

        let drawn = try XCTUnwrap(broken.addingWall(from: Point2(3.4, 4.1), to: Point2(0.1, 3.05)))
        XCTAssertTrue(drawn.freeEnds.isEmpty)
        XCTAssertNil(broken.addingWall(from: Point2(1, 1), to: Point2(1.02, 1)))

        let removed = living.removingWall(0)
        XCTAssertEqual(removed.walls.count, 3)
        XCTAssertFalse(removed.openings.contains { $0.wallIndex >= 3 })
    }
}
