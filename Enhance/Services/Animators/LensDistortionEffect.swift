import CoreImage

/// Radial chromatic dispersion — rainbow streaks that fan outward from a centre point,
/// clean at the centre and strongest toward the edges.
///
/// **This is a reconstruction, not a port.** It was built to match a Figma shader whose
/// source is not obtainable (the capture harness says so), by measuring the shader's
/// rendered output — see `Docs/FEATURE-LENS-DISTORTION.md`. The observed effect is *not*
/// geometric distortion despite the "lens" name; it is prismatic dispersion.
///
/// Mechanism: three `CIZoomBlur` passes, one per colour channel at different strengths.
/// A zoom blur is zero at its centre and grows radially, which gives the centre-clean /
/// edge-heavy falloff for free; running it at three different amounts and keeping one
/// channel from each pass separates the colours into the rainbow streak. Related to but
/// distinct from `ChromaticAberrationEffect` (CHROMA SHIFT), which is a *linear* constant
/// offset of the whole R and B planes.
///
/// Deliberately frame-anchored (no `FrameGeometry`): a lens aberration is a property of
/// the lens, so it should stay fixed to the output frame as the zoom pushes in, not track
/// the subject the way a dither grid must. That is why this only implements the
/// `viewportCenter` overload and leaves the geometry overload at its default.
public struct LensDistortionEffect: VisualEffect {
    /// Peak per-channel zoom-blur amount, before the progress ramp. The red channel gets
    /// the full amount and the others a fraction, so the channels smear by different radii
    /// — that spread *is* the visible dispersion.
    private let maxAmount: CGFloat

    /// 0…1. How far in from the edge the dispersion reaches: 0 confines it to the extreme
    /// corners, 1 lets it fill most of the frame.
    private let reach: CGFloat

    /// Per-channel share of `maxAmount`. Red smears most, blue least — the ordering the
    /// reference showed. The gap between them sets how saturated the fringing reads.
    private static let redScale: CGFloat = 1.0
    private static let greenScale: CGFloat = 0.62
    private static let blueScale: CGFloat = 0.30

    public init(intensity: Double = 0.5, reach: Double = 0.4) {
        // ~4…40px of zoom-blur at 600². Floored so a non-zero intensity always does
        // something visible rather than rounding to nothing.
        self.maxAmount = max(4.0, 40.0 * CGFloat(max(0, min(1, intensity))))
        self.reach = CGFloat(max(0, min(1, reach)))
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil)
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        // Quadratic ease-in, matching the other progressive effects: the dispersion
        // reveals as the zoom pushes in and holds at the pause. At progress 0 this is a
        // pass-through, which the identity test pins.
        let amount = maxAmount * (progress * progress)
        guard amount > 0.5 else { return image }

        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        let c = viewportCenter ?? CGPoint(x: extent.midX, y: extent.midY)
        let center = CIVector(x: c.x, y: c.y)

        // Clamp first so the zoom blur has data to sample past the border — otherwise the
        // radial smear pulls in transparent black and haloes the edges.
        let clamped = image.clampedToExtent()

        let redBlur = zoomBlurredChannel(clamped, center: center, amount: amount * Self.redScale,
                                         keep: .red)
        let greenBlur = zoomBlurredChannel(clamped, center: center, amount: amount * Self.greenScale,
                                           keep: .green)
        let blueBlur = zoomBlurredChannel(clamped, center: center, amount: amount * Self.blueScale,
                                          keep: .blue)

        // Each pass carries one channel with the others zeroed, so additive compositing
        // recombines them into full colour — the same recombination CHROMA SHIFT uses.
        let dispersion = redBlur
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: greenBlur])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: blueBlur])

        // REACH mask: original inside `innerR`, full dispersion beyond `outerR`, a smooth
        // ramp between. Higher reach shrinks the clean centre so the effect fills more of
        // the frame; lower reach pushes it out to the corners only.
        let maxR = hypot(extent.width, extent.height) / 2
        let innerR = maxR * (1 - reach) * 0.75
        let outerR = innerR + maxR * 0.25
        let mask = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": center,
            "inputRadius0": innerR,
            "inputRadius1": outerR,
            "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
            "inputColor1": CIColor.white
        ])!.outputImage!

        return dispersion
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: mask
            ])
            // Mandatory: the clamp made the graph infinite, and CIZoomBlur grows its
            // extent regardless — an uncropped result letterboxes the canvas and changes
            // the GIF's frame dimensions. See FisheyeEffect / LEARNINGS 2026-08-08.
            .cropped(to: extent)
    }

    private enum Channel { case red, green, blue }

    private func zoomBlurredChannel(_ image: CIImage, center: CIVector, amount: CGFloat, keep: Channel) -> CIImage {
        let blurred = image.applyingFilter("CIZoomBlur", parameters: [
            "inputCenter": center,
            "inputAmount": amount
        ])
        let r: CIVector, g: CIVector, b: CIVector
        switch keep {
        case .red:   r = CIVector(x: 1, y: 0, z: 0, w: 0); g = .init(x: 0, y: 0, z: 0, w: 0); b = .init(x: 0, y: 0, z: 0, w: 0)
        case .green: r = CIVector(x: 0, y: 0, z: 0, w: 0); g = .init(x: 0, y: 1, z: 0, w: 0); b = .init(x: 0, y: 0, z: 0, w: 0)
        case .blue:  r = CIVector(x: 0, y: 0, z: 0, w: 0); g = .init(x: 0, y: 0, z: 0, w: 0); b = .init(x: 0, y: 0, z: 1, w: 0)
        }
        return blurred.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": r,
            "inputGVector": g,
            "inputBVector": b,
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
    }
}
