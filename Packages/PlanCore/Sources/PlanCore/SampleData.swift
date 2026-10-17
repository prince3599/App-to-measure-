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
