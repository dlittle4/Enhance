import CoreImage

/// Enlarges the subject's **head** — cutting its outline out and growing it on the body, rather
/// than distorting the pixels in place. ROADMAP §2a.
///
/// **This replaces a `CIBumpDistortion` version, on the user's call (2026-08-18): "big head just
/// seems like a slightly different fisheye".** That was accurate and it is worth recording why.
/// A bump warps a disc of the image outward, so the head grows *and* everything near it smears —
/// the ears bend, the background curves, and the result is a lens artefact rather than a bigger
/// head. Scaling a cutout keeps the head's own shape intact and lets it occlude the body, which
/// is what "grown on the individual's body" actually means. The distortion approach is not
/// tunable into this one; it is the wrong mechanism, not the wrong constants.
///
/// The head silhouette is the subject mask **intersected with a head region** from
/// `HeadRegionBuilder`: the mask alone is the whole body; the region says where the head stops.
/// On a precise human face the region is bounded below by the *traced jaw* and open everywhere
/// else — crown, hats and hair come from the mask, which is the only thing that knows where a
/// cap ends. Animals and estimated faces get the corrected ellipse. Person separation is the
/// mask's job alone; the region has no side walls, and ROADMAP §2a records why it never will.
///
/// **It scales about a point low in the head, not its centre.** Growing about the centre lifts
/// the head off the neck; anchoring low keeps it sitting on the body while the crown rises.
/// Anchoring at the *very* bottom is also wrong — it sends all the growth upward and clips the
/// ears on a tightly framed subject, which the first render did.
///
/// **Without a mask it returns the frame untouched.** Per §1g the editor leaves the card live on
/// a photo with no subject, and a fallback that reverted to the bump would be shipping the look
/// the user rejected.
struct BigHeadEffect: FaceEffect {
    private let growth: CGFloat
    private let coverage: CGFloat
    /// One mask per face, **positionally aligned** with the faces handed to the batch `apply`
    /// — `DetectedFace.scaled()` assigns a fresh UUID, so position is the only correlation that
    /// survives the callers' coordinate scaling. A single entry is the shared/union mask and
    /// serves every face. Masks are safe to store where faces were not (§2a's coordinate trap):
    /// `scaled(_:to:)` re-expresses them by extent ratio, so they survive the 650px preview and
    /// the GIF downscale alike.
    private let masks: [CIImage?]
    /// Reference type, so the per-face region cache survives this struct being copied — the
    /// effect is rebuilt per preview update but reused across a GIF's frames.
    private let regions = HeadRegionBuilder()

    /// - Parameters:
    ///   - intensity: how much the head grows — up to 3× at full (user's call; the old 1.55×
    ///     ceiling was set against a tightly framed cat and was invisible on real photos where
    ///     a head is a few percent of the frame). Growth only — shrinking exposes the area
    ///     behind the head, which is the reveal-hole problem PARALLAX is blocked on.
    ///   - size: how much around the face the *ellipse fallback* covers. The traced-jaw path
    ///     bounds itself and ignores it.
    init(intensity: Double = 0.5, size: Double = 0.5, mask: CIImage? = nil) {
        self.init(intensity: intensity, size: size, masks: mask.map { [$0] } ?? [])
    }

    init(intensity: Double = 0.5, size: Double = 0.5, masks: [CIImage?]) {
        self.growth = CGFloat(max(0, min(1, intensity)))
        self.coverage = 1.05 + CGFloat(max(0, min(1, size))) * 0.6
        self.masks = masks
    }

    /// Same effect with the segmentation masks attached — the view model has them, the factory
    /// does not. Carries the stored values directly rather than reverse-mapping `coverage`
    /// through the public init, which proved fragile when the coverage maths changed.
    func withMasks(_ masks: [CIImage?]) -> BigHeadEffect {
        BigHeadEffect(growth: growth, coverage: coverage, masks: masks)
    }

