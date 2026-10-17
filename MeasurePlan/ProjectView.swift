import PlanCore
import SwiftUI

struct ProjectView: View {
    var projectID: UUID

    @EnvironmentObject private var store: ProjectStore
    @State private var exports: ExportFiles.Files?
    @State private var showCustomFloor = false
    @State private var customFloorName = ""

    var body: some View {
        if let project = store.project(projectID) {
            Form {
                Section("Property") {
                    TextField("Project name", text: bind(\.name, ""))
                    TextField("Address", text: bind(\.address, ""))
                    TextField("Owner", text: bind(\.owner, ""))
                    TextField("Prepared by", text: bind(\.preparedBy, ""))
                    Picker("Units", selection: bind(\.unit, .inches)) {
                        Text("ft-in").tag(LengthUnit.inches)
                        Text("mm").tag(LengthUnit.millimetres)
                    }
                    Toggle("Show furniture", isOn: bind(\.showFurniture, false))
                }

                Section {
                    ForEach(project.floors) { floor in
                        NavigationLink(value: FloorRoute(project: projectID, floor: floor.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(floor.name)
                                Text(floor.rooms.isEmpty
                                     ? "Not scanned yet"
                                     : "\(floor.rooms.count) rooms · \(project.unit.formatArea(floor.netArea))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in store.modify(projectID) { $0.floors.remove(atOffsets: offsets) } }
                    .onMove { from, to in store.modify(projectID) { $0.floors.move(fromOffsets: from, toOffset: to) } }

                    Menu {
                        ForEach(HouseProject.suggestedFloorNames.filter { name in !project.floors.contains { $0.name == name } }, id: \.self) { name in
                            Button(name) { addFloor(name) }
                        }
                        Button("Other…") { customFloorName = ""; showCustomFloor = true }
                    } label: {
                        Label("Add Floor", systemImage: "plus")
                    }
                } header: {
                    Text("Floors")
                } footer: {
                    Text("Scan each floor in one go, walking from room to room, so the rooms line up.")
                }

                Section {
                    if let exports {
                        ShareLink(item: exports.pdf) {
                            Label("Permit PDF (all floors)", systemImage: "doc.richtext")
                        }
                        if !exports.dxf.isEmpty {
                            ShareLink(items: exports.dxf) {
                                Label("AutoCAD DXF (one file per floor)", systemImage: "square.and.arrow.up")
                            }
                        }
                    } else {
                        Text("Scan a floor to create drawings.").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Permit drawings")
                } footer: {
                    Text("Sheets are 11 x 17 in at a standard scale, one per floor. Check key dimensions with a tape or laser before submitting. Some places require drawings stamped by a licensed designer.")
                }
            }
            .navigationTitle(project.name)
            .toolbar { EditButton() }
            .task(id: project) { exports = ExportFiles.write(project) }
            .alert("Floor name", isPresented: $showCustomFloor) {
                TextField("e.g. Garage", text: $customFloorName)
                Button("Add") { if !customFloorName.isEmpty { addFloor(customFloorName) } }
                Button("Cancel", role: .cancel) {}
            }
        } else {
            ContentUnavailableView("House not found", systemImage: "house")
        }
    }

    private func addFloor(_ name: String) {
        store.modify(projectID) { $0.floors.append(Floor(name: name)) }
    }

    private func bind<T>(_ keyPath: WritableKeyPath<HouseProject, T>, _ fallback: T) -> Binding<T> {
        Binding(
            get: { store.project(projectID)?[keyPath: keyPath] ?? fallback },
            set: { value in store.modify(projectID) { $0[keyPath: keyPath] = value } }
        )
    }
}

/// Writes PDF and DXF files to a temporary folder for the share sheet.
enum ExportFiles {
    struct Files: Equatable {
        var pdf: URL
        var dxf: [URL]
    }

    static func write(_ project: HouseProject) -> Files? {
        let scanned = project.floors.enumerated().filter { !$0.element.rooms.isEmpty }
        guard !scanned.isEmpty, let dir = folder(for: project) else { return nil }
        let base = safeName(project.name)
        let pdf = dir.appendingPathComponent("\(base) permit plans.pdf")
        guard (try? PermitPDF.write(project: project, floors: scanned.map { ($0.offset, $0.element) }, to: pdf)) != nil else { return nil }
        let dxf = scanned.compactMap { index, floor in
            write(floor: floor, index: index, of: project, in: dir)
        }
        return Files(pdf: pdf, dxf: dxf)
    }

    static func floorFiles(_ project: HouseProject, floorIndex: Int) -> Files? {
        guard project.floors.indices.contains(floorIndex), let dir = folder(for: project) else { return nil }
        let floor = project.floors[floorIndex]
        guard !floor.rooms.isEmpty else { return nil }
        let pdf = dir.appendingPathComponent("\(safeName(project.name)) \(safeName(floor.name)).pdf")
        guard (try? PermitPDF.write(project: project, floors: [(floorIndex, floor)], to: pdf)) != nil,
              let dxf = write(floor: floor, index: floorIndex, of: project, in: dir)
        else { return nil }
        return Files(pdf: pdf, dxf: [dxf])
    }

    private static func write(floor: Floor, index: Int, of project: HouseProject, in dir: URL) -> URL? {
        let url = dir.appendingPathComponent("\(safeName(project.name)) \(safeName(floor.name)).dxf")
        let text = DXFWriter(unit: project.unit).write(floor: floor, of: project, sheet: index + 1, of: project.floors.count)
        return (try? text.write(to: url, atomically: true, encoding: .ascii)) != nil ? url : nil
    }

    private static func folder(for project: HouseProject) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(project.id.uuidString, isDirectory: true)
        return (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)) != nil ? url : nil
    }

    private static func safeName(_ s: String) -> String {
        let cleaned = s.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        return cleaned.isEmpty ? "House" : cleaned
    }
}
