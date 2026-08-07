import CoreImage

/// Sobel edge detection rendered as glowing tinted lines over a darkened photo.
/// The effect emerges as progress advances: normal photo → dimmed → near-black
/// with neon edges, so no dissolve is needed — the ramp is intrinsic.
struct ColoredEdgesEffect: VisualEffect {
    private let edgeIntensity: CGFloat
    private let gammaPower: CGFloat
    private let tintR: CGFloat
    private let tintG: CGFloat
    private let tintB: CGFloat

    init(intensity: Double = 0.5, color: LaserColor = .red) {
        let clamped = CGFloat(max(0, min(1, intensity)))
        self.edgeIntensity = 1.0 + 9.0 * clamped   // CIEdges sensitivity
        self.gammaPower = 1.0 - 0.55 * clamped     // <1 lifts magnitude, thickening lines

        // Normalise so the brightest channel is 1. Multiplying edge magnitude by a
        // tint whose channels stay within [0,1] keeps the hue exact at full
        // strength; scaling past 1 clips channels unevenly and shifts the colour
        // (green would render as cyan).
        let (r, g, b) = color.rgb
        let peak = max(r, max(g, b))
        let scale = peak > 0 ? 1.0 / peak : 1.0
        self.tintR = r * scale
        self.tintG = g * scale
        self.tintB = b * scale
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let t = min(1.0, progress * 1.4)
        guard t > 0.01 else { return image }

        // clampedToExtent before CIEdges is mandatory. CIEdges is a convolution, so
        // without clamping it samples off-image and paints a bright false border on
        // all four sides — it looks exactly like the filter drew a frame around the
        // photo. Crop straight back afterwards to restore the original extent.
        let edges = image
            .clampedToExtent()
            .applyingFilter("CIEdges", parameters: [
                kCIInputIntensityKey: edgeIntensity
            ])
            .cropped(to: image.extent)
            .applyingFilter("CIMaximumComponent")
            .applyingFilter("CIGammaAdjust", parameters: [
                "inputPower": gammaPower
            ])

        // Map the grayscale edge magnitude onto the tint. Coefficients stay within
        // [0,1] so a saturated edge lands on exactly the tint colour. Reading from
        // the red row only is safe because CIMaximumComponent has already collapsed
        // the channels to a single magnitude.
        let tinted = edges.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: tintR * t, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: tintG * t, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: tintB * t, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])

        // Darken multiplicatively, not with CIColorControls' brightness. Brightness
        // is an *additive* offset applied in the context's working space, which is
        // linear sRGB — so -0.55 on white lands at 0.45 linear ≈ 0.70 sRGB, barely
        // dark at all, and the tint gets swamped. Scaling the channels is
        // proportional and behaves the same in either space.
        // 0.96 rather than something gentler because the working space is linear:
        // keeping 12% of a linear value still renders around 38% in sRGB, which
        // reads as mid-grey rather than the near-black this effect wants.
        let keep = 1.0 - 0.96 * t
        let darkened = image
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.0 - 0.8 * t
            ])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: keep, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: keep, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: keep, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
            ])

        return tinted
            .applyingFilter("CIAdditionCompositing", parameters: [
                kCIInputBackgroundImageKey: darkened
            ])
            .cropped(to: image.extent)
    }
}
