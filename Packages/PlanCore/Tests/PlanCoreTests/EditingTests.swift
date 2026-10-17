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
}
