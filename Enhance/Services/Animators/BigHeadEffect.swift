import CoreImage

/// Enlarges the subject's **head** — cutting its outline out and growing it on the body, rather
/// than distorting the pixels in place. ROADMAP §2a.
///
/// **Every number that shapes the mask lives in `HeadMaskTuning`**, and the mask is built in
/// exactly one place — `headMask(for:subject:extent:tuning:sizeScale:)` — which HEAD MASK LAB
/// calls with the same inputs to draw its overlay. What the lab shows is what the GIF gets;
/// tune there, then graduate the numbers into `HeadMaskTuning.default`.
///
/// `HeadMaskTuning.default` reproduces the ea96ce3 baseline the user chose (2026-08-20),
/// including its oversized ellipse — that size is part of the approved look, exposed rather
/// than corrected — plus the approved chin cut. The REACH slider scales the tuned ellipse by
/// the same ratio the baseline's `size` parameter did, so every slider position renders as it
/// did before the tuning existed.
///
/// **Known limit, structural:** overlapping faces double-expose, because the pipeline applies
/// the effect once per face and each pass re-blends the previous pass's output. That is the
/// sequential seam recorded on §2a; no mask tuning reaches it.
///
/// **Without a mask it returns the frame untouched.** Per §1g the editor leaves the card live
/// on a photo with no subject, and a live card must never render a broken frame.
struct BigHeadEffect: FaceEffect {
    private let growth: CGFloat
    private let sizeScale: CGFloat
    private let mask: CIImage?
    private let tuning: HeadMaskTuning

    /// - Parameters:
    ///   - intensity: how much the head grows — `1 + intensity² × tuning.growthMax` at full.
    ///   - size: the REACH slider. Scales the tuned ellipse by the baseline's own ratio, so the
    ///     mid-point is exactly the tuned size and the ends match the old slider's range.
    ///   - mask: the subject silhouette from `SubjectSegmentationService`.
    ///   - tuning: mask geometry. Defaults to the live store, so the lab's values apply
    ///     everywhere the effect is built without any call site knowing the lab exists.
    init(intensity: Double = 0.5, size: Double = 0.5, mask: CIImage? = nil,
         tuning: HeadMaskTuning = HeadMaskTuningStore.shared.tuning) {
        self.growth = CGFloat(max(0, min(1, intensity)))
        // The ea96ce3 ellipse at slider position s spanned (2.3 + 1.5s) face-widths; the tuned
        // default is its mid-point, 3.05. Expressing the slider as that same ratio keeps every
        // position rendering exactly as the approved baseline did.
        self.sizeScale = CGFloat((2.3 + 1.5 * max(0, min(1, size))) / 3.05)
        self.mask = mask
        self.tuning = tuning
    }

    /// Same effect with the segmentation mask attached — the view model has it, the factory
    /// does not.
    func withMask(_ mask: CIImage?) -> BigHeadEffect {
        var copy = self
        copy = BigHeadEffect(intensity: Double(growth), size: sliderPosition, mask: mask, tuning: tuning)
        return copy
    }

    /// Inverts `sizeScale` back to the slider position for `withMask`'s reconstruction.
    private var sliderPosition: Double {
        Double((sizeScale * 3.05 - 2.3) / 1.5)
    }

    // MARK: - The mask, in one place

    /// The head mask: ellipse ∩ subject silhouette, faded out below the chin.
    ///
    /// Static and tuning-driven so HEAD MASK LAB can build the identical mask for its overlay.
    /// Returns nil when the geometry is degenerate — callers return the frame unchanged.
    static func headMask(
        for face: DetectedFace,
        subject: CIImage,
        extent: CGRect,
        tuning: HeadMaskTuning,
        sizeScale: CGFloat = 1
    ) -> CIImage? {
        let fullW = face.faceWidth * CGFloat(tuning.ellipseWidth) * sizeScale
        let fullH = face.faceHeight * CGFloat(tuning.ellipseHeight) * sizeScale
        let centre = CGPoint(
            x: face.faceCenter.x,
            y: face.faceCenter.y + face.faceHeight * CGFloat(tuning.centerYOffset)
        )
        let bounds = CGRect(
            x: centre.x - fullW / 2, y: centre.y - fullH / 2, width: fullW, height: fullH
        )
        guard bounds.hasFiniteComponents, bounds.width >= 2, bounds.height >= 2,
              let ellipse = FaceRegionMaskBuilder.ellipticalMask(
                bounds: bounds, feather: CGFloat(max(0.02, min(1, tuning.feather)))
              )
        else { return nil }

        // Intersect: subject AND head-region. Multiply blend on two masks is the intersection,
        // keeping the ellipse's feather while the silhouette stays crisp.
        var headMask = ellipse
            .applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: subject
            ])
            .cropped(to: extent)

        // The chin cut: a vertical ramp, solid above the cut line, gone `chinFade` below it,
        // so the grown copy stops carrying neck and collar.
        let chinY = face.faceCenter.y + face.faceHeight * CGFloat(tuning.chinCutOffset)
        let fade = max(4, face.faceHeight * CGFloat(max(0.02, tuning.chinFade)))
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
        return headMask
    }

    /// The ellipse bounds for `face` under `tuning` — the lab draws them as a guide.
    static func ellipseBounds(
        for face: DetectedFace, tuning: HeadMaskTuning, sizeScale: CGFloat = 1
    ) -> CGRect {
        let fullW = face.faceWidth * CGFloat(tuning.ellipseWidth) * sizeScale
        let fullH = face.faceHeight * CGFloat(tuning.ellipseHeight) * sizeScale
        let centre = CGPoint(
            x: face.faceCenter.x,
            y: face.faceCenter.y + face.faceHeight * CGFloat(tuning.centerYOffset)
        )
        return CGRect(x: centre.x - fullW / 2, y: centre.y - fullH / 2, width: fullW, height: fullH)
    }

    // MARK: - FaceEffect

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let extent = image.extent
        guard let mask, extent.width > 1, extent.height > 1 else { return image }

        // Quadratic, like HANDSOME: most of the growth arrives late, so the head inflates as
        // the zoom lands rather than being large for the whole loop.
        let amount = growth * (progress * progress)
        guard amount > 0.01 else { return image }

        let subjectInFrame = scaled(mask, to: extent)
        guard let headMask = Self.headMask(
            for: face, subject: subjectInFrame, extent: extent,
            tuning: tuning, sizeScale: sizeScale
        ) else { return image }

        let bounds = Self.ellipseBounds(for: face, tuning: tuning, sizeScale: sizeScale)
        // Pin low in the ellipse so the head grows upward and outward off the neck — but not at
        // the very bottom, which sends all growth upward and clips a tightly framed crown.
        let pivot = CGPoint(
            x: face.faceCenter.x,
            y: bounds.minY + bounds.height * CGFloat(tuning.pivotY)
        )
        let scale = 1 + amount * CGFloat(tuning.growthMax)
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
