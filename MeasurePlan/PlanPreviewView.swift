import PlanCore
import SwiftUI

/// Draws the same layered line work that goes into the DXF file. Pinch to zoom, drag to pan.
struct PlanPreviewView: View {
    var plan: FloorPlan
    var unit: LengthUnit

    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero

    var body: some View {
        let items = PlanDrawing(unit: unit).items(for: plan)
        Canvas { context, size in
            guard let extents = Self.extents(of: items) else { return }
            let (lo, hi) = extents
            let w = max(hi.x - lo.x, 0.1), h = max(hi.y - lo.y, 0.1)
            let k = min(size.width / w, size.height / h) * 0.9 * zoom
            let origin = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
            let mid = (lo + hi) / 2
            // Plan y points up; screen y points down.
            func screen(_ p: Point2) -> CGPoint {
                CGPoint(x: origin.x + (p.x - mid.x) * k, y: origin.y - (p.y - mid.y) * k)
            }

            for item in items {
                let color = Self.color(for: item.layer)
                switch item.primitive {
                case let .line(a, b):
                    var path = Path()
                    path.move(to: screen(a))
                    path.addLine(to: screen(b))
                    context.stroke(path, with: .color(color), lineWidth: item.layer == .wall ? 1.5 : 1)
                case let .arc(center, radius, start, end):
                    let sweep = end >= start ? end - start : end - start + 2 * .pi
                    var path = Path()
                    for step in 0...24 {
                        let a = start + sweep * Double(step) / 24
                        let p = screen(center + Point2(cos(a), sin(a)) * radius)
                        if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    context.stroke(path, with: .color(color), lineWidth: 1)
                case let .text(at, height, string, rotation):
                    var c = context
                    c.translateBy(x: screen(at).x, y: screen(at).y)
                    c.rotate(by: .radians(-rotation))
                    c.draw(Text(string).font(.system(size: max(height * k, 6))).foregroundColor(color), at: .zero)
                }
            }
        }
        .gesture(
            MagnifyGesture()
                .onChanged { zoom = max(0.5, min(lastZoom * $0.magnification, 10)) }
                .onEnded { _ in lastZoom = zoom }
                .simultaneously(with: DragGesture()
                    .onChanged { pan = CGSize(width: lastPan.width + $0.translation.width,
                                              height: lastPan.height + $0.translation.height) }
                    .onEnded { _ in lastPan = pan })
        )
        .onTapGesture(count: 2) {
            zoom = 1; lastZoom = 1; pan = .zero; lastPan = .zero
        }
    }

    private static func color(for layer: Layer) -> Color {
        switch layer {
        case .wall: return .primary
        case .door: return .green
        case .glazing: return .cyan
        case .furniture: return .gray
        case .dimensions: return .red
        case .annotation: return .orange
        }
    }

    private static func extents(of items: [DrawingItem]) -> (Point2, Point2)? {
        var lo = Point2(.infinity, .infinity), hi = Point2(-.infinity, -.infinity)
        for item in items {
            let pts: [Point2]
            switch item.primitive {
            case let .line(a, b): pts = [a, b]
            case let .arc(c, r, _, _): pts = [c - Point2(r, r), c + Point2(r, r)]
            case let .text(at, _, _, _): pts = [at]
            }
            for p in pts {
                lo = Point2(min(lo.x, p.x), min(lo.y, p.y))
                hi = Point2(max(hi.x, p.x), max(hi.y, p.y))
            }
        }
        return lo.x.isFinite ? (lo, hi) : nil
    }
}
