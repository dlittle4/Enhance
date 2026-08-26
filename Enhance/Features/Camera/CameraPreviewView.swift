import SwiftUI

/// Hosts whatever the service serves as its live feed — an `AVCaptureVideoPreviewLayer`-backed
/// view on device, a placeholder `UIImageView` on the simulator.
struct CameraPreviewView: UIViewRepresentable {
    let makeView: () -> UIView

    func makeUIView(context: Context) -> UIView {
        // Wrapped in a plain container so SwiftUI's proposed size always wins: the mock's
        // `UIImageView` otherwise reports its image's intrinsic size and blows the square
        // card out to the full bitmap.
        let container = UIView()
        container.clipsToBounds = true

        let inner = makeView()
        inner.frame = container.bounds
        inner.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(inner)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Rotation is owned by `AVCameraService.applyRotation(for:)` (per-device angles from
        // `RotationCoordinator`); nothing to re-apply here.
    }
}
