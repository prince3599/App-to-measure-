import PlanCore
import RoomPlan
import simd

/// Converts RoomPlan's 3D result into top-view items for `PlanBuilder`.
///
/// RoomPlan uses a right-handed, y-up world in metres. Looking down from above,
/// world +x becomes plan +x and world -z becomes plan +y.
enum RoomPlanConverter {
    static func items(from room: CapturedRoom) -> [ScannedItem] {
        var items: [ScannedItem] = []
        items += room.walls.map { surface($0, .wall) }
        items += room.doors.map { surface($0, .door) }
        items += room.windows.map { surface($0, .window) }
        items += room.openings.map { surface($0, .opening) }
        items += room.objects.map { object in
            let (center, direction) = planPose(object.transform)
            return ScannedItem(kind: .object(label: String(describing: object.category)),
                               center: center, direction: direction,
                               width: Double(object.dimensions.x), depth: Double(object.dimensions.z))
        }
        return items
    }

    private static func surface(_ s: CapturedRoom.Surface, _ kind: ScannedItem.Kind) -> ScannedItem {
        let (center, direction) = planPose(s.transform)
        return ScannedItem(kind: kind, center: center, direction: direction, width: Double(s.dimensions.x))
    }

    /// Position and width axis (the transform's local x) projected onto the floor.
    private static func planPose(_ t: simd_float4x4) -> (Point2, Point2) {
        let p = t.columns.3, x = t.columns.0
        return (Point2(Double(p.x), Double(-p.z)), Point2(Double(x.x), Double(-x.z)))
    }
}
