#if targetEnvironment(simulator)
import UIKit

/// Stands in for the hardware on the simulator, where `AVCaptureSession` has no devices.
///
/// Deliberately imperfect in the same ways a device is: `capturePhoto()` returns a
/// **non-square, non-`.up`** image (a portrait frame delivered sideways, the way a sensor
/// delivers one), so simulator QA runs the same `CameraImageProcessor` path a device does.
/// The zoom ladder is built with the triple-camera switchovers `[2, 6]` so the pill has three
/// stops to cycle.
@MainActor
final class MockCameraService: CameraServing {

    private(set) var state: CameraSessionState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    private(set) var position: CameraPosition = .back
    private(set) var zoomOptions: [CameraZoomOption]
    private(set) var currentZoomIndex: Int
    var onStateChange: ((CameraSessionState) -> Void)?
    var onPreviewFrame: ((CGImage) -> Void)?

    private let previewView = UIImageView()

    /// Mirrors the real tap's resting-off contract; the placeholder only flows while the
    /// resolve intro has asked for frames.
    private var previewFramesEnabled = false

    init() {
        let options = CameraZoomLadder.make(switchOverFactors: [2, 6], maxZoomFactor: 16)
        zoomOptions = options
        currentZoomIndex = CameraZoomLadder.defaultIndex(in: options)
    }

    func makePreviewUIView() -> UIView {
        previewView.contentMode = .scaleAspectFill
        previewView.clipsToBounds = true
        updatePreview()
        return previewView
    }

    func start() async {
        state = .starting
        try? await Task.sleep(for: .milliseconds(300))
        state = .running
        updatePreview()
    }

    func stop() {
        state = .idle
    }

    func setPreviewFrames(_ enabled: Bool) {
        previewFramesEnabled = enabled
        deliverFrameIfEnabled()
        // BURST CAPTURE on the simulator needs frames that *change*: a marker sweeps across the
        // card at 15fps while delivery is on, so a burst is a stack of distinct frames and
        // the editor's GIF visibly moves.
        liveTimer?.invalidate()
        liveTimer = nil
        if enabled {
            liveTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.deliverLiveFrame() }
            }
        }
    }

    private var liveTimer: Timer?
    private var liveTick = 0

    private func deliverLiveFrame() {
        guard previewFramesEnabled, state == .running else { return }
        liveTick += 1
        let frame = Self.renderFrame(
            size: CGSize(width: 800, height: 800),
            position: position,
            zoomLabel: zoomOptions[currentZoomIndex].label,
            markerPhase: Double(liveTick % 45) / 45
        )
        if let cg = frame.cgImage { onPreviewFrame?(cg) }
    }

    func cycleZoom() {
        currentZoomIndex = (currentZoomIndex + 1) % zoomOptions.count
        updatePreview()
    }

    func flip() async {
        position = position == .back ? .front : .back
        zoomOptions = position == .back
            ? CameraZoomLadder.make(switchOverFactors: [2, 6], maxZoomFactor: 16)
            : CameraZoomLadder.make(switchOverFactors: [], maxZoomFactor: 4)
        currentZoomIndex = CameraZoomLadder.defaultIndex(in: zoomOptions)
        updatePreview()
    }

    func capturePhoto() async throws -> UIImage {
        guard state == .running else { throw CameraServiceError.notRunning }
        try? await Task.sleep(for: .milliseconds(100))

        // A 3:4 portrait frame, rotated 90° CCW into landscape bytes and tagged `.right` —
        // the shape and tagging real hardware hands back.
        let upright = Self.renderFrame(
            size: CGSize(width: 1200, height: 1600),
            position: position,
            zoomLabel: zoomOptions[currentZoomIndex].label
        )
        guard let cgImage = Self.rotatedCCW(upright)?.cgImage else {
            throw CameraServiceError.captureFailed
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .right)
    }

    // MARK: - Placeholder rendering

    private func updatePreview() {
        previewView.image = Self.renderFrame(
            size: CGSize(width: 800, height: 800),
            position: position,
            zoomLabel: zoomOptions[currentZoomIndex].label
        )
        deliverFrameIfEnabled()
    }

    /// The placeholder as a "live frame" — a static image resolves fine, since the overlay's
    /// clock does the animating. Gated on `.running` so the real ordering (running first,
    /// then a frame) is what simulator QA exercises.
    private func deliverFrameIfEnabled() {
        guard previewFramesEnabled, state == .running,
              let frame = previewView.image?.cgImage
        else { return }
        onPreviewFrame?(frame)
    }

    /// A gradient card with a watermark, standing in for the live feed. The zoom label is
    /// painted in so cycling the pill visibly changes the "feed".
    private static func renderFrame(size: CGSize, position: CameraPosition, zoomLabel: String, markerPhase: Double? = nil) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cgContext = context.cgContext
            let colors = position == .back
                ? [UIColor(red: 0.13, green: 0.19, blue: 0.25, alpha: 1).cgColor,
                   UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1).cgColor]
                : [UIColor(red: 0.25, green: 0.15, blue: 0.22, alpha: 1).cgColor,
                   UIColor(red: 0.10, green: 0.05, blue: 0.09, alpha: 1).cgColor]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 1]
            ) {
                cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            let font = UIFont(name: "Silkscreen-Regular", size: size.width * 0.05)
                ?? .monospacedSystemFont(ofSize: size.width * 0.05, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white.withAlphaComponent(0.55)
            ]
            let lines = ["CAMERA PREVIEW", position == .back ? "REAR" : "FRONT", zoomLabel]
            for (index, line) in lines.enumerated() {
                let text = NSAttributedString(string: line, attributes: attributes)
                let textSize = text.size()
                text.draw(at: CGPoint(
                    x: (size.width - textSize.width) / 2,
                    y: size.height * 0.42 + CGFloat(index) * textSize.height * 1.4
                ))
            }

            if let markerPhase {
                let r = size.width * 0.06
                let x = size.width * 0.1 + CGFloat(markerPhase) * size.width * 0.8
                let y = size.height * 0.25 + sin(CGFloat(markerPhase) * .pi * 2) * size.height * 0.06
                cgContext.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
                cgContext.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
    }

    /// Rotates the bitmap 90° counter-clockwise, so tagging the result `.right` (rotate CW to
    /// display) round-trips back to upright.
    private static func rotatedCCW(_ image: UIImage) -> UIImage? {
        let size = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cgContext = context.cgContext
            cgContext.translateBy(x: 0, y: size.height)
            cgContext.rotate(by: -.pi / 2)
            image.draw(at: .zero)
        }
    }
}
#endif
