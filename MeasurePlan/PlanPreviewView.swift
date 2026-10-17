import PlanCore
import SwiftUI

/// Draws the same layered line work that goes into the PDF and DXF files.
/// Pinch to zoom, drag to pan, double-tap to reset, tap a wall to select it.
struct PlanPreviewView: View {
    var items: [DrawingItem]
    /// Room-side wall faces that can be tapped.
    var walls: [(WallRef, Segment2)]
    var selectedWall: WallRef?
    var onTapWall: ((WallRef) -> Void)?

    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero

    var body: some View {
        let extents = Self.extents(of: items)
        GeometryReader { geo in
            let layout = extents.map { Layout(extents: $0, size: geo.size, zoom: zoom, pan: pan) }
            Canvas { context, _ in
                guard let layout else { return }
                if let selectedWall, let line = walls.first(where: { $0.0 == selectedWall })?.1 {
                    var path = Path()
                    path.move(to: layout.screen(line.start))
                    path.addLine(to: layout.screen(line.end))
                    context.stroke(path, with: .color(.accentColor.opacity(0.5)), lineWidth: 10)
                }
                for item in items {
                    draw(item, in: context, layout: layout)
                }
            }
            .contentShape(Rectangle())
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
            .onTapGesture(count: 1, coordinateSpace: .local) { location in
                guard let layout, let onTapWall, let wall = nearestWall(to: location, layout: layout) else { return }
                onTapWall(wall)
            }
        }
    }

    /// The wall within 30 points of a tap, if any.
    private func nearestWall(to location: CGPoint, layout: Layout) -> WallRef? {
        let p = layout.plan(location)
        let tolerance = 30 / layout.scale
        return walls
            .map { ($0.0, $0.1.distance(to: p)) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?.0
    }

    private func draw(_ item: DrawingItem, in context: GraphicsContext, layout: Layout) {
        let color = Self.color(for: item.layer)
        switch item.primitive {
        case let .line(a, b):
            var path = Path()
            path.move(to: layout.screen(a))
            path.addLine(to: layout.screen(b))
            context.stroke(path, with: .color(color), lineWidth: item.layer == .wall ? 1.5 : 1)
        case let .arc(center, radius, start, end):
            let sweep = end >= start ? end - start : end - start + 2 * .pi
            var path = Path()
            for step in 0...24 {
                let a = start + sweep * Double(step) / 24
                let p = layout.screen(center + Point2(cos(a), sin(a)) * radius)
                if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            context.stroke(path, with: .color(color), lineWidth: 1)
        case let .text(at, height, string, rotation):
            var c = context
            let p = layout.screen(at)
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .radians(-rotation))
            c.draw(Text(string).font(.system(size: max(height * layout.scale, 6))).foregroundColor(color), at: .zero)
        }
    }

    /// Maps plan metres to screen points. Plan y points up; screen y points down.
    private struct Layout {
        var mid: Point2
        var scale: Double
        var origin: CGPoint

        init(extents: (Point2, Point2), size: CGSize, zoom: CGFloat, pan: CGSize) {
            let (lo, hi) = extents
            let w = max(hi.x - lo.x, 0.1), h = max(hi.y - lo.y, 0.1)
            scale = min(size.width / w, size.height / h) * 0.9 * zoom
            mid = (lo + hi) / 2
            origin = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
        }

        func screen(_ p: Point2) -> CGPoint {
            CGPoint(x: origin.x + (p.x - mid.x) * scale, y: origin.y - (p.y - mid.y) * scale)
        }

        func plan(_ p: CGPoint) -> Point2 {
            Point2(mid.x + (p.x - origin.x) / scale, mid.y - (p.y - origin.y) / scale)
        }
    }

    private static func color(for layer: Layer) -> Color {
        switch layer {
        case .wall: return .primary
        case .door: return .green
        case .glazing: return .cyan
        case .furniture: return .gray
        case .dimensions: return .red
        case .annotation: return .blue
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
