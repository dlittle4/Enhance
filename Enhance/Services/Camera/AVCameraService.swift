import AVFoundation
import CoreImage
import UIKit

/// The hardware implementation of `CameraServing`.
///
/// Threading: every touch of the session — configuration, `startRunning`, input swaps, zoom
/// ramps — happens on `sessionQueue`, because `startRunning` blocks and AVFoundation wants
/// configuration serialized. That queue-confined world lives in `CameraSessionCore`, off the
/// main actor, so the queue closures never reach into main-actor state. The published
/// properties (`state`, `position`, the ladder) are only ever written back on the main actor.
@MainActor
final class AVCameraService: NSObject, CameraServing {

    private(set) var state: CameraSessionState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    private(set) var position: CameraPosition = .back
    private(set) var zoomOptions: [CameraZoomOption] = []
    private(set) var currentZoomIndex: Int = 0
    var onStateChange: ((CameraSessionState) -> Void)?
    var onPreviewFrame: ((CGImage) -> Void)?

    private let core = CameraSessionCore()
    private let sessionQueue = DispatchQueue(label: "com.enhance.camera.session")

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
        // Set before anything runs, like the session reads below; the tap hops to main
        // before calling this, matching the delegate hops elsewhere in this file.
        core.frameTap.onFrame = { [weak self] frame in
            self?.onPreviewFrame?(frame)
        }
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(sessionRuntimeError),
            name: AVCaptureSession.runtimeErrorNotification, object: core.session
        )
        center.addObserver(
            self, selector: #selector(sessionWasInterrupted),
            name: AVCaptureSession.wasInterruptedNotification, object: core.session
        )
        center.addObserver(
            self, selector: #selector(sessionInterruptionEnded),
            name: AVCaptureSession.interruptionEndedNotification, object: core.session
        )
    }

    // MARK: - CameraServing

    func makePreviewUIView() -> UIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = core.session
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
        let configured = await onSessionQueue { [core] in
            core.start(for: restartPosition)
        }

        if configured.ok {
            zoomOptions = configured.ladder
            currentZoomIndex = CameraZoomLadder.defaultIndex(in: configured.ladder)
            if let device = await onSessionQueue({ [core] in core.currentDevice }) {
                applyRotation(for: device)
            }
            state = .running
        } else {
            state = .failed(Self.failureMessage)
        }
    }

    func stop() {
        state = .idle
        sessionQueue.async { [core] in
            core.stopRunning()
        }
    }

    func setPreviewFrames(_ enabled: Bool) {
        core.setPreviewFrames(enabled)
    }

    func cycleZoom() {
        guard !zoomOptions.isEmpty else { return }
        currentZoomIndex = (currentZoomIndex + 1) % zoomOptions.count
        let factor = zoomOptions[currentZoomIndex].videoZoomFactor
        sessionQueue.async { [core] in
            core.rampZoom(to: factor)
        }
    }

    func flip() async {
        guard state == .running else { return }
        let newPosition: CameraPosition = position == .back ? .front : .back

        let ladder: [CameraZoomOption]? = await onSessionQueue { [core] in
            core.configureSession(for: newPosition)
        }

        if let ladder {
            position = newPosition
            zoomOptions = ladder
            currentZoomIndex = CameraZoomLadder.defaultIndex(in: ladder)
            // The input swap tore down the old preview connection and made a new one, which
            // comes up in the sensor's native landscape again — same fix as `start()`.
            if let device = await onSessionQueue({ [core] in core.currentDevice }) {
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
                core.photoOutput.capturePhoto(with: settings, delegate: capture)
            }
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
        let tapAngle = coordinator.videoRotationAngleForHorizonLevelPreview
        // The tap's one source of rotation truth: frames are dropped until this lands.
        core.setTapTargetAngle(tapAngle)
        sessionQueue.async { [core] in
            if let connection = core.photoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(captureAngle) {
                connection.videoRotationAngle = captureAngle
            }
            // The tapped frames take the *preview* angle, not the capture's — during the
            // resolve intro they are drawn where the preview layer shows.
            if let connection = core.videoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(tapAngle) {
                connection.videoRotationAngle = tapAngle
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

/// The queue-confined half of `AVCameraService`: the capture session and everything
/// AVFoundation wants serialized. Members are touched only on the service's `sessionQueue`
/// once the session is live (the main actor reads `session` during setup, before anything
/// runs). `@unchecked Sendable` states that discipline to the compiler — nothing here is
/// thread-safe on its own.
private final class CameraSessionCore: @unchecked Sendable {

    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()

    /// The resolve intro's frame source. The output stays attached for the session's whole
    /// life — no mid-run reconfiguration — and `VideoFrameTap.enabled` is the switch: off,
    /// each delivered buffer costs one guard-return on `videoQueue`.
    let videoOutput = AVCaptureVideoDataOutput()
    let frameTap: VideoFrameTap
    private let videoQueue = DispatchQueue(label: "com.enhance.camera.video")

    private var currentInput: AVCaptureDeviceInput?
    private var isSessionConfigured = false

    init() {
        frameTap = VideoFrameTap(clearQueue: videoQueue)
    }

    func setPreviewFrames(_ enabled: Bool) {
        videoQueue.async { [frameTap] in frameTap.enabled = enabled }
    }

    /// The angle tapped frames must present at to match the preview layer. Callable from
    /// any queue; the tap reads it only on the video queue.
    func setTapTargetAngle(_ angle: CGFloat) {
        videoQueue.async { [frameTap] in frameTap.targetAngle = angle }
    }

    var currentDevice: AVCaptureDevice? { currentInput?.device }

    /// First call configures the session; later calls just spin it back up.
    func start(for position: CameraPosition) -> (ladder: [CameraZoomOption], ok: Bool) {
        if !isSessionConfigured {
            guard let ladder = configureSession(for: position) else { return ([], false) }
            isSessionConfigured = true
            if !session.isRunning { session.startRunning() }
            return (ladder, session.isRunning)
        }
        if !session.isRunning { session.startRunning() }
        let ladder = currentLadder()
        // A restart keeps the device, but the pill resets to its default stop —
        // snap the hardware with it so label and lens agree.
        if let device = currentInput?.device {
            applyDefaultZoom(ladder, to: device)
        }
        return (ladder, session.isRunning)
    }

    func stopRunning() {
        if session.isRunning { session.stopRunning() }
    }

    func rampZoom(to factor: CGFloat) {
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

    /// Builds or rebuilds the session around the given position's device. Returns the zoom
    /// ladder for that device, or nil when no usable device/input exists.
    func configureSession(for position: CameraPosition) -> [CameraZoomOption]? {
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

        // The resolve intro's frame tap. A session that cannot take a data output still
        // runs the camera — the overlay's fallback timeout degrades the intro to the plain
        // fade, so this never fails the configure.
        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(frameTap, queue: videoQueue)
            session.addOutput(videoOutput)
        }
        if let connection = videoOutput.connection(with: .video) {
            // Tapped frames stand in for the preview layer, which auto-mirrors the front
            // camera — mirror to match or the intro would flip at handoff. Outside the
            // add-once guard: an input swap recreates the connection.
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position == .front
            }
            // Rotation is deliberately NOT set here. A device-only coordinator created on
            // this queue reports a preview angle of 0 — measured on device — so seeding
            // from it armed the wrong angle; only `applyRotation`'s preview-layer
            // coordinator tells the truth. Until it has spoken, the tap has no target and
            // *drops* frames rather than drawing the sensor's native landscape.
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

/// Converts tapped video buffers to `CGImage`s for the resolve intro, coalesced to the main
/// thread's own pace: no new conversion starts until main has consumed the previous frame,
/// so a slow main thread drops frames instead of queueing them.
///
/// `enabled` and `awaitingMain` are touched only on the video queue — the delegate's queue,
/// which is also `clearQueue` — so neither needs a lock.
private final class VideoFrameTap: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    var enabled = false

    /// The angle frames must present at to match the preview layer — the coordinator's
    /// horizon-level preview angle. Frames whose connection already carries this angle
    /// pass through untouched; ones the hardware left in another orientation are rotated
    /// here, and frames arriving before the target is known are dropped rather than drawn
    /// sideways. On device the first frames shipped in the sensor's native landscape and
    /// the whole intro played rotated — this is what makes that impossible.
    var targetAngle: CGFloat?

    /// Invoked on the main queue with the converted frame.
    var onFrame: ((CGImage) -> Void)?

    private var awaitingMain = false
    private let clearQueue: DispatchQueue
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// The frames feed a mosaic that only approaches full sharpness in its last beats, and
    /// the handoff to the real preview layer is a cross-fade — a short side of 640 is
    /// indistinguishable there and keeps each conversion trivial.
    private static let maxShortSide: CGFloat = 640

    init(clearQueue: DispatchQueue) {
        self.clearQueue = clearQueue
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard enabled, !awaitingMain, let targetAngle,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        var image = CIImage(cvPixelBuffer: pixelBuffer)
        // Judged from the buffer itself, not `connection.videoRotationAngle`: after the
        // angle is set the connection *reports* it immediately, but buffers keep arriving
        // sensor-native for a handful of frames before the rotation engages — measured on
        // device. Aspect is the honest signal in a portrait-only app: a landscape buffer
        // under a portrait target has not been rotated yet, whatever the connection claims.
        if let correction = Self.correction(
            bufferPortrait: image.extent.height > image.extent.width,
            target: targetAngle
        ) {
            image = image.oriented(correction)
        }
        let shortSide = min(image.extent.width, image.extent.height)
        if shortSide > Self.maxShortSide {
            let scale = Self.maxShortSide / shortSide
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let frame = ciContext.createCGImage(image, from: image.extent) else { return }

        awaitingMain = true
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(frame)
            self?.clearQueue.async { self?.awaitingMain = false }
        }
    }

    /// The orientation that carries a still-sensor-native buffer to the target angle, or
    /// nil when the buffer's aspect already agrees with the target's.
    ///
    /// The anchor for the mapping: an unrotated buffer sits at angle 0 — the sensor's
    /// native landscape — and displays upright as EXIF `.right`, the same fact
    /// `MockCameraService` documents for captures ("landscape bytes tagged `.right`").
    private static func correction(bufferPortrait: Bool, target: CGFloat) -> CGImagePropertyOrientation? {
        let targetPortrait = target == 90 || target == 270
        guard bufferPortrait != targetPortrait else { return nil }
        switch target {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return nil
        }
    }
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
