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
        service.stop()
    }

    /// Stop on backgrounding, restart on activation — the session holds hardware, and the
    /// system tears interrupted sessions down anyway.
    func sceneDidBackground() {
        guard capturedImage == nil else { return }
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
