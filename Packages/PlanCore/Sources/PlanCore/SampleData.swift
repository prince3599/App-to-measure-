import Foundation

public enum SampleData {
    /// A 4.0 x 3.2 m bedroom whose scanned walls don't quite meet, with a door, a window and a bed.
    /// Used by tests and by the app's "sample room" button on devices without LiDAR.
    public static let bedroomItems: [ScannedItem] = [
        ScannedItem(kind: .wall, center: Point2(2.0, 0.0), direction: Point2(1, 0), width: 3.9),
        ScannedItem(kind: .wall, center: Point2(4.0, 1.6), direction: Point2(0, 1), width: 3.3),
        ScannedItem(kind: .wall, center: Point2(2.0, 3.2), direction: Point2(-1, 0), width: 4.1),
        ScannedItem(kind: .wall, center: Point2(0.0, 1.6), direction: Point2(0, -1), width: 3.1),
        ScannedItem(kind: .door, center: Point2(0.8, 0.0), direction: Point2(1, 0), width: 0.9),
        ScannedItem(kind: .window, center: Point2(4.0, 1.8), direction: Point2(0, 1), width: 1.2),
        ScannedItem(kind: .object(label: "bed"), center: Point2(2.3, 2.1), direction: Point2(1, 0), width: 2.0, depth: 1.6),
    ]
}

extension SampleData {
    /// Four walls of a rectangular room, slightly short at the corners like a real scan.
    static func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, height: Double = 2.44) -> [ScannedItem] {
        let w = x1 - x0, h = y1 - y0, cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
        return [
            ScannedItem(kind: .wall, center: Point2(cx, y0), direction: Point2(1, 0), width: w - 0.06, height: height),
            ScannedItem(kind: .wall, center: Point2(x1, cy), direction: Point2(0, 1), width: h - 0.06, height: height),
            ScannedItem(kind: .wall, center: Point2(cx, y1), direction: Point2(-1, 0), width: w - 0.06, height: height),
            ScannedItem(kind: .wall, center: Point2(x0, cy), direction: Point2(0, -1), width: h - 0.06, height: height),
        ]
    }

    static func door(_ x: Double, _ y: Double, along d: Point2, width: Double = 0.9) -> ScannedItem {
        ScannedItem(kind: .door, center: Point2(x, y), direction: d, width: width, height: 2.03)
    }

    static func window(_ x: Double, _ y: Double, along d: Point2, width: Double, height: Double = 1.2) -> ScannedItem {
        ScannedItem(kind: .window, center: Point2(x, y), direction: d, width: width, height: height)
    }

    static func object(_ label: String, _ x: Double, _ y: Double, _ w: Double, _ d: Double, along dir: Point2 = Point2(1, 0)) -> ScannedItem {
        ScannedItem(kind: .object(label: label), center: Point2(x, y), direction: dir, width: w, depth: d)
    }

    static func room(_ name: String, _ items: [ScannedItem]) -> Room {
        Room(name: name, plan: PlanBuilder().build(from: items))
    }

    /// A two-storey house with 120 mm interior walls, for trying the app without LiDAR.
    public static var house: HouseProject {
        let x = Point2(1, 0), y = Point2(0, 1)
        let first = Floor(name: "First Floor", rooms: [
            room("Living Room", box(0, 0, 5, 4) + [
                door(1.2, 0, along: x), window(3.5, 0, along: x, width: 1.5),
                door(5, 2.0, along: y), door(3.6, 4, along: x),
                object("sofa", 2.5, 3.4, 2.2, 0.9),
            ]),
            room("Kitchen", box(5.12, 0, 8.62, 4) + [
                door(5.12, 2.0, along: y), window(8.62, 2.0, along: y, width: 1.2),
                object("stove", 6.0, 3.65, 0.76, 0.65), object("refrigerator", 7.0, 3.6, 0.9, 0.75),
                object("sink", 8.25, 1.0, 0.6, 0.55, along: y),
            ]),
            room("Bathroom", box(0, 4.12, 2.5, 6.62) + [
                window(0, 5.4, along: y, width: 0.6, height: 0.9),
                object("toilet", 0.45, 6.25, 0.4, 0.7), object("sink", 1.5, 6.35, 0.6, 0.45),
            ]),
            room("Hall", box(2.62, 4.12, 8.62, 6.62) + [
                door(2.62, 5.4, along: y, width: 0.8),
                object("stairs", 7.3, 5.37, 1.0, 2.5, along: y),
            ]),
        ], isComplete: true)
        let second = Floor(name: "Second Floor", rooms: [
            room("Bedroom", box(0, 0, 4.5, 4) + [
                window(2.25, 0, along: x, width: 1.5), door(3.6, 4, along: x, width: 0.8),
                object("bed", 2.25, 2.6, 1.6, 2.0, along: x),
            ]),
            room("Bedroom 2", box(4.62, 0, 8.62, 4) + [
                window(6.6, 0, along: x, width: 1.2), door(5.4, 4, along: x, width: 0.8),
            ]),
            room("Bathroom", box(0, 4.12, 2.5, 6.62) + [
                window(0, 5.4, along: y, width: 0.6, height: 0.9), door(2.5, 5.4, along: y, width: 0.8),
                object("bathtub", 1.25, 6.25, 1.5, 0.7), object("toilet", 2.1, 4.6, 0.4, 0.7, along: y),
            ]),
            room("Hall", box(2.62, 4.12, 8.62, 6.62) + [
                object("stairs", 7.3, 5.37, 1.0, 2.5, along: y),
            ]),
        ], isComplete: true)
        return HouseProject(name: "Sample House", address: "123 Example Street", owner: "Sample Owner",
                            preparedBy: "MeasurePlan", unit: .inches, floors: [first, second])
    }
}
