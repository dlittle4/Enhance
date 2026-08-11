import CoreImage
import CoreGraphics

/// THIRD EYE — grows a copy of one eye out of the forehead over the zoom, tinted to a chosen
/// colour, radiating spinning god-ray beams of light. A landmark-aware Core Image compositor
/// (see `FaceRegionCompositor`), not a kernel.
///
/// The reveal is driven by normalized GIF `progress`, so it assembles monotonically under Zoom
/// In, Zoom Out, and Pulse alike:
///   - `0.00...0.15` — untouched original.
///   - `0.15...0.75` — the eye grows in place on the forehead from nothing to full size, its
///     light rays brightening and rotating with it.
///   - `0.75...1.00` — the final arrangement, stable for the pause.
///
/// The real eyes are left in place — this is a *third* eye, an addition, not a swap.
struct ThirdEyeEffect: FaceEffect {

    private let size: CGFloat
    /// Number of light rays (0 = few broad beams, 1 = many fine beams).
    private let rayIntensity: CGFloat
    private let eyeColor: LaserColor
    private let compositor = FaceRegionCompositor()

    // MARK: - Tuned constants

    private let padding: CGFloat = 0.35
    private let feather: CGFloat = 0.55
    private let revealStart: CGFloat = 0.15
    private let revealEnd: CGFloat = 0.75

    init(size: Double = 0.5, rayIntensity: Double = 0.5, eyeColor: LaserColor = .red) {
        self.size = CGFloat(max(0, min(1, size)))
        self.rayIntensity = CGFloat(max(0, min(1, rayIntensity)))
        self.eyeColor = eyeColor
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        guard progress > revealStart else { return image }

        guard let eye = bestSourceEye(in: face),
              let eyeBounds = eye.sourceBounds(in: face),
              let forehead = foreheadCenter(for: face) else { return image }

        // Eased grow-in-place: the eye scales from nothing to full at the forehead.
        let t = smoothstep(min(1, max(0, (progress - revealStart) / (revealEnd - revealStart))))
        let scale = (0.6 + size * 0.9) * t
        guard scale > 0.001 else { return image }
        let opacity = min(1, t / 0.25)  // fade in over the first quarter of the reveal
        guard opacity > 0.01 else { return image }

        var result = image

        // God-ray beams under the eye: reach and core scale with the grown eye, rays spin
        // around it (a full turn across the reveal), and INTENSITY sets how many there are.
        let eyeSize = max(eyeBounds.width, eyeBounds.height) * scale
        result = compositor.radialLight(
            at: forehead,
            coreRadius: eyeSize * 0.95,
            rayAmount: eyeSize * 2.2,
            rayDensity: rayIntensity,
            rayAngle: progress * 2 * .pi,
            color: CIColor(red: 1.0, green: 0.9, blue: 0.62, alpha: opacity),
            over: result
        )

        // The tinted eye, grown in place on the forehead, on top of the light.
        let (r, g, b) = eyeColor.rgb
        let placement = FaceRegionPlacement(region: eye, destinationCenter: forehead, scale: scale, opacity: opacity)
        result = compositor.composite(
            placement, source: image, over: result,
            face: face, padding: padding, feather: feather,
            tint: CIColor(red: r, green: g, blue: b)
        )
        return result
    }

    // MARK: - Geometry

    /// The eye to copy: prefer the more complete precise polygon, else whichever eye resolves
    /// (so a profile face with one visible eye still works).
    private func bestSourceEye(in face: DetectedFace) -> FaceRegion? {
        let left = FaceRegion.leftEye, right = FaceRegion.rightEye
        if left.polygon(in: face).count >= right.polygon(in: face).count, left.isAvailable(in: face) { return left }
        if right.isAvailable(in: face) { return right }
        if left.isAvailable(in: face) { return left }
        return nil
    }

    /// Forehead target: face-centre X, Y between the brow line and the top of the face box
    /// (CIImage space is bottom-left origin, so "top" is the larger Y).
    private func foreheadCenter(for face: DetectedFace) -> CGPoint? {
        let brows = face.leftEyebrowPoints + face.rightEyebrowPoints
        let browTopY = brows.map(\.y).max() ?? (face.faceCenter.y + face.faceHeight * 0.18)
        let faceTopY = face.boundingBox.maxY
        guard faceTopY > browTopY else { return nil }
        return CGPoint(x: face.faceCenter.x, y: browTopY + (faceTopY - browTopY) * 0.5)
    }

    private func smoothstep(_ x: CGFloat) -> CGFloat { x * x * (3 - 2 * x) }
}
