import CoreImage
import CoreGraphics

/// Feature Scrambler V1 — **THIRD EYE**. Copies one eye to the forehead over the course of
/// the zoom, then holds it steady. A landmark-aware Core Image compositor, not a kernel.
///
/// The reveal is driven by normalized GIF `progress`, not instantaneous zoom scale, so it
/// assembles monotonically under Zoom In, Zoom Out, and Pulse alike:
///   - `0.00...0.15` — untouched original.
///   - `0.15...0.75` — the copied eye travels from its source to the forehead, growing from
///     roughly two-thirds of its final size with one eased settle.
///   - `0.75...1.00` — the final arrangement, stable for the pause.
///
/// Padding and feather are tuned constants rather than user controls, matching Snap's
/// separate inner/outer border concepts while keeping V1 to two panel rows (INTENSITY, SIZE).
struct FeatureScramblerEffect: FaceEffect {

    private let size: CGFloat
    private let intensity: CGFloat
    private let compositor = FaceRegionCompositor()

    // MARK: - Tuned constants (Stage A)
    // Chosen from rendered output, not the live preview. See FEATURE-SCRAMBLER.md Stage A.

    /// Source area kept around the eye landmark bounds, as a fraction of those bounds. Gives
    /// the feather room and retains eyelashes beyond the tight landmark polygon.
    private let padding: CGFloat = 0.35
    /// Mask edge softness (fraction of the ellipse radius spent fading out).
    private let feather: CGFloat = 0.55

    /// Reveal window, in normalized progress.
    private let revealStart: CGFloat = 0.15
    private let revealEnd: CGFloat = 0.75

    init(size: Double = 0.5, intensity: Double = 0.75) {
        self.size = CGFloat(max(0, min(1, size)))
        self.intensity = CGFloat(max(0, min(1, intensity)))
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        // Before the reveal begins the frame is the untouched original.
        guard progress > revealStart else { return image }

        // Zero intensity is "off" — identical to the input. Any positive value keeps the
        // tuned opacity floor below, so a low-but-nonzero setting stays visible.
        guard intensity > 0 else { return image }

        guard let sourceEye = bestSourceEye(in: face),
              let sourceCenter = sourceEye.sourceCenter(in: face),
              let forehead = foreheadCenter(for: face) else { return image }

        // Normalized, eased reveal fraction across the travel window.
        let t = smoothstep(min(1, max(0, (progress - revealStart) / (revealEnd - revealStart))))

        let currentCenter = CGPoint(
            x: lerp(sourceCenter.x, forehead.x, t),
            y: lerp(sourceCenter.y, forehead.y, t)
        )

        // SIZE scales the copy relative to its source (life-size ≈ 1). It grows from two-thirds
        // toward its final size as it travels, so it settles rather than snapping into place.
        let finalScale = 0.6 + size * 0.9
        let currentScale = finalScale * lerp(0.65, 1.0, t)

        // INTENSITY is the final opacity; fade it in over the first quarter of the travel so
        // the copy emerges from the real eye instead of popping in at progress 0.15.
        let finalOpacity = 0.4 + intensity * 0.6
        let opacity = finalOpacity * min(1, t / 0.25)
        guard opacity > 0.01 else { return image }

        let placement = FaceRegionPlacement(
            region: sourceEye,
            destinationCenter: currentCenter,
            scale: currentScale,
            rotation: 0,
            opacity: opacity
        )

        return compositor.composite(
            placement,
            source: image,
            over: image,
            face: face,
            padding: padding,
            feather: feather
        )
    }

    // MARK: - Geometry

    /// The eye to copy: prefer the more complete precise polygon, else whichever eye
    /// resolves at all (so a profile face with one visible eye still works).
    private func bestSourceEye(in face: DetectedFace) -> FaceRegion? {
        let left = FaceRegion.leftEye
        let right = FaceRegion.rightEye
        let leftPts = left.polygon(in: face).count
        let rightPts = right.polygon(in: face).count

        if leftPts >= rightPts, left.isAvailable(in: face) { return left }
        if right.isAvailable(in: face) { return right }
        if left.isAvailable(in: face) { return left }
        return nil
    }

    /// Forehead target: face-centre X, Y between the brow line and the top of the face box
    /// (CIImage space is bottom-left origin, so "top" is the larger Y).
    private func foreheadCenter(for face: DetectedFace) -> CGPoint? {
        let brows = face.leftEyebrowPoints + face.rightEyebrowPoints
        let browTopY: CGFloat
        if let maxBrow = brows.map(\.y).max() {
            browTopY = maxBrow
        } else {
            // No brow landmarks: estimate a brow line above the face centre.
            browTopY = face.faceCenter.y + face.faceHeight * 0.18
        }
        let faceTopY = face.boundingBox.maxY
        guard faceTopY > browTopY else { return nil }
        let y = browTopY + (faceTopY - browTopY) * 0.5
        return CGPoint(x: face.faceCenter.x, y: y)
    }

    // MARK: - Math

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    /// Smoothstep easing — a single eased settle, deterministic, no oscillation.
    private func smoothstep(_ x: CGFloat) -> CGFloat { x * x * (3 - 2 * x) }
}
