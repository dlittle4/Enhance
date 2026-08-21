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

    /// One person's silhouette, addressable by where their face sits.
    ///
    /// `normCenter` is the face centre normalized to the mask's own image space (0…1, y-up),
    /// which is what makes the match survive the preview's downsampling: the effect receives
    /// faces already scaled into frame space, normalizes them by the frame, and compares in
    /// unit space — no stored pixel coordinate can go stale. That indirection is the lesson of
    /// the coordinate-trap regression (LEARNINGS 2026-08-19), applied instead of repeated.
    struct PerFaceMask {
        let normCenter: CGPoint
        let mask: CIImage
    }

    private let growth: CGFloat
    private let sizeScale: CGFloat
    private let mask: CIImage?
    private let perFace: [PerFaceMask]
    private let tuning: HeadMaskTuning
    /// Region cache shared across this effect's frames — a class, so it survives the struct
    /// being copied, and per-effect rather than global so concurrent preview and export renders
    /// never share a mutable dictionary.
    private let regionBuilder = HeadRegionBuilder()

    /// - Parameters:
    ///   - intensity: how much the head grows — `1 + intensity² × tuning.growthMax` at full.
    ///   - size: the REACH slider. Scales the tuned ellipse by the baseline's own ratio, so the
    ///     mid-point is exactly the tuned size and the ends match the old slider's range.
    ///   - mask: the subject silhouette from `SubjectSegmentationService`.
    ///   - tuning: mask geometry. Defaults to the live store, so the lab's values apply
    ///     everywhere the effect is built without any call site knowing the lab exists.
    init(intensity: Double = 0.5, size: Double = 0.5, mask: CIImage? = nil,
         perFace: [PerFaceMask] = [],
         tuning: HeadMaskTuning = HeadMaskTuningStore.shared.tuning) {
        self.growth = CGFloat(max(0, min(1, intensity)))
        // The ea96ce3 ellipse at slider position s spanned (2.3 + 1.5s) face-widths; the tuned
        // default is its mid-point, 3.05. Expressing the slider as that same ratio keeps every
        // position rendering exactly as the approved baseline did.
        self.sizeScale = CGFloat((2.3 + 1.5 * max(0, min(1, size))) / 3.05)
        self.mask = mask
        self.perFace = perFace
        self.tuning = tuning
    }

    /// Same effect with the segmentation mask attached — the view model has it, the factory
    /// does not.
    func withMask(_ mask: CIImage?, perFace: [PerFaceMask] = []) -> BigHeadEffect {
        BigHeadEffect(intensity: Double(growth), size: sliderPosition, mask: mask,
                      perFace: perFace, tuning: tuning)
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
        sizeScale: CGFloat = 1,
        regionBuilder: HeadRegionBuilder? = nil
    ) -> CIImage? {
        // The jaw-region approach (user setting, 2026-08-20): bound the head below by the traced
        // contour instead of ellipse + chin ramp. Gated on a real trace — animals and estimated
        // faces carry synthetic 5-point contours and **fall through to the tuned ellipse path
        // below**, not to a private duplicate: an earlier version passed the builder its own
        // hardcoded coverage here, which silently ignored the WIDTH/HEIGHT sliders and REACH for
        // exactly the faces most likely to need them.
        if tuning.useJawRegion,
           face.landmarkQuality == .precise,
           face.faceContourPoints.count >= HeadRegionBuilder.minContourPoints,
           let builder = regionBuilder,
           let region = builder.region(
               for: face, coverage: 1.3, extent: extent,
               // REACH scales the jaw region exactly as it scales the ellipse, so the slider
               // keeps one meaning across modes. Yaw shifts the side bound toward the back of
               // the head — the skull a profile's symmetric bound cannot reach.
               jawDrop: CGFloat(tuning.jawDrop), jawFeather: CGFloat(tuning.jawFeather),
               jawHalfWidth: CGFloat(tuning.jawWidth) * sizeScale,
               xShift: yawShift(for: face, tuning: tuning)
           ) {
            // The jaw cut *is* the chin cut here — no ramp on top, or the head loses its chin
            // to a double fade.
            return region
                .applyingFilter("CIMultiplyCompositing", parameters: [
                    kCIInputBackgroundImageKey: subject
                ])
                .cropped(to: extent)
        }
        let fullW = face.faceWidth * CGFloat(tuning.ellipseWidth) * sizeScale
        let fullH = face.faceHeight * CGFloat(tuning.ellipseHeight) * sizeScale
        let centre = CGPoint(
            // Yaw pushes the ellipse toward the back of a turned head — the skull extends
            // behind the face, and a centred ellipse can only reach it by growing everywhere.
            x: face.faceCenter.x + yawShift(for: face, tuning: tuning),
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

        // FOLLOW POSE: rotate the whole ellipse+ramp geometry with the head's roll, about the
        // face centre. Only here — the traced jaw needs no help, its points already tilt with
        // the face. The subject intersection happens before this rotation, which is wrong in
        // principle (the silhouette should not rotate) — in practice the silhouette is
        // rotation-symmetric enough near the head that re-intersecting is not worth a second
        // multiply; judge it in the lab before promoting.
        if tuning.followPose, abs(face.roll) > 0.02 {
            let c = face.faceCenter
            let rotate = CGAffineTransform(translationX: -c.x, y: -c.y)
                .concatenating(CGAffineTransform(rotationAngle: CGFloat(face.roll)))
                .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
            headMask = headMask.transformed(by: rotate).cropped(to: extent)
        }
        return headMask
    }

    /// The sideways push yaw gives the mask, in frame points. Sign follows Vision's convention
    /// (positive yaw = head turned toward its left); **if the lab shows the shift landing on the
    /// face side rather than the skull side, negate here once** — the overlay makes the check a
    /// two-second look.
    private static func yawShift(for face: DetectedFace, tuning: HeadMaskTuning) -> CGFloat {
        guard tuning.followPose else { return 0 }
        let normalised = max(-1, min(1, face.yaw / (Double.pi / 2)))
        return CGFloat(normalised * tuning.yawShift) * face.faceWidth
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

        // Person-mask approach: this face's own silhouette when one is available, matched in
        // normalized space; the union otherwise. Off by default — the shared union is the
        // approved baseline.
        let chosen: CIImage
        if tuning.usePersonMasks,
           let nearest = nearestPerFaceMask(to: face, extent: extent) {
            chosen = nearest
        } else {
            chosen = mask
        }
        let subjectInFrame = scaled(chosen, to: extent)
        guard let headMask = Self.headMask(
            for: face, subject: subjectInFrame, extent: extent,
            tuning: tuning, sizeScale: sizeScale, regionBuilder: regionBuilder
        ) else { return image }

        // Pin low in the head so it grows upward and outward off the neck — but not at the
        // very bottom, which sends all growth upward and clips a tightly framed crown.
        // **Each mode pivots on its own geometry.** The ellipse path pivots in the ellipse's
        // bounds; the jaw path pivots just under its traced cut — an earlier version pivoted the
        // jaw mode on the ellipse bounds, which meant the "inert" ellipse sliders silently moved
        // where a jaw-mode head grew from.
        let pivot: CGPoint
        if tuning.useJawRegion,
           face.landmarkQuality == .precise,
           face.faceContourPoints.count >= HeadRegionBuilder.minContourPoints,
           let jawLowY = face.faceContourPoints.map(\.y).min() {
            let cut = jawLowY - face.faceHeight * CGFloat(tuning.jawDrop)
            let headSpan = face.faceHeight * 2.4
            pivot = CGPoint(x: face.faceCenter.x, y: cut + headSpan * CGFloat(tuning.pivotY) - headSpan * 0.3)
        } else {
            let bounds = Self.ellipseBounds(for: face, tuning: tuning, sizeScale: sizeScale)
            pivot = CGPoint(
                x: face.faceCenter.x,
                y: bounds.minY + bounds.height * CGFloat(tuning.pivotY)
            )
        }
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

    /// The stored mask whose owner's face sits closest to `face`, compared in unit space so the
    /// match is immune to the preview's downsampling. Rejects matches further than half the
    /// frame apart — a mismatch that gross means the lists disagree, and the union is safer.
    private func nearestPerFaceMask(to face: DetectedFace, extent: CGRect) -> CIImage? {
        guard !perFace.isEmpty, extent.width > 0, extent.height > 0 else { return nil }
        let target = CGPoint(
            x: (face.faceCenter.x - extent.origin.x) / extent.width,
            y: (face.faceCenter.y - extent.origin.y) / extent.height
        )
        let best = perFace.min {
            hypot($0.normCenter.x - target.x, $0.normCenter.y - target.y) <
            hypot($1.normCenter.x - target.x, $1.normCenter.y - target.y)
        }
        guard let best,
              hypot(best.normCenter.x - target.x, best.normCenter.y - target.y) < 0.5
        else { return nil }
        return best.mask
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
