import PlanCore
import RoomPlan
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ScanStore
    @State private var isScanning = false
    @State private var showUnsupported = false
    @State private var path: [SavedScan] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(store.scans) { scan in
                    NavigationLink(value: scan) {
                        VStack(alignment: .leading) {
                            Text(scan.name).font(.headline)
                            Text(scan.date, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { store.scans[$0] }.forEach(store.delete)
                }
            }
            .overlay {
                if store.scans.isEmpty {
                    ContentUnavailableView("No scans yet",
                                           systemImage: "camera.viewfinder",
                                           description: Text("Tap Scan Room and walk slowly around the room, pointing the camera at the walls."))
                }
            }
            .navigationTitle("MeasurePlan")
            .navigationDestination(for: SavedScan.self) { PlanDetailView(scan: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if RoomCaptureSession.isSupported { isScanning = true } else { showUnsupported = true }
                    } label: {
                        Label("Scan Room", systemImage: "camera.viewfinder")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Add Sample Room") {
                        let plan = PlanBuilder().build(from: SampleData.bedroomItems)
                        path = [store.add(plan, name: "Sample bedroom")]
                    }
                }
            }
            .fullScreenCover(isPresented: $isScanning) {
                ScanView { plan in
                    path = [store.add(plan)]
                }
            }
            .alert("Room scanning needs LiDAR", isPresented: $showUnsupported) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Room scanning works on iPhone and iPad Pro models with a LiDAR scanner. You can still try the app with a sample room from the menu.")
            }
        }
    }
}
