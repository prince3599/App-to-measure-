import PlanCore
import RoomPlan
import SwiftUI

struct FloorView: View {
    var route: FloorRoute

    private enum Mode: String, CaseIterable {
        case edit = "Edit"
        case move = "Move Rooms"
    }

    @EnvironmentObject private var store: ProjectStore
    @State private var mode = Mode.edit
    @State private var selection: FloorHit?
    @State private var tapPoint = Point2.zero
    @State private var dragDelta: Point2?

    @State private var isScanning = false
    @State private var confirmRescan = false
    @State private var showUnsupported = false
    @State private var sessionStartBounds: (min: Point2, max: Point2)?
    @State private var sessionShift: Point2?

    @State private var showWallActions = false
    @State private var showOpeningActions = false
    @State private var lengthEdit: LengthEdit?
    @State private var lengthText = ""
    @State private var editingWidth = false
    @State private var widthText = ""
    @State private var message: String?
    @State private var renamingRoom: UUID?
    @State private var roomName = ""
    @State private var files: ExportFiles.Files?

    private enum LengthEdit {
        case wall(WallRef)
        case scaleFloor(WallRef)
    }

    private var project: HouseProject? { store.project(route.project) }
    private var floorIndex: Int? { project?.floors.firstIndex { $0.id == route.floor } }

