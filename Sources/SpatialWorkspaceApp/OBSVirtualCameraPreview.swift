import AVFoundation
import SwiftUI

enum OBSPreviewState: Equatable {
    case idle
    case requestingPermission
    case connecting
    case live
    case unavailable
    case denied

    var label: String {
        switch self {
        case .idle: "Preview idle"
        case .requestingPermission: "Camera permission"
        case .connecting: "Connecting preview"
        case .live: "Program preview"
        case .unavailable: "Preview unavailable"
        case .denied: "Camera access denied"
        }
    }
}

final class OBSVirtualCameraController: NSObject, ObservableObject {
    @Published private(set) var state: OBSPreviewState = .idle
    @Published private(set) var detail = "OBS Virtual Camera carries the current Program output"

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "dev.local.spatial-workspace.obs-preview")
    private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            state = .requestingPermission
            detail = "Allow camera access to display OBS Program inside the workspace"
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if allowed {
                        self.configureAndStart()
                    } else {
                        self.state = .denied
                        self.detail = "Enable Camera access for CommandHall in System Settings"
                    }
                }
            }
        default:
            state = .denied
            detail = "Enable Camera access for CommandHall in System Settings"
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async {
                self.state = .idle
                self.detail = "OBS preview is paused"
            }
        }
    }

    func reconnect() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.start()
        }
    }

    private func configureAndStart() {
        state = .connecting
        detail = "Opening OBS Virtual Camera"
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                if !self.configured {
                    guard let camera = Self.obsVirtualCamera() else {
                        DispatchQueue.main.async {
                            self.state = .unavailable
                            self.detail = "Start Virtual Camera in OBS, then reconnect"
                        }
                        return
                    }
                    let input = try AVCaptureDeviceInput(device: camera)
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .high
                    guard self.session.canAddInput(input) else {
                        self.session.commitConfiguration()
                        throw OBSPreviewError.inputUnavailable
                    }
                    self.session.addInput(input)
                    self.session.commitConfiguration()
                    self.configured = true
                }
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async {
                    self.state = .live
                    self.detail = "Live from OBS Virtual Camera"
                }
            } catch {
                DispatchQueue.main.async {
                    self.state = .unavailable
                    self.detail = "OBS preview failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private static func obsVirtualCamera() -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        ).devices.first {
            $0.localizedName.localizedCaseInsensitiveContains("OBS Virtual Camera")
        }
    }
}

private enum OBSPreviewError: LocalizedError {
    case inputUnavailable

    var errorDescription: String? {
        "OBS Virtual Camera could not be added to the preview session"
    }
}

struct OBSVirtualCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> OBSPreviewSurface {
        let view = OBSPreviewSurface()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: OBSPreviewSurface, context: Context) {
        nsView.previewLayer.session = session
    }
}

final class OBSPreviewSurface: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspect
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
