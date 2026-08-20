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
    private let mask: CIImage?
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
        self.growth = CGFloat(max(0, min(1, intensity)))
        self.coverage = 1.05 + CGFloat(max(0, min(1, size))) * 0.6
        self.mask = mask
    }

    /// Same effect with the segmentation mask attached — the view model has it, the factory does not.
    func withMask(_ mask: CIImage?) -> BigHeadEffect {
        BigHeadEffect(intensity: Double(growth), size: Double((coverage - 1.05) / 0.6), mask: mask)
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let extent = image.extent
        guard let mask, extent.width > 1, extent.height > 1 else { return image }

        // Quadratic, like HANDSOME: most of the growth arrives late, so the head inflates as the
        // zoom lands rather than being large for the whole loop.
        let amount = growth * (progress * progress)
        guard amount > 0.01 else { return image }

        guard let region = regions.region(for: face, coverage: coverage, extent: extent)
        else { return image }

        let subjectInFrame = scaled(mask, to: extent)

        // Intersect: subject AND head-region. Multiply blend on two masks is the intersection;
        // the region supplies the only feather (the jaw/neck seam) while the silhouette edge
        // stays crisp — a crisp edge is what lets stacked heads occlude instead of cross-fade.
        let headMask = region
            .applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: subjectInFrame
            ])
            .cropped(to: extent)

        // Pin low in the head so it grows upward and outward off the neck — but not at the very
        // bottom, which sends all growth upward and clips a tightly framed crown.
        // 0.13 face-heights below centre (y-up): the value the approved renders used, stated
        // directly instead of derived through the ellipse box it used to be coupled to.
        let pivot = CGPoint(
            x: face.faceCenter.x,
            y: face.faceCenter.y - face.faceHeight * 0.13
        )
        // Up to 3×.
        let scale = 1 + amount * 2.0
        let transform = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))

        // Clamped before transforming: a head near the frame edge should extend its border
        // pixels rather than sample transparency and tear a hole as it grows.
        let grownHead = image.clampedToExtent().transformed(by: transform)
        let grownMask = headMask.transformed(by: transform)

        guard grownHead.extent.hasFiniteComponents, grownMask.extent.hasFiniteComponents else {
            return image
        }

        return grownHead
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: grownMask
            ])
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
