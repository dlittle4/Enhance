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
    private let toneContrast: CGFloat
    private let baseCell: CGFloat
    private let shadow: CIColor
    private let highlight: CIColor

    /// Beyond this the dots read as blocks rather than a screen. A multiple of 8, since the cell
    /// is rounded to whole matrix widths.
    private static let maxCell: CGFloat = 32

    init(intensity: Double = 0.5, size: Double = 0.5, contrast: Double = 0.5,
         stops: GradientStops = .default) {
        self.hardness = CGFloat(max(0, min(1, intensity)))
        // Its own row on the user's call (2026-08-18): the first render read muddy, and the
        // lever that fixes that is how hard the tones are pushed apart *before* the screen
        // compares them — not the screen itself, which was already right.
        self.toneContrast = CGFloat(max(0, min(1, contrast)))
        // 8…24pt, rounded to whole matrix widths at use. Below one matrix width the screen has
        // no room to form a dot at all; the cap is `maxCell` once the zoom multiplies it.
        self.baseCell = 8 + CGFloat(max(0, min(1, size))) * 16
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

        // Rounded to a whole multiple of 8 so `cell / 8` is an integer and every matrix entry
        // lands on a whole pixel. A fractional cell is the other half of the seam problem above.
        let rawCell = min(Self.maxCell, max(1, baseCell * max(1, geometry.scale)))
        let cell = max(8, (rawCell / 8).rounded() * 8)

        // Same phase trick as DITHER: offsetting by the content origin modulo the cell pins the
        // screen to the same image features as the frame pans.
        let phaseX = geometry.contentOrigin.x.truncatingRemainder(dividingBy: cell)
        let phaseY = geometry.contentOrigin.y.truncatingRemainder(dividingBy: cell)

        // `CIAffineTile` transforms the image *and then* tiles it, so the scale belongs only in
        // its transform. An earlier version also pre-scaled the tile, which put tile edges on
        // fractional pixels — invisible at low contrast and, once the threshold was steep,
        // amplified into a visible grid of seams across the image *(user-reported)*.
        //
        // `samplingNearest` for the same reason: the matrix is a threshold lookup, not a
        // picture, and interpolating between neighbouring entries smears the boundary between
        // two dot sizes into a value that thresholds inconsistently along cell edges.
        let screen = tile
            .samplingNearest()
            .applyingFilter("CIAffineTile", parameters: [
                kCIInputTransformKey: CGAffineTransform(scaleX: cell / 8, y: cell / 8)
            ])
            .transformed(by: CGAffineTransform(translationX: phaseX, y: phaseY))
            .cropped(to: extent)

        let luma = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            // Contrast before the screen, or a flat photo collapses into one tone and prints as
            // a single colour — the same failure RISO's CONTRAST row exists to prevent.
            // 0.8…2.6. The top of that range is what separates a flat photo into distinct
            // dot densities instead of one muddy midtone.
            kCIInputContrastKey: 0.8 + toneContrast * 1.8,
            // Lift slightly with contrast, or pushing the tones apart drags the whole image
            // dark — which is exactly how the first render failed.
            kCIInputBrightnessKey: toneContrast * 0.12
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
