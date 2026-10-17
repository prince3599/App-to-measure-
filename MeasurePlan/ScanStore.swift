import Foundation
import PlanCore

struct SavedScan: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var date = Date()
    var plan: FloorPlan

    static func == (a: SavedScan, b: SavedScan) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Keeps each scan as a JSON file in the app's Documents/Scans folder.
@MainActor
final class ScanStore: ObservableObject {
    @Published private(set) var scans: [SavedScan] = []

    private let folder: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    init() {
        load()
    }

    func add(_ plan: FloorPlan, name: String? = nil) -> SavedScan {
        let scan = SavedScan(name: name ?? "Room \(scans.count + 1)", plan: plan)
        save(scan)
        scans.insert(scan, at: 0)
        return scan
    }

    func delete(_ scan: SavedScan) {
        try? FileManager.default.removeItem(at: file(for: scan))
        scans.removeAll { $0.id == scan.id }
    }

    private func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        scans = files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(SavedScan.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    private func save(_ scan: SavedScan) {
        if let data = try? JSONEncoder().encode(scan) {
            try? data.write(to: file(for: scan), options: .atomic)
        }
    }

    private func file(for scan: SavedScan) -> URL {
        folder.appendingPathComponent("\(scan.id.uuidString).json")
    }
}
