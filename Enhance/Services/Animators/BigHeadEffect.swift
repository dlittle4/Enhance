import CoreImage

/// Enlarges the subject's **head** — cutting its outline out and growing it on the body, rather
/// than distorting the pixels in place. ROADMAP §2a.
///
/// **This is deliberately the simple version.** The head region is an ellipse around the face,
/// intersected with the shared subject mask; heads are grown one face at a time by the
/// pipeline's sequential pass. A far more ambitious version — per-person instance masks, a
/// traced-jaw region, a layered occlusion pass — was built, rendered, and **parked on the
/// user's call (2026-08-20) after failing visual review twice**; §2a records what it got right
/// and where it broke. Do not re-grow this file toward it without reading that entry: the
/// person-mask *infrastructure* survives in `SubjectSegmentationService` and
/// `HeadRegionBuilder` (kept compiled, unreferenced, per the retired-effects convention), so a
/// revival is wiring, not rebuilding.
///
/// Three fixes from that work are kept here because they are corrections, not look changes:
///
/// - **Ellipse half-extents are halved** — `faceWidth × coverage` is the full width. Using it
///   as the half-extent made the ellipse enclose whole animals and scaled the entire subject.
/// - **Growth reaches 3×** (user's call): the old 1.55× ceiling was set against a tightly
///   framed cat and was invisible on real photos, where a head is a few percent of the frame.
/// - **The mask is flattened to opaque grayscale** (`settingAlphaOne`) — the ellipse gradient
///   feathers via alpha, and an alpha-carried mask silently defeats colour filters and blends
///   (LEARNINGS 2026-08-20).
///
/// **Without a mask it returns the frame untouched.** Per §1g the editor leaves the card live
/// on a photo with no subject, and a live card must never render a broken frame.
struct BigHeadEffect: FaceEffect {
    private let growth: CGFloat
    private let coverage: CGFloat
    private let mask: CIImage?

    /// - Parameters:
    ///   - intensity: how much the head grows — up to 3× at full. Growth only: shrinking
    ///     exposes the area behind the head, which is the reveal-hole problem PARALLAX is
    ///     blocked on.
    ///   - size: how much around the face the ellipse covers. Larger catches tall hair and
    ///     ears; too large starts taking shoulder with it.
    init(intensity: Double = 0.5, size: Double = 0.5, mask: CIImage? = nil) {
        self.growth = CGFloat(max(0, min(1, intensity)))
        self.coverage = 1.05 + CGFloat(max(0, min(1, size))) * 0.6
        self.mask = mask
    }

    /// Same effect with the segmentation mask attached — the view model has it, the factory
    /// does not.
    func withMask(_ mask: CIImage?) -> BigHeadEffect {
        BigHeadEffect(intensity: Double(growth), size: Double((coverage - 1.05) / 0.6), mask: mask)
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let extent = image.extent
        guard let mask, extent.width > 1, extent.height > 1 else { return image }

        // Quadratic, like HANDSOME: most of the growth arrives late, so the head inflates as
        // the zoom lands rather than being large for the whole loop.
        let amount = growth * (progress * progress)
        guard amount > 0.01 else { return image }

        let halfW = face.faceWidth * 0.5 * coverage
        let halfH = face.faceHeight * 0.5 * coverage
        let headBounds = CGRect(
            x: face.faceCenter.x - halfW,
            // Biased upward: a face box is centred on the face, while a head runs from the
            // chin to above the crown — centred on the face it clips hair while dipping into
            // the chest.
            y: face.faceCenter.y - halfH * 0.85,
            width: halfW * 2,
            height: halfH * 2.2
        )
        guard headBounds.hasFiniteComponents, headBounds.width >= 2, headBounds.height >= 2,
              // A soft ellipse edge, so the head silhouette fades out at the neck instead of
              // ending on a cut line across the throat. Flattened to opaque grayscale — see
              // the doc note; the alpha-carried version is a recorded trap.
              let ellipse = FaceRegionMaskBuilder.ellipticalMask(bounds: headBounds, feather: 0.35)?
                  .cropped(to: extent)
                  .settingAlphaOne(in: extent)
        else { return image }

        let subjectInFrame = scaled(mask, to: extent)

        // Intersect: subject AND head-region. Multiply blend on two masks is the intersection,
        // and it keeps the ellipse's feather at the neck while the silhouette stays crisp.
        let headMask = ellipse
            .applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: subjectInFrame
            ])
            .cropped(to: extent)

        // Pin low in the head so it grows upward and outward off the neck — but not at the
        // very bottom, which sends all growth upward and clips a tightly framed crown.
        let pivot = CGPoint(x: face.faceCenter.x, y: headBounds.minY + headBounds.height * 0.30)
        // Up to 3×.
        let scale = 1 + amount * 2.0
        let transform = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))

        // Cut first, then transform, then source-over: the mask becomes the cutout's alpha
        // before the transform, so the composite is plain occlusion and nothing samples a mask
        // at blend time.
        let cutout = image.clampedToExtent()
            .cropped(to: extent)
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: headMask
            ])
        let grownHead = cutout.transformed(by: transform)
        guard grownHead.extent.hasFiniteComponents else { return image }

        return grownHead
            .composited(over: image)
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
