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
/// The head silhouette is the subject mask **intersected with a head region**. The mask alone is
/// the whole body; the region decides where the head stops. Two sources for that region, in
/// order of preference:
///
/// 1. **Vision's traced face contour**, where landmarks are available. Note the contour is *not*
///    a head outline — it runs ear-to-ear around the jaw with nothing above the brow — so it is
///    used only to place the chin cut and the side walls, and the mask supplies crown and hair.
/// 2. **An ellipse**, where no contour exists. That is the CIDetector fallback path and every
///    animal, whose contour comes from body-pose joints rather than a face.
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

    /// - Parameters:
    ///   - intensity: how much the head grows — up to +55% at full, a ceiling set by what keeps
    ///     the body visible underneath rather than by taste.
    ///   - size: how much around the face the head ellipse covers. Larger catches tall hair and
    ///     ears; too large starts taking shoulder with it.
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

        // `faceWidth`/`faceHeight` are full extents, not radii — `HandsomeEffect` halves them
        // for exactly this reason. An earlier version used them as half-extents, which made the
        // ellipse up to 3.8× the face: it enclosed the whole animal, so the effect scaled the
        // entire subject instead of its head *(user-reported: "only making the head larger")*.
        let halfW = face.faceWidth * 0.5 * coverage
        let halfH = face.faceHeight * 0.5 * coverage
        let headBounds = CGRect(
            x: face.faceCenter.x - halfW,
            // Biased upward: a face box is centred on the face, while a head runs from the chin
            // to above the crown, so an ellipse centred on the face clips hair and ears while
            // reaching down into the chest.
            y: face.faceCenter.y - halfH * 0.85,
            width: halfW * 2,
            height: halfH * 2.2
        )
        guard headBounds.hasFiniteComponents, headBounds.width >= 2, headBounds.height >= 2
        else { return image }

        let subjectInFrame = scaled(mask, to: extent)

        // The region that says "this part of the subject is head". Prefer the traced contour;
        // fall back to the ellipse where Vision gave none.
        let region = contourRegion(for: face, extent: extent)
            ?? FaceRegionMaskBuilder.ellipticalMask(bounds: headBounds, feather: 0.35)
        guard let region else { return image }

        // Intersect: subject AND head-region. Multiply blend on two masks is the intersection,
        // so the silhouette stays crisp — hair, ears and all — while the region decides where
        // the head stops.
        let headMask = region
            .applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: subjectInFrame
            ])
            .cropped(to: extent)

        // Pin the bottom of the head so it grows upward and outward off the neck.
        // 0.30, not 0.18. Anchoring at the very bottom sent almost all the growth upward, and
        // on a subject whose head already reaches the top of the frame that clipped the ears
        // off — seen at full intensity in the first render. A slightly higher pivot still keeps
        // the head on the neck while spending some of the growth sideways.
        let pivot = CGPoint(x: face.faceCenter.x, y: headBounds.minY + headBounds.height * 0.30)
        // Max 1.55×. The first render went to 1.85× and simply overflowed the frame — the joke
        // needs the body still visible underneath, so the ceiling is set by what keeps it there.
        let scale = 1 + amount * 0.55
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

    /// A head region built from Vision's traced face contour, or `nil` when there is none.
    ///
    /// **The contour alone is not a head outline** — it runs ear-to-ear around the jaw and has no
    /// points above the brow, because there are no facial landmarks up there. Filling it would
    /// cut the head off at the eyebrows, which is worse than the ellipse it replaces.
    ///
    /// What it *is* good for is the one thing the segmentation mask cannot tell you: **where the
    /// head stops and the neck starts.** So this does not trace a head at all. It builds an open
    /// region — unbounded above, cut at the chin, walled either side of the face — and lets the
    /// subject mask supply the actual outline. Crown and hair come from the mask; the jawline
    /// comes from the contour.
    ///
    /// Three linear gradients multiplied together, all lazy: no render, no context.
    private func contourRegion(for face: DetectedFace, extent: CGRect) -> CIImage? {
        let points = face.faceContourPoints
        // **12, not 5.** Vision's real `faceContour` returns dozens of points along the jaw;
        // a handful means the detection fell back and the "contour" is a few landmarks that do
        // not describe a jawline at all. The corpus caught this: the person in `showcase-3` is
        // facing away, so Vision returned 5 points with `.estimated` quality, and a 5-point
        // guard let that through to place a chin cut from noise. Requiring a real contour sends
        // weak detections to the ellipse, which is the honest answer for a head Vision cannot see.
        guard points.count >= 12, face.landmarkQuality != .estimated else { return nil }

        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let chinY = ys.min(),
              minX.isFinite, maxX.isFinite, chinY.isFinite, maxX > minX else { return nil }

        // Ears and hair sit outside the contour, which only traces skin.
        let pad = (maxX - minX) * 0.35
        let left = minX - pad
        let right = maxX + pad
        // Feather the chin cut over a fraction of the face's own width, so it scales with the
        // subject instead of being a fixed pixel count that is invisible on a large face and a
        // hard line on a small one.
        let feather = max(2, (maxX - minX) * 0.12)

        // White above the chin, fading below it.
        guard let above = linearGradient(
            from: CGPoint(x: extent.midX, y: chinY - feather), fromWhite: false,
            to: CGPoint(x: extent.midX, y: chinY + feather), toWhite: true
        ),
        // White right of the left wall, and left of the right wall.
        let insideLeft = linearGradient(
            from: CGPoint(x: left - feather, y: extent.midY), fromWhite: false,
            to: CGPoint(x: left + feather, y: extent.midY), toWhite: true
        ),
        let insideRight = linearGradient(
            from: CGPoint(x: right - feather, y: extent.midY), fromWhite: true,
            to: CGPoint(x: right + feather, y: extent.midY), toWhite: false
        ) else { return nil }

        return above
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: insideLeft])
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: insideRight])
            .cropped(to: extent)
    }

    private func linearGradient(
        from p0: CGPoint, fromWhite: Bool, to p1: CGPoint, toWhite: Bool
    ) -> CIImage? {
        let black = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        let white = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        return CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: p0.x, y: p0.y),
            "inputPoint1": CIVector(x: p1.x, y: p1.y),
            "inputColor0": fromWhite ? white : black,
            "inputColor1": toWhite ? white : black
        ])?.outputImage
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
