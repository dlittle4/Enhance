import CoreImage

/// Concentric outlines of the subject radiating outward from it — ROADMAP §2f's
/// "subject repeated into a pattern", drawn as edges rather than filled copies.
///
/// Mechanically it is the pattern effect: N transformed copies of the segmented subject
/// composited behind the original. The look differs in two choices — each copy is reduced to
/// its *outline* by a morphology gradient, and the copies scale about the subject's centroid
/// rather than tiling — which turns "several subjects" into "one subject with an aura".
///
/// **The echoes travel with `progress`.** A static ring set reads as a sticker border; pushing
/// the rings outward as the zoom lands is what makes it read as emanation. The outermost ring
/// fades as it goes, so the loop has somewhere to end rather than snapping back.
///
/// **A `nil` mask returns the frame untouched**, per §1g — the editor leaves the card live on a
/// photo with no subject, so the effect has to degrade to identity rather than draw nothing.
struct SubjectEchoEffect: VisualEffect {
    private let strength: CGFloat
    private let spread: CGFloat
    private let tint: CIColor
    private let mask: CIImage?

    private let compositor = SubjectMaskCompositor()

    /// How many rings. Exposed on the user's call (2026-08-18) — five was too few, and the
    /// ceiling was set from a guess about them merging that the render did not bear out: with
    /// SPREAD open, a dozen rings stay separate. The floor stays at three, where a lone offset
    /// outline still reads as a registration error rather than an effect.
    private let ringCount: Int

    init(intensity: Double = 0.5, spread: Double = 0.5, count: Double = 0.5,
         color: LaserColor = .red, mask: CIImage? = nil) {
        self.strength = max(0, min(1, CGFloat(intensity)))
        self.spread = max(0, min(1, CGFloat(spread)))
        self.ringCount = 3 + Int((max(0, min(1, count)) * 11).rounded())   // 3…14
        let (r, g, b) = color.rgb
        self.tint = CIColor(red: r, green: g, blue: b)
        self.mask = mask
    }

    /// Same effect with a mask attached — the view model has the mask, the factory does not.
    func withMask(_ mask: CIImage?) -> SubjectEchoEffect {
        SubjectEchoEffect(intensity: Double(strength), spread: Double(spread),
                          ringCount: ringCount, tintColor: tint, mask: mask)
    }

    private init(intensity: Double, spread: Double, ringCount: Int, tintColor: CIColor, mask: CIImage?) {
        self.strength = max(0, min(1, CGFloat(intensity)))
        self.spread = max(0, min(1, CGFloat(spread)))
        self.ringCount = ringCount
        self.tint = tintColor
        self.mask = mask
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
        guard let mask,
              extent.width > 1, extent.height > 1,
              let placed = compositor.maskInFrameSpace(mask, frame: image, geometry: geometry)
        else { return image }

        let fade = min(1, progress * 1.4)
        guard fade > 0.01, strength > 0.01 else { return image }

        // The silhouette's edge. `CIMorphologyGradient` is dilation-minus-erosion, so on a
        // binary mask it returns exactly the boundary band — no edge-detection tuning, and it
        // stays crisp under the mask's 1–2px feather (§1g measured that feather; it is
        // antialiasing rather than a soft matte, which is what makes this work).
        let lineWidth = 1 + strength * 3
        let outline = placed
            .applyingFilter("CIMorphologyGradient", parameters: ["inputRadius": lineWidth])
            .cropped(to: extent)

        // Rings scale about the subject's centre, not the frame's, or they slide off a subject
        // standing anywhere but the middle.
        let centre = centroid(of: placed, fallback: CGPoint(x: extent.midX, y: extent.midY))
        let maxStep = 0.06 + spread * 0.34

        var result = image
        for ring in 1...max(1, ringCount) {
            let t = CGFloat(ring) / CGFloat(max(1, ringCount))
            // Travel outward with progress, so the rings emanate rather than sit still.
            let scale = 1 + maxStep * t * fade
            let alpha = strength * (1 - t) * fade * 0.9
            guard alpha > 0.01 else { continue }

            let transform = CGAffineTransform(translationX: -centre.x, y: -centre.y)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y))

            let ringMask = outline.transformed(by: transform).cropped(to: extent)
            let ink = CIImage(color: tint).cropped(to: extent)

            result = ink.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: result,
                kCIInputMaskImageKey: ringMask.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: alpha, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: alpha, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: alpha, w: 0)
                ])
            ])
        }

        // The subject goes back on top, so rings that expanded across it read as coming from
        // behind rather than being painted over its face.
        return compositor.subject(of: image, over: result, mask: mask, geometry: geometry)
    }

    /// The point the rings expand about.
    ///
    /// **This is the mask's extent centre, not a true centroid.** A real centroid would need the
    /// pixels, and reading them means rendering the graph — which `FaceRegionCompositor`'s rule
    /// forbids here, since these effects must stay lazy until the caller's shared context
    /// evaluates them once per frame. The approximation is weakest for a subject standing well
    /// off to one side, where the rings will lean toward frame centre; if that shows up in a
    /// render, the fix is to carry the centroid on the mask from the service, which *does* have
    /// a context, rather than to render here.
    private func centroid(of mask: CIImage, fallback: CGPoint) -> CGPoint {
        let e = mask.extent
        guard e.width.isFinite, e.height.isFinite, e.width > 0, e.height > 0 else { return fallback }
        return CGPoint(x: e.midX, y: e.midY)
    }
}
