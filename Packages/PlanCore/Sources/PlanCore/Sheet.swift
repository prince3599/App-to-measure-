import Foundation

/// Paper size and drawing scale for permit sheets.
public enum SheetLayout {
    /// ANSI B / tabloid, landscape: 17 x 11 inches, in points.
    public static let pageSize = (width: 17.0 * 72, height: 11.0 * 72)
    public static let margin = 0.5 * 72
    /// Title block strip down the right-hand side.
    public static let titleBlockWidth = 3.0 * 72

    /// Drawing area in points (inside the margins, left of the title block).
    public static var drawingArea: (x: Double, y: Double, width: Double, height: Double) {
        (margin, margin, pageSize.width - 2 * margin - titleBlockWidth, pageSize.height - 2 * margin)
    }

    public struct Scale: Equatable, Sendable {
        /// Real size divided by paper size, e.g. 48 for 1/4" = 1'-0".
        public var ratio: Double
        public var label: String

        /// Paper points per real metre.
        public var pointsPerMetre: Double { 72 / 0.0254 / ratio }
    }

    public static func scales(for unit: LengthUnit) -> [Scale] {
        switch unit {
        case .inches:
            return [Scale(ratio: 48, label: "1/4\" = 1'-0\""), Scale(ratio: 64, label: "3/16\" = 1'-0\""),
                    Scale(ratio: 96, label: "1/8\" = 1'-0\""), Scale(ratio: 192, label: "1/16\" = 1'-0\"")]
        case .millimetres:
            return [Scale(ratio: 50, label: "1:50"), Scale(ratio: 100, label: "1:100"), Scale(ratio: 200, label: "1:200")]
        }
    }

    /// The largest standard scale at which a drawing of the given size (metres) fits the drawing area.
    public static func scale(forWidth width: Double, height: Double, unit: LengthUnit) -> Scale {
        let area = drawingArea
        let options = scales(for: unit)
        return options.first { width * $0.pointsPerMetre <= area.width - 36 && height * $0.pointsPerMetre <= area.height - 36 }
            ?? options[options.count - 1]
    }
}

public enum DrawingExtents {
    public static func of(_ items: [DrawingItem]) -> (min: Point2, max: Point2)? {
        var lo = Point2(.infinity, .infinity), hi = Point2(-.infinity, -.infinity)
        for item in items {
            let pts: [Point2]
            switch item.primitive {
            case let .line(a, b): pts = [a, b]
            case let .arc(c, r, _, _): pts = [c - Point2(r, r), c + Point2(r, r)]
            case let .text(at, h, s, _): pts = [at - Point2(Double(s.count) * h * 0.35, h), at + Point2(Double(s.count) * h * 0.35, h)]
            }
            for p in pts {
                lo = Point2(min(lo.x, p.x), min(lo.y, p.y))
                hi = Point2(max(hi.x, p.x), max(hi.y, p.y))
            }
        }
        return lo.x.isFinite ? (lo, hi) : nil
    }
}

extension HouseProject {
    /// Title block lines for one floor's sheet.
    public func titleLines(for floor: Floor, sheet: Int, of sheets: Int, scale: String?, date: Date = Date()) -> [String] {
        let df = DateFormatter()
        df.dateStyle = .medium
        var lines = [name.uppercased()]
        if !address.isEmpty { lines.append(address) }
        if !owner.isEmpty { lines.append("Owner: \(owner)") }
        lines.append("\(floor.name.uppercased()) PLAN")
        lines.append("Net floor area: \(unit.formatArea(floor.netArea))")
        if let scale { lines.append("Scale: \(scale)") }
        lines.append("Date: \(df.string(from: date))")
        if !preparedBy.isEmpty { lines.append("Prepared by: \(preparedBy)") }
        lines.append("Sheet A-\(100 + sheet) (\(sheet) of \(sheets))")
        lines.append("Measured by LiDAR scan. Verify all dimensions on site.")
        return lines
    }

    public func drawing(for floor: Floor) -> PlanDrawing {
        var d = PlanDrawing(unit: unit)
        d.showFurniture = showFurniture
        d.interiorWallThickness = interiorWallThickness
        // Every wall is drawn at the house's standard thickness unless the user changed that wall.
        d.exteriorWallThickness = interiorWallThickness
        return d
    }
}

extension DXFWriter {
    /// One floor at 1:1 with a text title block under the plan.
    public func write(floor: Floor, of project: HouseProject, sheet: Int = 1, of sheets: Int = 1) -> String {
        var items = project.drawing(for: floor).items(for: floor)
        if let ext = DrawingExtents.of(items) {
            let h = 0.2
            let lines = project.titleLines(for: floor, sheet: sheet, of: sheets,
                                           scale: unit == .millimetres ? "1:1 (mm)" : "1:1 (inches)")
            for (i, line) in lines.enumerated() {
                let p = Point2(ext.min.x + Double(line.count) * h * 0.35, ext.min.y - 1.0 - Double(i) * h * 1.8)
                items.append(DrawingItem(layer: .annotation, primitive: .text(at: p, height: h, string: line, rotation: 0)))
            }
        }
        return write(items)
    }
}
