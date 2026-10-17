import PlanCore
import RoomPlan
import SwiftUI

/// Full-screen RoomPlan capture. "Done" stops scanning and shows Apple's processed 3D model; "Save" turns it into a floor plan.
struct ScanView: View {
    var onSave: (FloorPlan) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var controller = CaptureControllerBox()
    @State private var capturedRoom: CapturedRoom?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            RoomCaptureRepresentable(box: controller) { room in
                capturedRoom = room
                isProcessing = false
            } onError: { error in
                errorMessage = error.localizedDescription
                isProcessing = false
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    if let room = capturedRoom {
                        Button("Save") {
                            onSave(PlanBuilder().build(from: RoomPlanConverter.items(from: room)))
                            dismiss()
                        }
                        .bold()
                    } else if isProcessing {
                        ProgressView()
                    } else {
                        Button("Done") {
                            isProcessing = true
                            controller.viewController?.finish()
                        }
                        .bold()
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                Spacer()
            }
        }
        .alert("Scan failed", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { dismiss() }
        } message: {
            Text(errorMessage ?? "")
        }
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

    private lazy var captureView = RoomCaptureView(frame: .zero)
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
        guard !isRunning else { return }
        isRunning = true
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        finish()
    }

    func finish() {
        guard isRunning else { return }
        isRunning = false
        captureView.captureSession.stop()
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
