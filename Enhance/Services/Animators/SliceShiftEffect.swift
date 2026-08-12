import CoreImage

/// Horizontal bands displaced sideways — the torn-signal look, built from strip
/// compositing rather than a kernel.
///
/// - `intensity` scales the maximum displacement.
/// - `size` sets the band height, i.e. how coarse the tearing reads.
/// - `jitter` blends between a regular alternating comb (0) and per-band pseudo-random
///   displacement (1). These are genuinely different looks — a comb reads as a venetian
///   blind, jitter as a broken transmission — which is why they are separate controls
///   rather than one INTENSITY driving both.
///
/// **This is a grid effect** (see EFFECTS.md): its output has a characteristic size in
/// pixels, so band height scales with `FrameGeometry.scale` and band position is phase-
/// aligned to `contentOrigin`. Without the scale the preview and the GIF disagree the
/// moment the user zooms — the preview applies effects to the un-zoomed source and lets
/// the scroll view magnify, so its bands would be `scale` times taller than the export's.
/// Without the phase the bands stay pinned to the frame and slide across the subject as
/// the animation pans, which is exactly the crawl DITHER had.
///
/// Deliberately hard-edged. The reference softens band boundaries with a smoothstep,
/// which here would mean a gradient mask per band and roughly triple the node count; the
/// hard cut is also closer to the look this effect is for.
struct SliceShiftEffect: VisualEffect {
    private let maxShift: CGFloat
    private let baseBand: CGFloat
    private let jitter: CGFloat

    /// Ceiling on how many bands are composited. Each band costs a crop, a transform and
    /// a composite, so an unbounded count turns a fine SIZE into a graph with hundreds of
    /// nodes. 64 is past the point where individual bands are distinguishable at 600px.
    private static let maxBands = 64

    init(intensity: Double = 0.5, size: Double = 0.5, jitter: Double = 0.5) {
        self.maxShift = max(2.0, 60.0 * CGFloat(max(0, min(1, intensity))))
        // 4pt bands are a fine comb; 40pt are broad slabs.
        self.baseBand = 4.0 + 36.0 * CGFloat(max(0, min(1, size)))
        self.jitter = CGFloat(max(0, min(1, jitter)))
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil, geometry: .identity)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: viewportCenter, geometry: .identity)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, geometry: FrameGeometry) -> CIImage {
        // Quadratic ease-in, so the tearing arrives once the zoom has established the
        // subject rather than being present from the first frame.
        let amount = maxShift * (progress * progress)
        guard amount > 0.5 else { return image }

        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        let scale = max(1.0, geometry.scale)
        let band = max(extent.height / CGFloat(Self.maxBands), baseBand * scale)
        let count = max(1, Int((extent.height / band).rounded(.up)))

        // Phase-align to the content so bands pin to the same image features as the frame
        // pans. Only the remainder matters — see `FrameGeometry.contentOrigin`.
        let phase = geometry.contentOrigin.y.truncatingRemainder(dividingBy: band)

        // Clamped once, outside the loop: it is the same infinite image for every band and
        // rebuilding it per band would add a node each time for nothing.
        let clamped = image.clampedToExtent()

        // Bands are laid out from one band below the origin so the phase offset cannot
        // leave an uncovered strip at the bottom edge once the result is cropped back.
        var result = image

        for i in -1..<count {
            let y = extent.origin.y + CGFloat(i) * band - phase

            // The band index has to come from the *content* position, not the loop
            // counter: the loop restarts at 0 every frame, so seeding from `i` would make
            // the pattern jump whenever the phase crosses a band boundary. Deriving it
            // from the un-phased coordinate keeps a given strip of the subject on the same
            // seed from frame to frame, so the bands flicker in place instead of marching.
            let contentIndex = Int(((y - extent.origin.y + geometry.contentOrigin.y) / band).rounded(.down))

            let dx = displacement(bandIndex: contentIndex, frameIndex: frameIndex, amount: amount)
            guard abs(dx) > 0.5 else { continue }

            let shiftedSource = clamped.transformed(by: CGAffineTransform(translationX: dx, y: 0))

            let bandRect = CGRect(x: extent.origin.x, y: y, width: extent.width, height: band)

            // Translate the clamped whole image, then crop the band out of the result. The
            // clamp stays infinite through the translate, so the band crop is always fully
            // covered and the strip cannot expose an empty sliver at the edge it moves away
            // from. Cropping a widened band first and translating that also works, but costs
            // an extra crop per band for nothing.
            let slice = shiftedSource.cropped(to: bandRect)

            result = slice.composited(over: result)
        }

        return result.cropped(to: extent)
    }

    /// Alternating comb, blended toward per-band pseudo-randomness by `jitter`.
    ///
    /// Seeded from the band and frame indices, never `random()` — GIF playback has to be
    /// reproducible and the preview has to match the export.
    private func displacement(bandIndex: Int, frameIndex: Int, amount: CGFloat) -> CGFloat {
        let comb: CGFloat = bandIndex % 2 == 0 ? amount : -amount
        guard jitter > 0.001 else { return comb }

        let h = Self.hash01(bandIndex: bandIndex, frameIndex: frameIndex)
        let random = (h - 0.5) * 2.0 * amount
        return comb * (1 - jitter) + random * jitter
    }

    /// Deterministic 0…1 hash from two integers. A small xorshift-style mix — enough to
    /// decorrelate neighbouring bands and successive frames, which is all this needs.
    private static func hash01(bandIndex: Int, frameIndex: Int) -> CGFloat {
        var x = UInt64(bitPattern: Int64(bandIndex &* 73_856_093 ^ frameIndex &* 19_349_663))
        x ^= x >> 33
        x = x &* 0xff51_afd7_ed55_8ccd
        x ^= x >> 33
        x = x &* 0xc4ce_b9fe_1a85_ec53
        x ^= x >> 33
        return CGFloat(x % 10_000) / 10_000.0
    }
}
