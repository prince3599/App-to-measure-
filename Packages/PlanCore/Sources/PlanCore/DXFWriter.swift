import Foundation

/// Writes an ASCII DXF (AutoCAD R12 / AC1009), the most widely readable DXF flavour.
/// Coordinates are written at 1:1 in the chosen unit (millimetres by default).
public struct DXFWriter: Sendable {
    public var unit: LengthUnit

    public init(unit: LengthUnit = .millimetres) {
        self.unit = unit
    }

    public func write(_ plan: FloorPlan) -> String {
        write(PlanDrawing(unit: unit).items(for: plan))
    }

    public func write(_ items: [DrawingItem]) -> String {
        var out = DXFStream()
        let s = unit.scale
        let (lo, hi) = extents(of: items)

        out.pair(0, "SECTION"); out.pair(2, "HEADER")
        out.pair(9, "$ACADVER"); out.pair(1, "AC1009")
        out.pair(9, "$EXTMIN"); out.point(lo * s)
        out.pair(9, "$EXTMAX"); out.point(hi * s)
        out.pair(0, "ENDSEC")

        out.pair(0, "SECTION"); out.pair(2, "TABLES")
        out.pair(0, "TABLE"); out.pair(2, "LTYPE"); out.pair(70, 1)
        out.pair(0, "LTYPE"); out.pair(2, "CONTINUOUS"); out.pair(70, 0)
        out.pair(3, "Solid line"); out.pair(72, 65); out.pair(73, 0); out.pair(40, 0.0)
        out.pair(0, "ENDTAB")
        out.pair(0, "TABLE"); out.pair(2, "LAYER"); out.pair(70, Layer.allCases.count)
        for layer in Layer.allCases {
            out.pair(0, "LAYER"); out.pair(2, layer.rawValue); out.pair(70, 0)
            out.pair(62, layer.aciColor); out.pair(6, "CONTINUOUS")
        }
        out.pair(0, "ENDTAB")
        out.pair(0, "ENDSEC")

        out.pair(0, "SECTION"); out.pair(2, "ENTITIES")
        for item in items {
            switch item.primitive {
            case let .line(a, b):
                out.pair(0, "LINE"); out.pair(8, item.layer.rawValue)
                out.point(a * s)
                out.point(b * s, base: 11)
            case let .arc(center, radius, start, end):
                out.pair(0, "ARC"); out.pair(8, item.layer.rawValue)
                out.point(center * s)
                out.pair(40, radius * s)
                out.pair(50, degrees(start)); out.pair(51, degrees(end))
            case let .text(at, height, string, rotation):
                out.pair(0, "TEXT"); out.pair(8, item.layer.rawValue)
                out.point(at * s)
                out.pair(40, height * s)
                out.pair(1, sanitize(string))
                out.pair(50, degrees(rotation))
                out.pair(72, 1) // centre
                out.point(at * s, base: 11)
                out.pair(73, 2) // middle
            }
        }
        out.pair(0, "ENDSEC")
        out.pair(0, "EOF")
        return out.text
    }

    private func extents(of items: [DrawingItem]) -> (Point2, Point2) {
        var pts: [Point2] = []
        for item in items {
            switch item.primitive {
            case let .line(a, b): pts += [a, b]
            case let .arc(c, r, _, _): pts += [c - Point2(r, r), c + Point2(r, r)]
            case let .text(at, _, _, _): pts.append(at)
            }
        }
        guard let first = pts.first else { return (.zero, .zero) }
        return pts.reduce((first, first)) { acc, p in
            (Point2(min(acc.0.x, p.x), min(acc.0.y, p.y)), Point2(max(acc.1.x, p.x), max(acc.1.y, p.y)))
        }
    }

    private func degrees(_ radians: Double) -> Double {
        var d = radians * 180 / .pi
        while d < 0 { d += 360 }
        while d >= 360 { d -= 360 }
        return d
    }

    /// R12 text is a single line of ASCII; anything else is written as \U+XXXX.
    private func sanitize(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            if scalar == "\n" || scalar == "\r" {
                out += " "
            } else if scalar.isASCII {
                out.unicodeScalars.append(scalar)
            } else {
                out += String(format: "\\U+%04X", scalar.value)
            }
        }
        return out
    }
}

private struct DXFStream {
    var text = ""

    mutating func pair(_ code: Int, _ value: String) {
        let c = String(code)
        text += String(repeating: " ", count: max(0, 3 - c.count)) + c + "\n" + value + "\n"
    }

    mutating func pair(_ code: Int, _ value: Int) { pair(code, String(value)) }

    mutating func pair(_ code: Int, _ value: Double) { pair(code, String(format: "%.4f", value)) }

    mutating func point(_ p: Point2, base: Int = 10) {
        pair(base, p.x); pair(base + 10, p.y); pair(base + 20, 0.0)
    }
}
