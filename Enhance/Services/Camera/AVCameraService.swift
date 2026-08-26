import AVFoundation
import UIKit

/// The hardware implementation of `CameraServing`.
///
/// Threading: every touch of the session — configuration, `startRunning`, input swaps, zoom
/// ramps — happens on `sessionQueue`, because `startRunning` blocks and AVFoundation wants
/// configuration serialized. The published properties (`state`, `position`, the ladder) are
/// only ever written back on the main actor.
@MainActor
final class AVCameraService: NSObject, CameraServing {

    private(set) var state: CameraSessionState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    private(set) var position: CameraPosition = .back
    private(set) var zoomOptions: [CameraZoomOption] = []
    private(set) var currentZoomIndex: Int = 0
    var onStateChange: ((CameraSessionState) -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.enhance.camera.session")

    /// Touched only on `sessionQueue`.
    private var currentInput: AVCaptureDeviceInput?
    private var isSessionConfigured = false

    /// The live preview view, if one is mounted. Weak: the overlay owns it.
    private weak var attachedPreviewView: CameraPreviewUIView?

    /// Derives the rotation each connection needs for the *current* device — the front and
    /// back sensors are not guaranteed to share an angle, which is why the angles are not
    /// hardcoded. Recreated on every configure; retained because the coordinator only
    /// reports while alive.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    /// Capture delegates are not retained by AVFoundation, so each in-flight one parks here
    /// until its completion fires.
    private var inFlightCaptures: [PhotoCaptureDelegate] = []

    private static let failureMessage = "CAMERA UNAVAILABLE"

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(sessionRuntimeError),
            name: .AVCaptureSessionRuntimeError, object: session
        )
        center.addObserver(
            self, selector: #selector(sessionWasInterrupted),
            name: .AVCaptureSessionWasInterrupted, object: session
        )
        center.addObserver(
            self, selector: #selector(sessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded, object: session
        )
    }

    // MARK: - CameraServing

    func makePreviewUIView() -> UIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        // Held weakly so rotation can be re-applied the moment a (re)configure creates a new
        // preview connection — the passive layout/update hooks alone raced that async creation
        // and left the feed in the sensor's native landscape on device.
        attachedPreviewView = view
        return view
    }

    func start() async {
        switch state {
        case .idle, .failed: break
        case .starting, .running: return
        }
        state = .starting

        let restartPosition = position
        let configured: (ladder: [CameraZoomOption], ok: Bool) = await onSessionQueue { [self] in
            if !isSessionConfigured {
                guard let ladder = configureSession(for: restartPosition) else { return ([], false) }
                isSessionConfigured = true
                if !session.isRunning { session.startRunning() }
                return (ladder, session.isRunning)
            }
            if !session.isRunning { session.startRunning() }
            let ladder = currentLadder()
            // A restart keeps the device, but the pill resets to its default stop below —
            // snap the hardware with it so label and lens agree.
            if let device = currentInput?.device {
                applyDefaultZoom(ladder, to: device)
            }
            return (ladder, session.isRunning)
        }

        if configured.ok {
            zoomOptions = configured.ladder
            currentZoomIndex = CameraZoomLadder.defaultIndex(in: configured.ladder)
            if let device = await onSessionQueue({ [self] in currentInput?.device }) {
                applyRotation(for: device)
            }
            state = .running
        } else {
            state = .failed(Self.failureMessage)
        }
    }

    func stop() {
        state = .idle
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func cycleZoom() {
        guard !zoomOptions.isEmpty else { return }
        currentZoomIndex = (currentZoomIndex + 1) % zoomOptions.count
        let factor = zoomOptions[currentZoomIndex].videoZoomFactor
        sessionQueue.async { [self] in
            guard let device = currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                // Rate tuned to feel like a lens, not a cut; optical switchovers on virtual
                // devices happen inside the ramp.
                device.ramp(toVideoZoomFactor: factor, withRate: 8)
                device.unlockForConfiguration()
            } catch {
                // A failed ramp leaves the previous factor — harmless, the label still names
                // the intent and the next tap re-applies.
            }
        }
    }

    func flip() async {
        guard state == .running else { return }
        let newPosition: CameraPosition = position == .back ? .front : .back

        let ladder: [CameraZoomOption]? = await onSessionQueue { [self] in
            configureSession(for: newPosition)
        }

        if let ladder {
            position = newPosition
            zoomOptions = ladder
            currentZoomIndex = CameraZoomLadder.defaultIndex(in: ladder)
            // The input swap tore down the old preview connection and made a new one, which
            // comes up in the sensor's native landscape again — same fix as `start()`.
            if let device = await onSessionQueue({ [self] in currentInput?.device }) {
                applyRotation(for: device)
            }
        } else {
            state = .failed(Self.failureMessage)
        }
    }

    func capturePhoto() async throws -> UIImage {
        guard state == .running else { throw CameraServiceError.notRunning }

        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .balanced

                var delegate: PhotoCaptureDelegate?
                let capture = PhotoCaptureDelegate { result in
                    DispatchQueue.main.async { [self] in
                        inFlightCaptures.removeAll { $0 === delegate }
                        continuation.resume(with: result)
                    }
                }
                delegate = capture
                DispatchQueue.main.async { [self] in inFlightCaptures.append(capture) }
                photoOutput.capturePhoto(with: settings, delegate: capture)
            }
        }
    }

    // MARK: - Session configuration (sessionQueue only)

    /// Builds or rebuilds the session around the given position's device. Returns the zoom
    /// ladder for that device, or nil when no usable device/input exists.
    private func configureSession(for position: CameraPosition) -> [CameraZoomOption]? {
        guard let device = Self.bestDevice(for: position),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return nil }

        session.beginConfiguration()
        session.sessionPreset = .photo

        if let currentInput {
            session.removeInput(currentInput)
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return nil
        }
        session.addInput(input)
        currentInput = input

        if !session.outputs.contains(photoOutput) {
            guard session.canAddOutput(photoOutput) else {
                session.commitConfiguration()
                return nil
            }
            session.addOutput(photoOutput)
        }
        photoOutput.maxPhotoQualityPrioritization = .balanced

        if let connection = photoOutput.connection(with: .video) {
            // Rotation is applied per device by `applyRotation(for:)` — the coordinator's
            // angles, not a constant. Mirroring: the preview layer auto-mirrors the front
            // camera; mirror the capture to match, so the photo that flies into the editor
            // is the frame the user composed.
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position == .front
            }
        }

        session.commitConfiguration()

        let ladder = ladder(for: device)
        applyDefaultZoom(ladder, to: device)
        return ladder
    }

    private func currentLadder() -> [CameraZoomOption] {
        guard let device = currentInput?.device else { return [] }
        return ladder(for: device)
    }

    private func ladder(for device: AVCaptureDevice) -> [CameraZoomOption] {
        CameraZoomLadder.make(
            switchOverFactors: device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) },
            // The format ceiling is digital-crop territory (often 100+); cap where the system
            // camera does so the digital 2X stop on single-module devices stays honest.
            maxZoomFactor: min(device.activeFormat.videoMaxZoomFactor, 16)
        )
    }

    /// A virtual device starts at factor 1 — the ultra-wide. Snap to the ladder's "1X" (the
    /// wide module) before the first frame is shown, without a ramp.
    private func applyDefaultZoom(_ ladder: [CameraZoomOption], to device: AVCaptureDevice) {
        guard !ladder.isEmpty else { return }
        let factor = ladder[CameraZoomLadder.defaultIndex(in: ladder)].videoZoomFactor
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = factor
            device.unlockForConfiguration()
        } catch {}
    }

    private static func bestDevice(for position: CameraPosition) -> AVCaptureDevice? {
        switch position {
        case .back:
            // Virtual devices first: they give optical switchover across modules for free.
            AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            ).devices.first
        case .front:
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
    }

    private func onSessionQueue<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            sessionQueue.async { continuation.resume(returning: work()) }
        }
    }


    /// Rotates the preview and photo connections for the given device using the angles the
    /// system derives (`RotationCoordinator`) — hardcoding 90 left the front camera sideways
    /// on hardware whose front sensor wants a different compensation. The preview connection
    /// is recreated *asynchronously* after a configure and there is no layout pass on a
    /// static card to catch it, so this polls briefly until it exists.
    private func applyRotation(for device: AVCaptureDevice, attempt: Int = 0) {
        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: attachedPreviewView?.previewLayer
        )
        rotationCoordinator = coordinator

        let captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture
        sessionQueue.async { [self] in
            if let connection = photoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(captureAngle) {
                connection.videoRotationAngle = captureAngle
            }
        }

        let previewAngle = coordinator.videoRotationAngleForHorizonLevelPreview
        if let connection = attachedPreviewView?.previewLayer.connection {
            if connection.isVideoRotationAngleSupported(previewAngle) {
                connection.videoRotationAngle = previewAngle
            }
        } else if attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.applyRotation(for: device, attempt: attempt + 1)
            }
        }
    }

    // MARK: - Session notifications

    @objc private func sessionRuntimeError(_ notification: Notification) {
        DispatchQueue.main.async { [self] in
            if state == .running || state == .starting {
                state = .failed(Self.failureMessage)
            }
        }
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        DispatchQueue.main.async { [self] in
            if state == .running { state = .starting }
        }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        DispatchQueue.main.async { [self] in
            if state == .starting { state = .running }
        }
    }
}

/// A view whose backing layer is the preview layer itself, so the feed tracks the view's
/// bounds with no manual frame management.
final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    // No rotation logic here on purpose: `AVCameraService.applyRotation(for:)` owns the
    // angles via `RotationCoordinator`, per device. A hardcoded 90° fallback in
    // `layoutSubviews` would silently clobber the coordinator's answer on every layout —
    // exactly wrong for a front sensor whose angle differs.
}

/// Bridges one `capturePhoto` call to a completion. AVFoundation calls back on an arbitrary
/// queue; the owner hops to main.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<UIImage, Error>) -> Void

    init(completion: @escaping (Result<UIImage, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            completion(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            completion(.failure(CameraServiceError.captureFailed))
            return
        }
        completion(.success(image))
    }
}
