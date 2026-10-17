import PlanCore
import RoomPlan
import SwiftUI

struct FloorView: View {
    var route: FloorRoute

    @EnvironmentObject private var store: ProjectStore
    @State private var isScanning = false
    @State private var confirmRescan = false
    @State private var showUnsupported = false
    @State private var selectedWall: WallRef?
    @State private var isEditingLength = false
    @State private var lengthText = ""
    @State private var showInvalidLength = false
    @State private var renamingRoom: UUID?
    @State private var roomName = ""
    @State private var files: ExportFiles.Files?

    private var project: HouseProject? { store.project(route.project) }
    private var floorIndex: Int? { project?.floors.firstIndex { $0.id == route.floor } }

    var body: some View {
        if let project, let floorIndex {
            let floor = project.floors[floorIndex]
            content(project: project, floor: floor)
                .navigationTitle(floor.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        if let files {
                            Menu {
                                ShareLink(item: files.pdf) { Label("Permit PDF", systemImage: "doc.richtext") }
                                ForEach(files.dxf, id: \.self) { url in
                                    ShareLink(item: url) { Label("AutoCAD DXF", systemImage: "square.and.arrow.up") }
                                }
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                        }
                        Button {
                            if !RoomCaptureSession.isSupported {
                                showUnsupported = true
                            } else if floor.rooms.isEmpty {
                                isScanning = true
                            } else {
                                confirmRescan = true
                            }
                        } label: {
                            Label("Scan Rooms", systemImage: "camera.viewfinder")
                        }
                    }
                }
                .task(id: project) { files = ExportFiles.floorFiles(project, floorIndex: floorIndex) }
                .fullScreenCover(isPresented: $isScanning) {
                    FloorScanView(floorName: floor.name) { captured in
                        let scanned = RoomPlanConverter.room(from: captured)
                        store.modify(route.project) { p in
                            guard let i = p.floors.firstIndex(where: { $0.id == route.floor }) else { return }
                            p.floors[i].rooms.append(Room(name: p.floors[i].uniqueRoomName(scanned.name), plan: scanned.plan))
                        }
                    }
                }
                .confirmationDialog("This floor already has rooms", isPresented: $confirmRescan, titleVisibility: .visible) {
                    Button("Rescan Whole Floor", role: .destructive) {
                        modifyFloor { $0.rooms.removeAll() }
                        isScanning = true
                    }
                    Button("Add Rooms Anyway") { isScanning = true }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Rooms scanned in a new session won't line up with the ones already on this floor. For a clean plan, rescan the whole floor in one go.")
                }
                .alert("Room scanning needs LiDAR", isPresented: $showUnsupported) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Use an iPhone Pro or iPad Pro with a LiDAR scanner. You can try the app with Add Sample House on the home screen.")
                }
                .alert("Real wall length", isPresented: $isEditingLength) {
                    TextField(project.unit == .millimetres ? "e.g. 3650" : "e.g. 12'6\"", text: $lengthText)
                        .keyboardType(project.unit == .millimetres ? .numberPad : .numbersAndPunctuation)
                    Button("Apply") { applyLength(unit: project.unit) }
                    Button("Cancel", role: .cancel) { selectedWall = nil }
                } message: {
                    Text("Every room on this floor rescales to match.")
                }
                .alert("That length isn't valid", isPresented: $showInvalidLength) {
                    Button("OK") { selectedWall = nil }
                }
                .alert("Room name", isPresented: Binding(get: { renamingRoom != nil }, set: { if !$0 { renamingRoom = nil } })) {
                    TextField("Name", text: $roomName)
                    Button("Save") {
                        let id = renamingRoom
                        modifyFloor { f in
                            if let i = f.rooms.firstIndex(where: { $0.id == id }), !roomName.isEmpty { f.rooms[i].name = roomName }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
        } else {
            ContentUnavailableView("Floor not found", systemImage: "square.stack.3d.up")
        }
    }

    @ViewBuilder
    private func content(project: HouseProject, floor: Floor) -> some View {
        if floor.rooms.isEmpty {
            ContentUnavailableView {
                Label("No rooms yet", systemImage: "camera.viewfinder")
            } description: {
                Text("Tap Scan Rooms and scan every room on this floor in one go. After each room, tap Room Done, walk into the next room and keep going.")
            }
        } else {
            VStack(spacing: 0) {
                PlanPreviewView(
                    items: project.drawing(for: floor).items(for: floor),
                    walls: wallLines(floor),
                    selectedWall: selectedWall
                ) { ref in
                    selectedWall = ref
                    lengthText = project.unit.format(floor.rooms[ref.room].plan.walls[ref.wall].line.length)
                    isEditingLength = true
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                Text("Tap a wall to type its real length. Pinch to zoom.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.vertical, 6)
                List {
                    Section("\(floor.rooms.count) rooms · \(project.unit.formatArea(floor.netArea))") {
                        ForEach(floor.rooms) { room in
                            Button {
                                roomName = room.name
                                renamingRoom = room.id
                            } label: {
                                HStack {
                                    Text(room.name).foregroundStyle(.primary)
                                    Spacer()
                                    Text(project.unit.formatArea(room.plan.area)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in modifyFloor { $0.rooms.remove(atOffsets: offsets) } }
                    }
                }
                .listStyle(.insetGrouped)
                .frame(height: 220)
            }
        }
    }

    private func wallLines(_ floor: Floor) -> [(WallRef, Segment2)] {
        var lines: [(WallRef, Segment2)] = []
        for (r, room) in floor.rooms.enumerated() {
            for (w, wall) in room.plan.walls.enumerated() {
                lines.append((WallRef(room: r, wall: w), wall.line))
            }
        }
        return lines
    }

    private func modifyFloor(_ change: @escaping (inout Floor) -> Void) {
        store.modify(route.project) { p in
            if let i = p.floors.firstIndex(where: { $0.id == route.floor }) { change(&p.floors[i]) }
        }
    }

    private func applyLength(unit: LengthUnit) {
        guard let ref = selectedWall else { return }
        guard let metres = unit.parse(lengthText) else {
            showInvalidLength = true
            return
        }
        modifyFloor { $0 = $0.calibrated(room: ref.room, wall: ref.wall, to: metres) }
        selectedWall = nil
    }
}
