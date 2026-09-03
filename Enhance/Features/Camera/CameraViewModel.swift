import AVFoundation
import SwiftUI

/// State for the camera overlay — the `FeatureFlags.cameraCapture` experiment.
///
/// Thin on purpose: hardware truth lives in the `CameraServing` service and is mirrored here
/// after every call, because `@Observable` tracks this class's stored properties, not the
/// service's. Image normalization is delegated to `CameraImageProcessor` so the interesting
/// logic stays in tested, pure functions.
@Observable
@MainActor
final class CameraViewModel {

    enum Permission: Equatable {
        case undetermined
        case granted
        case denied
    }

    private(set) var permission: Permission = .undetermined
    private(set) var sessionState: CameraSessionState = .idle
    private(set) var zoomLabel: String = "1X"
    private(set) var position: CameraPosition = .back
    private(set) var isCapturing = false

    /// The normalized, square capture — setting this is what freezes the viewfinder and
    /// starts the handoff into the editor.
    private(set) var capturedImage: UIImage?

    /// The latest live frame, flowing only while the resolve intro has asked for frames
    /// (`beginIntroFrames`). Its first non-nil value is the app's real "the feed has
    /// rendered" signal — `sessionState == .running` only means the session started.
    private(set) var previewFrame: CGImage?

    private let service: any CameraServing
    private let authorizationStatus: () -> AVAuthorizationStatus
    private let requestAccess: () async -> Bool