    private init(growth: CGFloat, coverage: CGFloat, masks: [CIImage?]) {
        self.growth = growth
        self.coverage = coverage
        self.masks = masks
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, faces: [face], progress: progress, frameIndex: frameIndex)
    }

    /// **The layered pass.** Every head is cut from the *original* frame and composited onto
    /// the accumulator back-to-front — widest face last, since a face is wider the nearer it is
    /// to the camera, so the nearest head lands on top and overlapping heads occlude. The
    /// sequential default was the recorded smear: its second pass re-scaled pixels that already
    /// contained the first enlarged head.
    func apply(to image: CIImage, faces: [DetectedFace], progress: CGFloat, frameIndex: Int) -> CIImage {
        guard !faces.isEmpty, image.extent.width > 1, image.extent.height > 1 else { return image }

        // Quadratic, like HANDSOME: most of the growth arrives late, so the head inflates as
        // the zoom lands rather than being large for the whole loop.
        let amount = growth * (progress * progress)
        guard amount > 0.01 else { return image }

        let ordered = faces.enumerated()
            .map { (face: $0.element, mask: mask(at: $0.offset)) }
            .sorted { $0.face.faceWidth < $1.face.faceWidth }

        var result = image
        for entry in ordered {
            result = grow(head: entry.face, mask: entry.mask, from: image, over: result, amount: amount)
        }
        return result
    }

    /// The mask for the face at `index`: positional when the array is per-face, the single
    /// entry when it is the shared/union mask, nil past the end (that face degrades to
    /// identity, per §1g — never a broken frame).
    private func mask(at index: Int) -> CIImage? {
        if masks.count == 1 { return masks[0] }
        guard index >= 0, index < masks.count else { return nil }
        return masks[index]
    }

    /// One head, cut from `image`, composited over `canvas`.
    private func grow(
        head face: DetectedFace, mask: CIImage?, from image: CIImage, over canvas: CIImage,
        amount: CGFloat
    ) -> CIImage {
        let extent = image.extent
        guard let mask else { return canvas }

        guard let region = regions.region(for: face, coverage: coverage, extent: extent)
        else { return canvas }

        let subjectInFrame = scaled(mask, to: extent)

        // Intersect: subject AND head-region. Multiply blend on two masks is the intersection;
        // the region supplies the only feather (the jaw/neck seam) while the silhouette edge
        // stays crisp — a crisp edge is what lets stacked heads occlude instead of cross-fade.
        // **Steep contrast after the intersect, and it is required, not cosmetic.** Mid-values
        // in the mask render as translucency, and translucent heads cross-fade where they
        // overlap instead of occluding — measured as a constant partial show-through of the
        // under-head. The steep curve collapses the region's feather to a narrow seam band
        // (the jaw/neck fade survives, ~thinner) while the working range becomes effectively
        // binary, which is what makes stacked heads occlude. Note this only works because the
        // region masks are opaque grayscale — see the `settingAlphaOne` note in
        // `HeadRegionBuilder`: on an alpha-carried mask, colour filters silently do nothing.
        let headMask = region
            .applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: subjectInFrame
            ])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 8.0,
                kCIInputBrightnessKey: 0.0
            ])
            .applyingFilter("CIColorClamp")
            .cropped(to: extent)

        // Pin low in the head so it grows upward and outward off the neck — but not at the very
        // bottom, which sends all growth upward and clips a tightly framed crown.
        // 0.13 face-heights below centre (y-up): the value the approved renders used, stated
        // directly instead of derived through the ellipse box it used to be coupled to.
        let pivot = CGPoint(
            x: face.faceCenter.x,
            y: face.faceCenter.y - face.faceHeight * 0.13
        )
        // Up to 3×. `amount` already carries the progress ramp from the batch entry point.
        let scale = 1 + amount * 2.0
        let transform = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))

        // **Cut first, then transform, then source-over.** The mask becomes the cutout's alpha
        // *before* the transform, so the enlargement scales one premultiplied image and the
        // composite is plain source-over — occlusion by alpha. The earlier shape (transform the
        // head and the mask separately, `CIBlendWithMask` at the end) blended at a uniform ~0.86
        // even where the mask image sampled 1.0 — measured with probes, cause unidentified, and
        // sidestepped rather than fought: with the alpha baked in before the transform there is
        // no mask to mis-sample at blend time.
        //
        // Clamped before cutting: a head near the frame edge extends its border pixels rather
        // than sampling transparency and tearing a hole as it grows.
        let cutout = image.clampedToExtent()
            .cropped(to: extent)
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: headMask
            ])
        let grownHead = cutout.transformed(by: transform)

        guard grownHead.extent.hasFiniteComponents else { return canvas }

        // Source-over the accumulating canvas — but always cut from the original `image`,
        // which is what stops overlapping heads smearing into each other.
        return grownHead
            .composited(over: canvas)
            .cropped(to: extent)
    }

    /// Face effects run in source space, so this is normally a no-op — it exists because the
    /// pipeline can normalise orientation before drawing, changing pixel dimensions without
    /// changing what the mask means.
    private func scaled(_ mask: CIImage, to extent: CGRect) -> CIImage {
        guard mask.extent.width > 0, mask.extent.height > 0,
              mask.extent.size != extent.size else { return mask }
        return mask
            .transformed(by: CGAffineTransform(
                scaleX: extent.width / mask.extent.width,
                y: extent.height / mask.extent.height
            ))
            .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
    }
}
