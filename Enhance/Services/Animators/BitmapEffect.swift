import CoreImage
import CoreGraphics

/// 1-bit **clustered-dot** halftone in two arbitrary spot colours — the Game Boy Camera /
/// Playdate look. ROADMAP §2b; full spec in EFFECTS.md → "Bitmap".
///
/// **The spike this row called for is answered: no kernel is needed.** The screen comes from
/// thresholding luminance against a tiled 8×8 clustered-dot matrix, which stock Core Image can
/// express — the matrix is a tiny `CGImage`, `CIAffineTile` repeats it, a subtract puts the
/// comparison at zero, and a hard contrast turns that into a 1-bit step. `CIFalseColor` then
/// maps the two states to the chosen colours. The §1c gate would have made a kernel ordinary
/// work, but it buys nothing here.
///
/// **Why this is not DITHER's deferred MONO row.** DITHER posterises `CIDither`'s blue *noise*
/// (`DitherEffect.swift:96-105`). Noise scatters and never resolves into the regular crosshatch
/// that defines this look; that hatch is a property of the *matrix*, whose cells grow as a blob
/// and touch corners through the midtones. DUOTONE has the colour mapping but no screen at all,
/// and HALFTONE's screen is `CICMYKHalftone`'s four-channel rosette in full colour.
///
/// **Grid effect, non-negotiable.** The cell scales with `FrameGeometry.scale` and phase-aligns
/// to `contentOrigin` exactly as DITHER does. Without both, the screen crawls across the subject
/// as the animation pans — a static overlay the photo slides beneath.
struct BitmapEffect: VisualEffect {
    private let hardness: CGFloat
    private let baseCell: CGFloat
    private let shadow: CIColor
    private let highlight: CIColor

    /// Beyond this the dots read as blocks rather than a screen.
    private static let maxCell: CGFloat = 14

    init(intensity: Double = 0.5, size: Double = 0.5, stops: GradientStops = .default) {
        self.hardness = CGFloat(max(0, min(1, intensity)))
        // 2…10pt. Below 2 the matrix is finer than the GIF's own pixel grid and the hatch is
        // invisible; the cap is `maxCell` once the zoom multiplies it.
        self.baseCell = 2 + CGFloat(max(0, min(1, size))) * 8
        // Two stops, not three: this is a 1-bit screen, so the MID colour has nowhere to go.
        // The picker still shows three wells because it is the shared `.gradientStops` row —
        // worth knowing before someone "fixes" the middle one being inert.
        let resolved = stops.resolved
        self.shadow = Self.ciColor(resolved.first?.rgb)
        self.highlight = Self.ciColor(resolved.last?.rgb)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil, geometry: .identity)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: viewportCenter, geometry: .identity)
    }

    func apply(
        to image: CIImage,
        progress: CGFloat,
        frameIndex: Int,
        viewportCenter: CGPoint?,
        geometry: FrameGeometry
    ) -> CIImage {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1 else { return image }

        let amount = min(1, progress * 1.4)
        guard amount > 0.01, let tile = Self.matrixTile else { return image }

        let cell = min(Self.maxCell, max(1, baseCell * max(1, geometry.scale)))

        // Same phase trick as DITHER: offsetting by the content origin modulo the cell pins the
        // screen to the same image features as the frame pans.
        let phaseX = geometry.contentOrigin.x.truncatingRemainder(dividingBy: cell)
        let phaseY = geometry.contentOrigin.y.truncatingRemainder(dividingBy: cell)

        // One matrix cell spans `cell` points, so the 8px tile scales by cell/8.
        let screen = tile
            .transformed(by: CGAffineTransform(scaleX: cell / 8, y: cell / 8))
            .applyingFilter("CIAffineTile", parameters: [
                kCIInputTransformKey: CGAffineTransform(scaleX: cell / 8, y: cell / 8)
            ])
            .transformed(by: CGAffineTransform(translationX: phaseX, y: phaseY))
            .cropped(to: extent)

        let luma = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            // Contrast before the screen, or a flat photo collapses into one tone and prints as
            // a single colour — the same failure RISO's CONTRAST row exists to prevent.
            kCIInputContrastKey: 1.0 + hardness * 0.6
        ])

        // luma - screen + 0.5 puts the comparison at mid grey, then a large contrast turns the
        // sign of that difference into a hard 1-bit step.
        let difference = luma
            .applyingFilter("CISubtractBlendMode", parameters: [
                kCIInputBackgroundImageKey: screen
            ])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: 0.5,
                kCIInputContrastKey: 40.0
            ])
            .applyingFilter("CIColorClamp")

        let inked = difference.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": shadow,
            "inputColor1": highlight
        ])

        // Ramp in with progress like every other effect, so the card can be previewed part-way
        // and the GIF does not snap to full strength on frame one.
        return image
            .applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: inked,
                kCIInputTimeKey: amount
            ])
            .cropped(to: extent)
    }

    private static func ciColor(_ rgb: RGB?) -> CIColor {
        guard let rgb else { return CIColor(red: 0, green: 0, blue: 0) }
        return CIColor(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    // MARK: - The screen

    /// An 8×8 **clustered-dot** ordered-dither matrix as a one-tile image.
    ///
    /// Clustered rather than dispersed (Bayer) deliberately: the entries spiral outward from two
    /// centres, so as a region darkens its dots *grow and merge* instead of scattering, and the
    /// midtones resolve into the crosshatch that is this effect's signature. A Bayer matrix at
    /// the same size gives an even stipple that reads as noise.
    ///
    /// Built once — it depends on nothing per-frame, and rebuilding an 8×8 `CGImage` per frame
    /// would be pure waste in a path that runs 30 times per GIF.
    private static let matrixTile: CIImage? = {
        // The standard 8×8 clustered-dot threshold matrix, 0…63.
        let m: [Int] = [
            24, 10, 12, 26, 35, 47, 49, 37,
             8,  0,  2, 14, 45, 59, 61, 51,
            22,  6,  4, 16, 43, 57, 63, 53,
            30, 20, 18, 28, 33, 41, 55, 39,
            34, 46, 48, 38, 25, 11, 13, 27,
            44, 58, 60, 50,  9,  1,  3, 15,
            42, 56, 62, 52, 23,  7,  5, 17,
            32, 40, 54, 36, 31, 21, 19, 29
        ]
        // Spread 0…63 across 0…255 so the screen uses the full comparison range.
        var pixels = m.map { UInt8(($0 * 255) / 63) }

        return pixels.withUnsafeMutableBytes { raw -> CIImage? in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ), let cg = ctx.makeImage() else { return nil }
            return CIImage(cgImage: cg)
        }
    }()
}