    var body: some View {
        if let project, let floorIndex {
            let floor = project.floors[floorIndex]
            content(project: project, floor: floor)
                .navigationTitle(floor.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar(floor: floor) }
                .task(id: project) { files = ExportFiles.floorFiles(project, floorIndex: floorIndex) }
                .fullScreenCover(isPresented: $isScanning) {
                    FloorScanView(floorName: floor.name) { captured in addScannedRoom(captured) }
                }
                .confirmationDialog("This floor already has rooms", isPresented: $confirmRescan, titleVisibility: .visible) {
                    Button("Add Rooms") {
                        sessionStartBounds = floor.bounds
                        sessionShift = nil
                        isScanning = true
                    }
                    Button("Rescan Whole Floor", role: .destructive) {
                        modifyFloor { $0.rooms.removeAll() }
                        sessionStartBounds = nil
                        isScanning = true
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("New rooms appear beside the plan. Use Move Rooms to drag each one into place, then tap Snap.")
                }
                .confirmationDialog("Wall", isPresented: $showWallActions, titleVisibility: .hidden) {
                    wallActions(floor: floor, unit: project.unit)
                }
                .confirmationDialog(openingTitle(floor), isPresented: $showOpeningActions, titleVisibility: .visible) {
                    openingActions(floor: floor, unit: project.unit)
                }
                .alert(lengthTitle, isPresented: Binding(get: { lengthEdit != nil }, set: { if !$0 { lengthEdit = nil } })) {
                    TextField(project.unit == .millimetres ? "e.g. 3650" : "e.g. 12'6\"", text: $lengthText)
                        .keyboardType(project.unit == .millimetres ? .numberPad : .numbersAndPunctuation)
                    Button("Apply") { applyLength(unit: project.unit) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    if case .scaleFloor = lengthEdit {
                        Text("Every room on this floor rescales to match.")
                    } else {
                        Text("The wall's far end moves. The walls joined to it follow, so the room keeps its shape.")
                    }
                }
                .alert("Opening width", isPresented: $editingWidth) {
                    TextField(project.unit == .millimetres ? "e.g. 900" : "e.g. 3'0\"", text: $widthText)
                        .keyboardType(project.unit == .millimetres ? .numberPad : .numbersAndPunctuation)
                    Button("Apply") { applyWidth(unit: project.unit) }
                    Button("Cancel", role: .cancel) {}
                }
                .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button("OK", role: .cancel) {}
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
                .onChange(of: mode) { _, _ in selection = nil }
        } else {
            ContentUnavailableView("Floor not found", systemImage: "square.stack.3d.up")
        }
    }

    // MARK: - Layout

    @ToolbarContentBuilder
    private func toolbar(floor: Floor) -> some ToolbarContent {
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
                    sessionStartBounds = nil
                    isScanning = true
                } else {
                    confirmRescan = true
                }
            } label: {
                Label("Scan Rooms", systemImage: "camera.viewfinder")
            }
            .alert("Room scanning needs LiDAR", isPresented: $showUnsupported) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Use an iPhone Pro or iPad Pro with a LiDAR scanner. You can try the app with Add Sample House on the home screen.")
            }
        }
    }

    @ViewBuilder
    private func content(project: HouseProject, floor: Floor) -> some View {
        if floor.rooms.isEmpty {
            ContentUnavailableView {
                Label("No rooms yet", systemImage: "camera.viewfinder")
            } description: {
                Text("Tap Scan Rooms. Scan the whole floor in one go if you can: after each room, tap Room Done and walk into the next one. You can also scan rooms one at a time and move them into place afterwards.")
            }
        } else {
            let shown = displayedFloor(floor)
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 6)

                PlanPreviewView(
                    items: project.drawing(for: shown).items(for: shown),
                    highlights: highlights(shown),
                    onTap: { p, tolerance in handleTap(p, tolerance: tolerance, floor: floor) },
                    onDrag: mode == .move && selectedRoom != nil ? { delta, ended in handleDrag(delta, ended: ended) } : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))

                if mode == .move {
                    moveBar(floor: floor)
                } else {
                    Text("Tap a wall, door or window to edit it. Tap inside a room to rename it.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.vertical, 6)
                    roomList(project: project, floor: floor)
                }
            }
        }
    }

    private func moveBar(floor: Floor) -> some View {
        VStack(spacing: 10) {
            if let r = selectedRoom, floor.rooms.indices.contains(r) {
                Text("Drag \(floor.rooms[r].name) into place, then tap Snap to line it up with the room next to it.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button { rotate(r, degrees: 90) } label: { Image(systemName: "rotate.left") }
                    Button { rotate(r, degrees: -90) } label: { Image(systemName: "rotate.right") }
                    Button("−1°") { rotate(r, degrees: 1) }
                    Button("+1°") { rotate(r, degrees: -1) }
                    Button("Snap") {
                        if let snapped = floor.snappingRoom(r) {
                            modifyFloor { $0 = snapped }
                        } else {
                            message = "No wall of another room is close enough. Drag the room within about 3 ft of its neighbour first."
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .buttonStyle(.bordered)
            } else {
                Text("Tap a room to select it.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func roomList(project: HouseProject, floor: Floor) -> some View {
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
        .frame(height: 200)
    }

    // MARK: - Selection

    private var selectedRoom: Int? {
        if case let .room(r) = selection { return r }
        return nil
    }

    private func displayedFloor(_ floor: Floor) -> Floor {
        if let dragDelta, let r = selectedRoom { return floor.movingRoom(r, by: dragDelta) }
        return floor
    }

    private func highlights(_ floor: Floor) -> [Segment2] {
        switch selection {
        case let .wall(ref)?:
            guard floor.rooms.indices.contains(ref.room), floor.rooms[ref.room].plan.walls.indices.contains(ref.wall) else { return [] }
            return [floor.rooms[ref.room].plan.walls[ref.wall].line]
        case let .opening(r, i)?:
            guard let o = opening(floor, r, i) else { return [] }
            let line = floor.rooms[r].plan.walls[o.wallIndex].line
            return [Segment2(line.point(atDistance: o.offset - o.width / 2), line.point(atDistance: o.offset + o.width / 2))]
        case let .room(r)?:
            guard floor.rooms.indices.contains(r) else { return [] }
            return floor.rooms[r].plan.walls.map(\.line)
        case nil:
            return []
        }
    }

    private func handleTap(_ p: Point2, tolerance: Double, floor: Floor) {
        tapPoint = p
        let hit = floor.hit(at: p, tolerance: tolerance)
        switch mode {
        case .move:
            switch hit {
            case let .room(r)?: selection = .room(r)
            case let .wall(ref)?: selection = .room(ref.room)
            case let .opening(r, _)?: selection = .room(r)
            case nil: selection = nil
            }
        case .edit:
            selection = hit
            switch hit {
            case .wall?: showWallActions = true
            case .opening?: showOpeningActions = true
            case let .room(r)?:
                roomName = floor.rooms[r].name
                renamingRoom = floor.rooms[r].id
            case nil: break
            }
        }
    }

    private func handleDrag(_ delta: Point2, ended: Bool) {
        guard let r = selectedRoom else { return }
        if ended {
            dragDelta = nil
            modifyFloor { $0 = $0.movingRoom(r, by: delta) }
        } else {
            dragDelta = delta
        }
    }

    private func rotate(_ room: Int, degrees: Double) {
        modifyFloor { $0 = $0.rotatingRoom(room, by: degrees * .pi / 180) }
    }

    // MARK: - Walls

    @ViewBuilder
    private func wallActions(floor: Floor, unit: LengthUnit) -> some View {
        if case let .wall(ref)? = selection, floor.rooms.indices.contains(ref.room),
           floor.rooms[ref.room].plan.walls.indices.contains(ref.wall) {
            let length = floor.rooms[ref.room].plan.walls[ref.wall].line.length
            Button("Set This Wall's Length (\(unit.format(length)))…") {
                lengthText = unit.format(length)
                lengthEdit = .wall(ref)
            }
            Button("Scale Whole Floor From This Wall…") {
                lengthText = unit.format(length)
                lengthEdit = .scaleFloor(ref)
            }
            Button("Add Door Here") { addOpening(.door, on: ref, floor: floor) }
            Button("Add Window Here") { addOpening(.window, on: ref, floor: floor) }
            Button("Cancel", role: .cancel) { selection = nil }
        }
    }

    private var lengthTitle: String {
        if case .scaleFloor = lengthEdit { return "Real length of this wall" }
        return "New wall length"
    }

    private func applyLength(unit: LengthUnit) {
        guard let edit = lengthEdit else { return }
        guard let metres = unit.parse(lengthText) else {
            message = "That length isn't valid."
            return
        }
        switch edit {
        case let .wall(ref):
            modifyFloor { f in
                guard f.rooms.indices.contains(ref.room) else { return }
                f.rooms[ref.room].plan = f.rooms[ref.room].plan.settingLength(ofWall: ref.wall, to: metres)
            }
        case let .scaleFloor(ref):
            modifyFloor { $0 = $0.calibrated(room: ref.room, wall: ref.wall, to: metres) }
        }
        selection = nil
    }

    private func addOpening(_ kind: OpeningKind, on ref: WallRef, floor: Floor) {
        let line = floor.rooms[ref.room].plan.walls[ref.wall].line
        let width = min(kind == .door ? 0.9 : 1.2, line.length)
        let offset = min(max(line.distanceAlong(tapPoint), width / 2), line.length - width / 2)
        modifyFloor { f in
            f.rooms[ref.room].plan.openings.append(Opening(kind: kind, wallIndex: ref.wall, offset: offset, width: width,
                                                           height: kind == .door ? 2.03 : 1.2))
        }
        selection = nil
    }

    // MARK: - Doors and windows

    private func opening(_ floor: Floor, _ r: Int, _ i: Int) -> Opening? {
        guard floor.rooms.indices.contains(r), floor.rooms[r].plan.openings.indices.contains(i) else { return nil }
        let o = floor.rooms[r].plan.openings[i]
        return floor.rooms[r].plan.walls.indices.contains(o.wallIndex) ? o : nil
    }

    private func openingTitle(_ floor: Floor) -> String {
        guard case let .opening(r, i)? = selection, let o = opening(floor, r, i) else { return "Opening" }
        switch o.kind {
        case .door: return o.leaves > 1 ? "Door (\(o.leaves) leaves)" : "Door"
        case .window: return "Window"
        case .opening: return "Opening"
        }
    }

    @ViewBuilder
    private func openingActions(floor: Floor, unit: LengthUnit) -> some View {
        if case let .opening(r, i)? = selection, let o = opening(floor, r, i) {
            if o.kind == .door {
                Button("Flip Hinge Side") { modifyOpening(r, i) { $0.hingeAtEnd.toggle() } }
                Button(o.swingsOut ? "Swing Into Room" : "Swing Out of Room") { modifyOpening(r, i) { $0.swingsOut.toggle() } }
                ForEach([1, 2, 3, 4].filter { $0 != o.leaves }, id: \.self) { n in
                    Button(n == 1 ? "Single Door" : n == 2 ? "Double Door (2 leaves)" : "\(n) Leaves") {
                        modifyOpening(r, i) { $0.leaves = n }
                    }
                }
                Button("Change to Window") { modifyOpening(r, i) { $0.kind = .window; $0.leaves = 1 } }
            } else {
                Button("Change to Door") { modifyOpening(r, i) { $0.kind = .door } }
            }
            Button("Change Width (\(unit.format(o.width)))…") {
                widthText = unit.format(o.width)
                editingWidth = true
            }
            Button("Delete", role: .destructive) {
                modifyFloor { f in f.rooms[r].plan.openings.remove(at: i) }
                selection = nil
            }
            Button("Cancel", role: .cancel) { selection = nil }
        }
    }

    private func applyWidth(unit: LengthUnit) {
        guard case let .opening(r, i)? = selection else { return }
        guard let metres = unit.parse(widthText) else {
            message = "That width isn't valid."
            return
        }
        modifyOpening(r, i) { $0.width = metres }
        selection = nil
    }

    private func modifyOpening(_ r: Int, _ i: Int, _ change: @escaping (inout Opening) -> Void) {
        modifyFloor { f in
            guard f.rooms.indices.contains(r), f.rooms[r].plan.openings.indices.contains(i) else { return }
            change(&f.rooms[r].plan.openings[i])
            let wall = f.rooms[r].plan.walls[f.rooms[r].plan.openings[i].wallIndex].line
            let half = min(f.rooms[r].plan.openings[i].width, wall.length) / 2
            f.rooms[r].plan.openings[i].width = half * 2
            f.rooms[r].plan.openings[i].offset = min(max(f.rooms[r].plan.openings[i].offset, half), wall.length - half)
        }
    }

    // MARK: - Scanning and storage

    private func addScannedRoom(_ captured: CapturedRoom) {
        var room = RoomPlanConverter.room(from: captured)
        // Rooms from a new scan session have their own coordinates: park them beside the existing plan.
        if let existing = sessionStartBounds {
            if sessionShift == nil, let b = Floor(name: "", rooms: [room]).bounds {
                sessionShift = Point2(existing.max.x + 1.5 - b.min.x, existing.min.y - b.min.y)
            }
            if let shift = sessionShift {
                room = room.transformed(by: RigidTransform(translation: shift))
            }
        }
        store.modify(route.project) { p in
            guard let i = p.floors.firstIndex(where: { $0.id == route.floor }) else { return }
            room.name = p.floors[i].uniqueRoomName(room.name)
            p.floors[i].rooms.append(room)
        }
    }

    private func modifyFloor(_ change: @escaping (inout Floor) -> Void) {
        store.modify(route.project) { p in
            if let i = p.floors.firstIndex(where: { $0.id == route.floor }) { change(&p.floors[i]) }
        }
    }
}
