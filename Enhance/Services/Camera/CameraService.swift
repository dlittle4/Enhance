import UIKit

/// Which way the camera faces. A deliberate mirror of `AVCaptureDevice.Position` so the UI and
/// the pure zoom-ladder math never have to import AVFoundation.
enum CameraPosition: Equatable {
    case front
    case back
}

enum CameraSessionState: Equatable {
    case idle
    case starting
    case running
    /// A human-readable reason, shown inside the viewfinder card.
    case failed(String)
}

enum CameraServiceError: Error {
    case notRunning
    case captureFailed
}

/// The seam between the camera UI and AVFoundation.
///
/// `capturePhoto()` returns the frame **raw** — EXIF orientation and front-camera mirroring
/// intact — because normalization lives in `CameraImageProcessor` where it is one shared,
/// tested code path for both this protocol's implementations. The mock returns deliberately
/// non-`.up` images so QA in the simulator exercises the same math a device does.
@MainActor
protocol CameraServing: AnyObject {
    var state: CameraSessionState { get }
    var position: CameraPosition { get }
    var zoomOptions: [CameraZoomOption] { get }
    var currentZoomIndex: Int { get }

    /// Fired on the main actor whenever `state` changes on its own — a runtime error, an
    /// interruption ending. Awaited calls (`start`, `flip`) also fire it before returning, so
    /// one observation path covers both.
    var onStateChange: ((CameraSessionState) -> Void)? { get set }

    /// The live preview, sized by the caller. Real: a view backed by
    /// `AVCaptureVideoPreviewLayer`. Mock: a `UIImageView` placeholder.
    func makePreviewUIView() -> UIView

    func start() async
    func stop()
    func cycleZoom()
    func flip() async
    func capturePhoto() async throws -> UIImage
}

enum CameraServiceFactory {
    @MainActor
    static func make() -> any CameraServing {
        #if targetEnvironment(simulator)
        MockCameraService()
        #else
        AVCameraService()
        #endif
    }
}
