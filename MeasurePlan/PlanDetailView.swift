import PlanCore
import SwiftUI

struct PlanDetailView: View {
    var scan: SavedScan

    @AppStorage("unit") private var unit: LengthUnit = .millimetres
    @State private var exportURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            PlanPreviewView(plan: scan.plan, unit: unit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
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
        .task(id: unit) { exportURL = writeDXF() }
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
