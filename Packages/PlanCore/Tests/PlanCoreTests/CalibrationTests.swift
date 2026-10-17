import XCTest
@testable import PlanCore

final class CalibrationTests: XCTestCase {
    func testCalibratingOneWallScalesTheWholePlan() {
        let plan = PlanBuilder().build(from: SampleData.bedroomItems)
        let fixed = plan.calibrated(wall: 0, to: 4.2) // scanned 4.0 m, tape says 4.2 m
        XCTAssertEqual(fixed.walls[0].line.length, 4.2, accuracy: 1e-9)
        XCTAssertEqual(fixed.walls[1].line.length, 3.2 * 1.05, accuracy: 1e-9)
        XCTAssertEqual(fixed.openings[0].width, 0.9 * 1.05, accuracy: 1e-9)
        XCTAssertEqual(fixed.objects[0].width, 2.0 * 1.05, accuracy: 1e-9)
        XCTAssertEqual(fixed.walls[0].thickness, plan.walls[0].thickness)
        XCTAssertEqual(fixed.centroid.distance(to: plan.centroid), 0, accuracy: 1e-9)
    }

    func testInvalidCalibrationLeavesPlanUnchanged() {
        let plan = PlanBuilder().build(from: SampleData.bedroomItems)
        XCTAssertEqual(plan.calibrated(wall: 99, to: 3), plan)
        XCTAssertEqual(plan.calibrated(wall: 0, to: 0), plan)
    }

    func testParsingLengths() {
        XCTAssertEqual(LengthUnit.millimetres.parse("3650")!, 3.65, accuracy: 1e-9)
        XCTAssertNil(LengthUnit.millimetres.parse("abc"))
        XCTAssertEqual(LengthUnit.inches.parse("120")!, 120 * 0.0254, accuracy: 1e-9)
        XCTAssertEqual(LengthUnit.inches.parse("10'")!, 120 * 0.0254, accuracy: 1e-9)
        XCTAssertEqual(LengthUnit.inches.parse("10'6")!, 126 * 0.0254, accuracy: 1e-9)
        XCTAssertEqual(LengthUnit.inches.parse("10' 6\"")!, 126 * 0.0254, accuracy: 1e-9)
        XCTAssertEqual(LengthUnit.inches.parse("10’-6.5”")!, 126.5 * 0.0254, accuracy: 1e-9)
        XCTAssertNil(LengthUnit.inches.parse("ten feet"))
    }
}
