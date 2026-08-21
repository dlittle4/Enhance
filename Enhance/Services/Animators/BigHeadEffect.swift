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
/// The head silhouette is the subject mask **intersected with an ellipse around the face**: the
/// mask alone is the whole body, and the ellipse alone is the oval that made ANIME read as a
/// vignette. Multiplied together they give the head's real outline — hair, ears and all — bounded
/// to the head.
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
        self.coverage = 1.15 + CGFloat(max(0, min(1, size))) * 0.75
        self.mask = mask
    }

    /// Same effect with the segmentation mask attached — the view model has it, the factory does not.
    func withMask(_ mask: CIImage?) -> BigHeadEffect {
        BigHeadEffect(intensity: Double(growth), size: Double((coverage - 1.15) / 0.75), mask: mask)
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let extent = image.extent
        guard let mask, extent.width > 1, extent.height > 1 else { return image }

        // Quadratic, like HANDSOME: most of the growth arrives late, so the head inflates as the
        // zoom lands rather than being large for the whole loop.
        let amount = growth * (progress * progress)
        guard amount > 0.01 else { return image }

        let headBounds = CGRect(
            x: face.faceCenter.x - face.faceWidth * coverage,
            y: face.faceCenter.y - face.faceHeight * coverage,
            width: face.faceWidth * coverage * 2,
            height: face.faceHeight * coverage * 2
        )
        guard headBounds.hasFiniteComponents, headBounds.width >= 2, headBounds.height >= 2,
              // A soft ellipse edge, so the head silhouette fades out at the neck instead of
              // ending on a cut line across the throat.
              let ellipse = FaceRegionMaskBuilder.ellipticalMask(bounds: headBounds, feather: 0.35)
        else { return image }

        let subjectInFrame = scaled(mask, to: extent)

        // Intersect: subject AND head-region. Multiply blend on two masks is the intersection,
        // and it keeps the ellipse's feather at the neck while the silhouette stays crisp.
        var headMask = ellipse
            .applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: subjectInFrame
            ])
            .cropped(to: extent)

        // **The chin cut** *(user tweak, 2026-08-20: "mask around the chin a bit better, or
        // maybe the neck")*. The oversized ellipse reaches well below the chin, so the grown
        // copy carried neck and collar with it. Rather than reshaping the ellipse — whose look
        // above the chin is the approved baseline — a vertical ramp fades the region out just
        // under the chin: solid above the face box's bottom edge, gone a third of a face-height
        // below it. Everything above the chin renders exactly as before.
        let chinY = face.faceCenter.y - face.faceHeight * 0.5
        let fade = max(4, face.faceHeight * 0.35)
        if let ramp = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: extent.midX, y: chinY - fade),
            "inputPoint1": CIVector(x: extent.midX, y: chinY),
            "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: 1),
            "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        ])?.outputImage {
            headMask = headMask
                .applyingFilter("CIMultiplyCompositing", parameters: [
                    kCIInputBackgroundImageKey: ramp.cropped(to: extent)
                ])
                .cropped(to: extent)
        }

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
