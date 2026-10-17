import PlanCore
import SwiftUI

struct PlanDetailView: View {
    @EnvironmentObject private var store: ScanStore
    @AppStorage("unit") private var unit: LengthUnit = .millimetres
    @State private var scan: SavedScan
    @State private var exportURL: URL?
    @State private var selectedWall: Int?
    @State private var lengthText = ""
    @State private var isEditing = false
    @State private var showInvalidLength = false

    init(scan: SavedScan) {
        _scan = State(initialValue: scan)
    }

    var body: some View {
        VStack(spacing: 0) {
            PlanPreviewView(plan: scan.plan, unit: unit, selectedWall: selectedWall) { wall in
                selectedWall = wall
                lengthText = unit.format(scan.plan.walls[wall].line.length)
                isEditing = true
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            Text("Tap a wall to type its real length. The whole plan rescales to match.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)
            Divider()
            HStack {
                Picker("Units", selection: $unit) {
                    Text("mm").tag(LengthUnit.millimetres)
                    Text("ft-in").tag(LengthUnit.inches)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                Spacer()
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Export DXF", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle(scan.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: ExportKey(unit: unit, plan: scan.plan)) { exportURL = writeDXF() }
        .alert("Real wall length", isPresented: $isEditing) {
            TextField(unit == .millimetres ? "e.g. 3650" : "e.g. 12'6\"", text: $lengthText)
                .keyboardType(unit == .millimetres ? .numberPad : .numbersAndPunctuation)
            Button("Apply") { applyLength() }
            Button("Cancel", role: .cancel) { selectedWall = nil }
        } message: {
            Text(unit == .millimetres ? "Enter the measured length in millimetres." : "Enter feet and inches, like 12'6\".")
        }
        .alert("That length isn't valid", isPresented: $showInvalidLength) {
            Button("OK") { selectedWall = nil }
        }
    }

    private func applyLength() {
        guard let wall = selectedWall else { return }
        guard let metres = unit.parse(lengthText) else {
            showInvalidLength = true
            return
        }
        scan.plan = scan.plan.calibrated(wall: wall, to: metres)
        store.update(scan)
        selectedWall = nil
    }

    /// Writes the DXF to a temporary file the share sheet can hand to Files, Mail, AirDrop and so on.
    private func writeDXF() -> URL? {
        let safeName = scan.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).dxf")
        do {
            try DXFWriter(unit: unit).write(scan.plan).write(to: url, atomically: true, encoding: .ascii)
            return url
        } catch {
            return nil
        }
    }
}

private struct ExportKey: Equatable {
    var unit: LengthUnit
    var plan: FloorPlan
}
