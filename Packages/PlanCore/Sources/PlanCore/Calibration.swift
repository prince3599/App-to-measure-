import Foundation

extension FloorPlan {
    /// The whole plan scaled about its centroid so that wall `index` measures `length` metres.
    /// Scan errors are mostly a uniform scale error, so one known length corrects every wall.
    public func calibrated(wall index: Int, to length: Double) -> FloorPlan {
        guard walls.indices.contains(index), length > 0 else { return self }
        let current = walls[index].line.length
        guard current > 0 else { return self }
        return scaled(by: length / current)
    }

    /// Scales positions and sizes about `center` (the plan's centroid by default). Wall thickness is left unchanged.
    public func scaled(by factor: Double, about center: Point2? = nil) -> FloorPlan {
        let c = center ?? centroid
        func s(_ p: Point2) -> Point2 { c + (p - c) * factor }
        var plan = self
        for i in plan.walls.indices {
            plan.walls[i].line = Segment2(s(walls[i].line.start), s(walls[i].line.end))
        }
        for i in plan.openings.indices {
            plan.openings[i].offset *= factor
            plan.openings[i].width *= factor
            plan.openings[i].height *= factor
        }
        plan.ceilingHeight *= factor
        for i in plan.objects.indices {
            plan.objects[i].center = s(objects[i].center)
            plan.objects[i].width *= factor
            plan.objects[i].depth *= factor
        }
        return plan
    }
}

extension LengthUnit {
    /// Parses a typed length into metres.
    /// Millimetres: "3650". Inches: "120", "10'", "10'6", "10' 6\"", "10'-6.5\"".
    public func parse(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "”", with: "\"")
        switch self {
        case .millimetres:
            guard let mm = Double(t), mm > 0 else { return nil }
            return mm / 1000
        case .inches:
            var inches = 0.0
            var rest = Substring(t)
            if let foot = rest.firstIndex(of: "'") {
                guard let feet = Double(rest[..<foot].trimmingCharacters(in: .whitespaces)) else { return nil }
                inches = feet * 12
                rest = rest[rest.index(after: foot)...]
            }
            let inchText = rest.trimmingCharacters(in: CharacterSet(charactersIn: " -\""))
            if !inchText.isEmpty {
                guard let value = Double(inchText) else { return nil }
                inches += value
            }
            return inches > 0 ? inches * 0.0254 : nil
        }
    }
}
