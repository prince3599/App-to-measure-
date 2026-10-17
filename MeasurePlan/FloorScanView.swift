import ARKit
import PlanCore
import RoomPlan
import SwiftUI

/// Scans several rooms in one AR session so they share one coordinate system and line up on the plan.
struct FloorScanView: View {
    var floorName: String
    /// Called for each room the user keeps.
    var onRoom: (CapturedRoom) -> Void

    private enum Phase {
        case scanning
        case processing
        case review(CapturedRoom)
        case failed(String)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var controller = CaptureControllerBox()
    @State private var phase = Phase.scanning
    @State private var roomsSaved = 0

    var body: some View {
        ZStack {
            RoomCaptureRepresentable(box: controller) { room in
                phase = .review(room)
            } onError: { error in
                phase = .failed(error.localizedDescription)
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button("Close") { close() }
                    Spacer()
                    Text("\(floorName) · \(roomsSaved) saved").font(.subheadline.bold())
                    Spacer()
                    switch phase {
                    case .scanning:
                        Button("Room Done") {
                            phase = .processing
                            controller.viewController?.finishRoom()
                        }
                        .bold()
                    case .processing:
                        ProgressView()
                    default:
                        Color.clear.frame(width: 60, height: 1)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)

                Spacer()

                Group {
                    switch phase {
                    case .scanning where roomsSaved == 0:
                        Text("Walk slowly around the room. Point at every wall, corner, door and window.")
                    case .scanning:
                        Text("Scanning the next room. Start from the doorway you just walked through.")
                    case let .review(room):
                        VStack(spacing: 10) {
                            Text("Room scanned").font(.headline)
                            Button("Save and Scan Next Room") {
                                onRoom(room)
                                roomsSaved += 1
                                phase = .scanning
                                controller.viewController?.startRoom()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Save and Finish Floor") {
                                onRoom(room)
                                close()
                            }
                            .buttonStyle(.bordered)
                            Button("Discard and Rescan", role: .destructive) {
                                phase = .scanning
                                controller.viewController?.startRoom()
                            }
                        }
                    case let .failed(message):
                        VStack(spacing: 10) {
                            Text("Scan failed: \(message)")
                            Button("Try Again") {
                                phase = .scanning
                                controller.viewController?.startRoom()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    case .processing:
                        Text("Processing room…")
                    }
                }
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: 500)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding()
            }
        }
    }

    private func close() {
        controller.viewController?.endSession()
        dismiss()
    }
}

final class CaptureControllerBox {
    weak var viewController: RoomCaptureViewController?
}

struct RoomCaptureRepresentable: UIViewControllerRepresentable {
    var box: CaptureControllerBox
    var onFinished: (CapturedRoom) -> Void
    var onError: (Error) -> Void

    func makeUIViewController(context: Context) -> RoomCaptureViewController {
        let vc = RoomCaptureViewController()
        box.viewController = vc
        return vc
    }

    func updateUIViewController(_ vc: RoomCaptureViewController, context: Context) {
        vc.onFinished = onFinished
        vc.onError = onError
    }
}

final class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate {
    var onFinished: ((CapturedRoom) -> Void)?
    var onError: ((Error) -> Void)?

    /// Shared by every room on the floor, so all rooms use the same coordinates.
    private let arSession = ARSession()
    private lazy var captureView = RoomCaptureView(frame: .zero, arSession: arSession)
    private var isRunning = false

    override func viewDidLoad() {
        super.viewDidLoad()
        captureView.frame = view.bounds
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        captureView.delegate = self
        view.addSubview(captureView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startRoom()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        endSession()
    }

    func startRoom() {
        guard !isRunning else { return }
        isRunning = true
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    /// Ends this room's scan but keeps AR tracking alive for the next room.
    func finishRoom() {
        guard isRunning else { return }
        isRunning = false
        captureView.captureSession.stop(pauseARSession: false)
    }

    func endSession() {
        if isRunning {
            isRunning = false
            captureView.captureSession.stop()
        }
        arSession.pause()
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error {
            onError?(error)
        } else {
            onFinished?(processedResult)
        }
    }
}
