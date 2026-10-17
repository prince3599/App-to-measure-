import Foundation
import PlanCore

/// Keeps each house project as a JSON file in the app's Documents/Projects folder.
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [HouseProject] = []

    private let folder: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    init() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        projects = files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(HouseProject.self, from: Data(contentsOf: $0)) }
            .sorted { $0.created > $1.created }
    }

    func project(_ id: UUID) -> HouseProject? {
        projects.first { $0.id == id }
    }

    func add(_ project: HouseProject) {
        save(project)
        projects.insert(project, at: 0)
    }

    func modify(_ id: UUID, _ change: (inout HouseProject) -> Void) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        var project = projects[i]
        change(&project)
        guard project != projects[i] else { return }
        projects[i] = project
        save(project)
    }

    func delete(_ project: HouseProject) {
        try? FileManager.default.removeItem(at: file(for: project.id))
        projects.removeAll { $0.id == project.id }
    }

    private func save(_ project: HouseProject) {
        if let data = try? JSONEncoder().encode(project) {
            try? data.write(to: file(for: project.id), options: .atomic)
        }
    }

    private func file(for id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).json")
    }
}

/// Navigation value for a floor inside a project.
struct FloorRoute: Hashable {
    var project: UUID
    var floor: UUID
}
