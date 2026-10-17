import PlanCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var path = NavigationPath()
    @State private var showNewProject = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(store.projects) { project in
                    NavigationLink(value: project.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name).font(.headline)
                            if !project.address.isEmpty {
                                Text(project.address).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text("\(project.floors.count) floors · \(project.floors.map(\.rooms.count).reduce(0, +)) rooms")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { store.projects[$0] }.forEach(store.delete)
                }
            }
            .overlay {
                if store.projects.isEmpty {
                    ContentUnavailableView("No houses yet",
                                           systemImage: "house",
                                           description: Text("Tap + to start a house. Each floor gets its own permit sheet."))
                }
            }
            .navigationTitle("MeasurePlan")
            .navigationDestination(for: UUID.self) { ProjectView(projectID: $0) }
            .navigationDestination(for: FloorRoute.self) { FloorView(route: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNewProject = true } label: { Label("New House", systemImage: "plus") }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Add Sample House") {
                        var sample = SampleData.house
                        sample.id = UUID()
                        store.add(sample)
                        path.append(sample.id)
                    }
                }
            }
            .sheet(isPresented: $showNewProject) {
                NewProjectSheet { project in
                    store.add(project)
                    path.append(project.id)
                }
            }
        }
    }
}

struct NewProjectSheet: View {
    var onCreate: (HouseProject) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var project = HouseProject(name: "", floors: [Floor(name: "First Floor")])

    var body: some View {
        NavigationStack {
            Form {
                Section("Property") {
                    TextField("Project name", text: $project.name)
                    TextField("Address", text: $project.address)
                    TextField("Owner", text: $project.owner)
                    TextField("Prepared by", text: $project.preparedBy)
                }
                Section("Units") {
                    Picker("Units", selection: $project.unit) {
                        Text("Feet and inches").tag(LengthUnit.inches)
                        Text("Millimetres").tag(LengthUnit.millimetres)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("New House")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if project.name.isEmpty { project.name = project.address.isEmpty ? "New House" : project.address }
                        onCreate(project)
                        dismiss()
                    }
                }
            }
        }
    }
}
