import XCTest
@testable import PlanCore

final class HouseTests: XCTestCase {
    func testSharedWallsAreFound() {
        let floor = SampleData.house.floors[0]
        let analysis = WallAnalysis(rooms: floor.rooms.map(\.plan))
        // Living room's right wall backs onto the kitchen through a 120 mm wall.
        let living = analysis.info[0][1]
        XCTAssertEqual(living.shared.count, 1)
        XCTAssertEqual(living.shared[0].neighbor, WallRef(room: 1, wall: 3))
        XCTAssertEqual(living.shared[0].thickness, 0.12, accuracy: 1e-9)
        // Its front wall is exterior.
        XCTAssertTrue(analysis.info[0][0].shared.isEmpty)
        XCTAssertEqual(analysis.info[0][0].exteriorFraction(length: 5), 1, accuracy: 1e-9)
    }

    func testFloorArea() {
        XCTAssertEqual(SampleData.house.floors[0].netArea, 55.25, accuracy: 1e-6)
    }

    func testDoorBetweenRoomsIsDrawnOnce() {
        let items = PlanDrawing(unit: .inches).items(for: SampleData.house.floors[0])
        let arcs = items.filter { if case .arc = $0.primitive { return true } else { return false } }
        XCTAssertEqual(arcs.count, 4)
    }

    func testScheduleNumbersEachDoorAndWindowOnce() {
        let floor = SampleData.house.floors[0]
        let drawing = PlanDrawing(unit: .inches)
        let schedule = drawing.schedule(for: floor)
        let doors = schedule.filter { $0.kind == .door }, windows = schedule.filter { $0.kind == .window }
        XCTAssertEqual(doors.map(\.tag), (1...doors.count).map { "D\($0)" })
        XCTAssertEqual(windows.map(\.tag), (1...windows.count).map { "W\($0)" })
        // The plan shows each tag exactly once.
        let texts = drawing.items(for: floor).compactMap { item -> String? in
            if case let .text(_, _, s, _) = item.primitive { return s } else { return nil }
        }
        for entry in schedule {
            XCTAssertEqual(texts.filter { $0 == entry.tag }.count, 1, entry.tag)
        }
        XCTAssertEqual(SampleData.house.scheduleRows(for: floor).count, schedule.count)
    }

    func testCalibratingAFloorScalesEveryRoom() {
        let floor = SampleData.house.floors[0]
        let wall = floor.rooms[0].plan.walls[0].line.length
        let fixed = floor.calibrated(room: 0, wall: 0, to: wall * 1.1)
        XCTAssertEqual(fixed.rooms[1].plan.walls[0].line.length, floor.rooms[1].plan.walls[0].line.length * 1.1, accuracy: 1e-9)
        XCTAssertEqual(fixed.netArea, floor.netArea * 1.21, accuracy: 1e-6)
    }

    func testUniqueRoomNames() {
        let floor = SampleData.house.floors[1]
        XCTAssertEqual(floor.uniqueRoomName("Bedroom"), "Bedroom 3")
        XCTAssertEqual(floor.uniqueRoomName("Office"), "Office")
    }

    func testSheetScale() {
        XCTAssertEqual(SheetLayout.scale(forWidth: 10, height: 8, unit: .inches).ratio, 48)
        XCTAssertEqual(SheetLayout.scale(forWidth: 30, height: 20, unit: .inches).ratio, 96)
        XCTAssertEqual(SheetLayout.scale(forWidth: 10, height: 8, unit: .millimetres).ratio, 50)
    }
}