    /// Everything injected so tests drive the overlay logic against a stub, without touching
    /// TCC; callers take the defaults (hardware on device, mock on simulator).
    init(
        service: (any CameraServing)? = nil,
        authorizationStatus: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .video) },
        requestAccess: @escaping () async -> Bool = { await AVCaptureDevice.requestAccess(for: .video) }
    ) {
        self.service = service ?? CameraServiceFactory.make()
        self.authorizationStatus = authorizationStatus
        self.requestAccess = requestAccess
        self.service.onStateChange = { [weak self] state in
            self?.sessionState = state
        }
        self.service.onPreviewFrame = { [weak self] frame in
            guard let self else { return }
            self.previewFrame = frame
            self.collectBurstFrame(frame)
        }
    }

    // MARK: - Burst capture (`FeatureFlags.burstCapture`)

    /// True from the shutter being held long enough until it is released. The overlay shows a
    /// recording cue while this is on.
    private(set) var isBursting = false
    /// Real frames from the tap, in order, sampled down to `burstFPS`.
    private var burstRaw: [CGImage] = []
    private var burstStartedAt: Date?
    private var burstLastKeptAt: Date?
    private var burstFPS: Double = 12
    private var burstDuration: Double = 1.5
    private var burstAutoStop: Task<Void, Never>?
    /// The normalized burst, alongside `capturedImage` (its first frame). Set by `endBurst`.
    private(set) var capturedBurst: [UIImage]?

    /// Starts recording. Frames arrive through the same tap the resolve intro uses; the
    /// `previewFrame` mirror keeps flowing, which is harmless. Auto-stops at `duration`, so a
    /// finger that never lifts still gets a burst rather than an ever-growing array.
    func beginBurst(fps: Double, duration: Double) {
        guard !isBursting, capturedImage == nil, service.state == .running else { return }
        isBursting = true
        burstRaw = []
        burstStartedAt = Date()
        burstLastKeptAt = nil
        burstFPS = max(1, fps)
        burstDuration = max(0.2, duration)
        service.setPreviewFrames(true)
        burstAutoStop = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(duration * 1000)))
            guard !Task.isCancelled, let self, self.isBursting else { return }
            await self.endBurst()
        }
    }

    private func collectBurstFrame(_ frame: CGImage) {
        guard isBursting, let started = burstStartedAt else { return }
        let now = Date()
        guard now.timeIntervalSince(started) <= burstDuration else { return }
        if let last = burstLastKeptAt, now.timeIntervalSince(last) < 1 / burstFPS { return }
        burstLastKeptAt = now
        burstRaw.append(frame)
    }

    /// Stops recording and, with enough frames, normalizes them into the capture. Fewer than
    /// `minimumBurstFrames` — a hold released almost at once — falls back to nothing, so the
    /// shutter's ordinary tap path can take the photo instead.
    static let minimumBurstFrames = 4

    @discardableResult
    func endBurst() async -> [UIImage]? {
        guard isBursting else { return nil }
        isBursting = false
        burstAutoStop?.cancel()
        burstAutoStop = nil
        service.setPreviewFrames(false)
        let raw = burstRaw
        burstRaw = []
        guard raw.count >= Self.minimumBurstFrames else { return nil }

        let side = CanvasTuningStore.shared.tuning.burstFrameSide
        let frames = await Self.normalizeBurst(raw, side: side)
        guard let first = frames.first else { return nil }
        service.stop()
        withAnimation(.easeOut(duration: 0.25)) {
            capturedImage = first
        }
        capturedBurst = frames
        return frames
    }

    /// Every frame square-cropped and scaled to one exact size, so the generator can treat
    /// the stack as one image that changes. The tap already delivered them upright.
    nonisolated static func normalizeBurst(_ raw: [CGImage], side: Double) async -> [UIImage] {
        await Task.detached(priority: .userInitiated) {
            let target = CGSize(width: side, height: side)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: target, format: format)
            return raw.map { cg in
                let square = CameraImageProcessor.centerSquareCrop(UIImage(cgImage: cg))
                return renderer.image { _ in
                    square.draw(in: CGRect(origin: .zero, size: target))
                }
            }
        }.value
    }

    /// Start frame delivery for the resolve intro. Idempotent; the overlay calls it before
    /// the session starts so the very first frame is caught.
    func beginIntroFrames() {
        service.setPreviewFrames(true)
    }

    /// The intro is over (or aborted): stop the tap and drop the held frame. Every terminal
    /// path funnels here — the intro must never outlive the feed it covers.
    func endIntroFrames() {
        service.setPreviewFrames(false)
        previewFrame = nil
    }

    func makePreviewUIView() -> UIView {
        service.makePreviewUIView()
    }

    /// Checks (and if undetermined, requests) camera permission, then starts the session.
    /// Called from the overlay's `.task` and again when the app re-activates, so returning
    /// from Settings with access newly granted recovers live.
    func openCamera() async {
        switch authorizationStatus() {
        case .authorized:
            permission = .granted
        case .notDetermined:
            permission = await requestAccess() ? .granted : .denied
        default:
            permission = .denied
        }
        guard permission == .granted, capturedImage == nil else { return }

        await service.start()
        syncFromService()
    }

    func capture() async {
        // The service's state is the truth; `sessionState` is a repaint mirror.
        guard !isCapturing, capturedImage == nil, service.state == .running else { return }
        isCapturing = true
        defer { isCapturing = false }
        endIntroFrames()

        do {
            let raw = try await service.capturePhoto()
            let processed = await Self.normalize(raw)
            service.stop()
            // Animated here rather than by an `.animation(value:)` in the overlay: a subtree
            // animation modifier would also inject itself into the overlay's insertion
            // transaction and kill the launch transition (it did — see CameraOverlayView).
            withAnimation(.easeOut(duration: 0.25)) {
                capturedImage = processed
            }
        } catch {
            // A failed capture keeps the viewfinder live — the shutter simply didn't take,
            // and the next press tries again.
        }
    }

    func cycleZoom() {
        service.cycleZoom()
        syncFromService()
    }

    func flip() async {
        await service.flip()
        syncFromService()
    }

    func close() {
        endIntroFrames()
        service.stop()
    }

    /// Stop on backgrounding, restart on activation — the session holds hardware, and the
    /// system tears interrupted sessions down anyway.
    func sceneDidBackground() {
        guard capturedImage == nil else { return }
        endIntroFrames()
        service.stop()
        syncFromService()
    }

    func sceneDidActivate() async {
        guard capturedImage == nil else { return }
        await openCamera()
    }

    private func syncFromService() {
        sessionState = service.state
        position = service.position
        let options = service.zoomOptions
        if options.indices.contains(service.currentZoomIndex) {
            zoomLabel = options[service.currentZoomIndex].label
        }
    }

    /// Orientation + mirroring baked in, then cropped to the square the viewfinder showed.
    /// Off-main: these redraw the full-size capture.
    private nonisolated static func normalize(_ image: UIImage) async -> UIImage {
        await Task.detached(priority: .userInitiated) {
            CameraImageProcessor.centerSquareCrop(CameraImageProcessor.normalizedUp(image))
        }.value
    }
}
