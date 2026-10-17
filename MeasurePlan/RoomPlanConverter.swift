import PlanCore
import RoomPlan
import simd

/// Converts RoomPlan's 3D result into top-view items for `PlanBuilder`.
///
/// RoomPlan uses a right-handed, y-up world in metres. Looking down from above,
/// world +x becomes plan +x and world -z becomes plan +y.
enum RoomPlanConverter {
    static func room(from captured: CapturedRoom) -> Room {
        let label = captured.sections.first.map { String(describing: $0.label) } ?? "unidentified"
        let name = label == "unidentified" ? "Room" : prettify(label)
        let scan = items(from: captured)
        return Room(name: name, plan: PlanBuilder().build(from: scan), scan: scan)
    }

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
                               width: Double(object.dimensions.x), depth: Double(object.dimensions.z),
                               height: Double(object.dimensions.y))
        }
        return items
    }

    private static func surface(_ s: CapturedRoom.Surface, _ kind: ScannedItem.Kind) -> ScannedItem {
        let (center, direction) = planPose(s.transform)
        return ScannedItem(kind: kind, center: center, direction: direction,
                           width: Double(s.dimensions.x), height: Double(s.dimensions.y))
    }

    /// Position and width axis (the transform's local x) projected onto the floor.
    private static func planPose(_ t: simd_float4x4) -> (Point2, Point2) {
        let p = t.columns.3, x = t.columns.0
        return (Point2(Double(p.x), Double(-p.z)), Point2(Double(x.x), Double(-x.z)))
    }

    /// "livingRoom" -> "Living Room"
    private static func prettify(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch.isUppercase { out += " " }
            out.append(ch)
        }
        return out.prefix(1).uppercased() + String(out.dropFirst())
    }
}
