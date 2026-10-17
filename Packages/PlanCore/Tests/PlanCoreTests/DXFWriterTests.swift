import XCTest
@testable import PlanCore

final class DXFWriterTests: XCTestCase {
    private func pairs(_ dxf: String) -> [(Int, String)] {
        let lines = dxf.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return stride(from: 0, to: lines.count - 1, by: 2).map {
            (Int(lines[$0].trimmingCharacters(in: .whitespaces))!, lines[$0 + 1])
        }
    }

    func testFileStructure() {
        let plan = PlanBuilder().build(from: PlanBuilderTests.sampleItems)
        let p = pairs(DXFWriter().write(plan))
        XCTAssertEqual(p.first?.1, "SECTION")
        XCTAssertEqual(p.last?.1, "EOF")
        XCTAssertTrue(p.contains { $0 == (1, "AC1009") })
        for layer in Layer.allCases {
            XCTAssertTrue(p.contains { $0 == (2, layer.rawValue) }, "missing layer \(layer.rawValue)")
        }
    }

    func testEntityCountsForSampleRoom() {
        let plan = PlanBuilder().build(from: PlanBuilderTests.sampleItems)
        let p = pairs(DXFWriter().write(plan))
        let entities = p.filter { $0.0 == 0 }.map(\.1)
        XCTAssertEqual(entities.filter { $0 == "ARC" }.count, 1)       // door swing
        // 4 wall + 2 overall dimensions, bed, door and window tags, room size and area
        XCTAssertEqual(entities.filter { $0 == "TEXT" }.count, 11)
        XCTAssertEqual(entities.filter { $0 == "LINE" }.count, 49)
    }

    func testCoordinatesAreInMillimetres() {
        let plan = FloorPlan(walls: [Wall(line: Segment2(Point2(0, 0), Point2(2.5, 0)))])
        let dxf = DXFWriter().write(plan)
        XCTAssertTrue(dxf.contains("2500.0000"))
        XCTAssertTrue(dxf.contains("\n2500\n"))  // dimension text
    }

    func testImperialFormatting() {
        XCTAssertEqual(LengthUnit.inches.format(3.048), "10'-0\"")
        XCTAssertEqual(LengthUnit.millimetres.format(3.2044), "3204")
    }
}
