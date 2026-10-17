import PlanCore
import UIKit

/// Renders permit sheets: one 11 x 17 in page per floor, drawn to a standard scale, with a title block.
enum PermitPDF {
    static func write(project: HouseProject, floors: [(index: Int, floor: Floor)], to url: URL) throws {
        let page = CGRect(x: 0, y: 0, width: SheetLayout.pageSize.width, height: SheetLayout.pageSize.height)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "\(project.name) permit plans",
                               kCGPDFContextCreator as String: "MeasurePlan"]
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        try renderer.writePDF(to: url) { context in
            for entry in floors {
                context.beginPage()
                drawSheet(project: project, floor: entry.floor, sheet: entry.index + 1, in: context.cgContext)
            }
        }
    }

    private static func drawSheet(project: HouseProject, floor: Floor, sheet: Int, in cg: CGContext) {
        let items = project.drawing(for: floor).items(for: floor)
        let area = SheetLayout.drawingArea
        let m = SheetLayout.margin
        let page = SheetLayout.pageSize

        // Border and title block frame.
        cg.setStrokeColor(UIColor.black.cgColor)
        cg.setLineWidth(1.2)
        cg.stroke(CGRect(x: m, y: m, width: page.width - 2 * m, height: page.height - 2 * m))
        let tbX = page.width - m - SheetLayout.titleBlockWidth
        cg.move(to: CGPoint(x: tbX, y: m))
        cg.addLine(to: CGPoint(x: tbX, y: page.height - m))
        cg.strokePath()

        var scaleLabel: String?
        if let ext = DrawingExtents.of(items) {
            let scale = SheetLayout.scale(forWidth: ext.max.x - ext.min.x, height: ext.max.y - ext.min.y, unit: project.unit)
            scaleLabel = scale.label
            let k = scale.pointsPerMetre
            let mid = (ext.min + ext.max) / 2
            let cx = area.x + area.width / 2, cy = area.y + area.height / 2
            func pt(_ p: Point2) -> CGPoint { CGPoint(x: cx + (p.x - mid.x) * k, y: cy - (p.y - mid.y) * k) }
            for item in items {
                draw(item, in: cg, k: k, pt: pt)
            }
        }

        titleBlock(project: project, floor: floor, sheet: sheet, scale: scaleLabel,
                   in: CGRect(x: tbX, y: m, width: SheetLayout.titleBlockWidth, height: page.height - 2 * m), cg: cg)
    }

    private static func draw(_ item: DrawingItem, in cg: CGContext, k: Double, pt: (Point2) -> CGPoint) {
        let color: UIColor = item.layer == .furniture ? .darkGray : .black
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(item.layer == .wall ? 1.0 : 0.4)
        switch item.primitive {
        case let .line(a, b):
            cg.move(to: pt(a))
            cg.addLine(to: pt(b))
            cg.strokePath()
        case let .arc(center, radius, start, end):
            let sweep = end >= start ? end - start : end - start + 2 * .pi
            for step in 0...24 {
                let a = start + sweep * Double(step) / 24
                let p = pt(center + Point2(cos(a), sin(a)) * radius)
                if step == 0 { cg.move(to: p) } else { cg.addLine(to: p) }
            }
            cg.strokePath()
        case let .text(at, height, string, rotation):
            let font = UIFont.systemFont(ofSize: max(height * k, 4))
            let text = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
            let size = text.size()
            let p = pt(at)
            cg.saveGState()
            cg.translateBy(x: p.x, y: p.y)
            cg.rotate(by: -rotation)
            text.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
            cg.restoreGState()
        }
    }

    private static func titleBlock(project: HouseProject, floor: Floor, sheet: Int, scale: String?, in rect: CGRect, cg: CGContext) {
        let lines = project.titleLines(for: floor, sheet: sheet, of: project.floors.count, scale: scale)
        var y = rect.minY + 14
        for (i, line) in lines.enumerated() {
            let font = i == 0 ? UIFont.boldSystemFont(ofSize: 14) : UIFont.systemFont(ofSize: i == lines.count - 1 ? 7 : 9)
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            let text = NSAttributedString(string: line, attributes: [.font: font, .paragraphStyle: style])
            let box = CGRect(x: rect.minX + 10, y: y, width: rect.width - 20, height: 200)
            let height = ceil(text.boundingRect(with: box.size, options: [.usesLineFragmentOrigin], context: nil).height)
            text.draw(with: box, options: [.usesLineFragmentOrigin], context: nil)
            y += height + (i == 0 ? 10 : 6)
        }

        // North arrow, pointing up the sheet. Rotate it to match the site.
        let c = CGPoint(x: rect.midX, y: rect.maxY - 60)
        cg.setFillColor(UIColor.black.cgColor)
        cg.move(to: CGPoint(x: c.x, y: c.y - 26))
        cg.addLine(to: CGPoint(x: c.x + 10, y: c.y + 14))
        cg.addLine(to: CGPoint(x: c.x, y: c.y + 6))
        cg.addLine(to: CGPoint(x: c.x - 10, y: c.y + 14))
        cg.closePath()
        cg.fillPath()
        let n = NSAttributedString(string: "N", attributes: [.font: UIFont.boldSystemFont(ofSize: 12)])
        n.draw(at: CGPoint(x: c.x - n.size().width / 2, y: c.y - 44))
        let note = NSAttributedString(string: "Verify north on site", attributes: [.font: UIFont.systemFont(ofSize: 7)])
        note.draw(at: CGPoint(x: c.x - note.size().width / 2, y: c.y + 20))
    }
}
