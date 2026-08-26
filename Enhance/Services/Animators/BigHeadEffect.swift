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
/// than corrected — plus the approved chin cut. Legacy masks still use the second slider to
/// scale that ellipse by the baseline ratio. Semantic V2 already supplies the exact head outline,
/// so its second slider instead controls a small, coverage-safe vertical position adjustment.
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
        /// Stable identity survives `DetectedFace.scaled`, so semantic masks never need to
        /// guess their owner from proximity. Nil keeps legacy test/stub call sites compatible.
        var ownerID: UUID? = nil
        let normCenter: CGPoint
        let mask: CIImage
        /// AUTO FIT's scan results for this face (`HeadGeometryScanner`), normalized to the
        /// mask's image space like `normCenter`, and nil when the scan found nothing — the
        /// tuned sliders then apply unchanged.
        var neckNormY: Double? = nil
        var crownNormY: Double? = nil
        /// True when `mask` is already a semantic head-only matte. Legacy entries are person
        /// silhouettes and still need the ellipse/jaw region applied by `headMask`.
        var isSemanticHeadMask: Bool = false
    }

    private let growth: CGFloat
    /// Raw second-slider position. In semantic V2, 0.5 is centred, 0 moves down and 1 moves up.
    /// Keeping the raw value also avoids reconstructing it from `sizeScale` when a mask is added.
    private let secondaryPosition: CGFloat
    private let sizeScale: CGFloat
    private let mask: CIImage?
    private let perFace: [PerFaceMask]
    /// Semantic V2's safe-overlap policy can explicitly leave ambiguous faces unchanged.
    private let suppressedFaceIDs: Set<UUID>
    /// Enables V2's face-centred growth and source-footprint replacement. V2-only so the
    /// approved legacy compositor and V1 comparison remain byte-for-byte available in the lab.
    private let collisionSafe: Bool
    private let tuning: HeadMaskTuning
    /// Region cache shared across this effect's frames — a class, so it survives the struct
    /// being copied, and per-effect rather than global so concurrent preview and export renders
    /// never share a mutable dictionary.
    private let regionBuilder = HeadRegionBuilder()

    /// - Parameters:
    ///   - intensity: how much the head grows — `1 + intensity² × tuning.growthMax` at full.
    ///   - size: the second slider. Semantic V2 treats it as VERTICAL POSITION; legacy masks retain
    ///     REACH so comparison renders remain unchanged. The midpoint is neutral in both modes.
    ///   - mask: the subject silhouette from `SubjectSegmentationService`.
    ///   - tuning: mask geometry. Defaults to the live store, so the lab's values apply
    ///     everywhere the effect is built without any call site knowing the lab exists.
    init(intensity: Double = 0.5, size: Double = 0.5, mask: CIImage? = nil,
         perFace: [PerFaceMask] = [],
         suppressedFaceIDs: Set<UUID> = [],
         collisionSafe: Bool = false,
         tuning: HeadMaskTuning = HeadMaskTuningStore.shared.tuning) {
        self.growth = CGFloat(max(0, min(1, intensity)))
        self.secondaryPosition = CGFloat(max(0, min(1, size)))
        // The ea96ce3 ellipse at slider position s spanned (2.3 + 1.5s) face-widths; the tuned
        // default is its mid-point, 3.05. Expressing the slider as that same ratio keeps every
        // position rendering exactly as the approved baseline did.
        self.sizeScale = CGFloat((2.3 + 1.5 * max(0, min(1, size))) / 3.05)
        self.mask = mask
        self.perFace = perFace
        self.suppressedFaceIDs = suppressedFaceIDs
        self.collisionSafe = collisionSafe
        self.tuning = tuning
    }

    /// Same effect with the segmentation mask attached — the view model has it, the factory
    /// does not.
    func withMask(
        _ mask: CIImage?, perFace: [PerFaceMask] = [], forceStackedPass: Bool = false,
        suppressedFaceIDs: Set<UUID> = [], collisionSafe: Bool = false
    ) -> BigHeadEffect {
        var appliedTuning = tuning
        if forceStackedPass { appliedTuning.stackedPass = true }
        return BigHeadEffect(intensity: Double(growth), size: Double(secondaryPosition), mask: mask,
                             perFace: perFace, suppressedFaceIDs: suppressedFaceIDs,
                             collisionSafe: collisionSafe,
                             tuning: appliedTuning)
    }

    /// Semantic V2's position transform. Travel is proportional to the enlargement, so there is
    /// no disconnected slide when INTENSITY is zero and no fixed-pixel jump between a close-up
    /// and a group. A scaled face box gains `(scale - 1) * height / 2` on each vertical edge;
    /// spending only 30% of that same quantity's full-height equivalent leaves 40% of the new
    /// margin covering the original face even at either slider extreme.
    static func semanticGrowthTransform(
        faceCenter: CGPoint, faceHeight: CGFloat, requestedScale: CGFloat, position: CGFloat
    ) -> CGAffineTransform {
        let clampedScale = max(1, requestedScale)
        let clampedPosition = max(0, min(1, position))
        let bias = (clampedPosition - 0.5) * 2
        let yOffset = bias * (clampedScale - 1) * max(0, faceHeight) * 0.30
        return CGAffineTransform(translationX: -faceCenter.x, y: -faceCenter.y)
            .concatenating(CGAffineTransform(scaleX: clampedScale, y: clampedScale))
            .concatenating(CGAffineTransform(translationX: faceCenter.x, y: faceCenter.y))
            .concatenating(CGAffineTransform(translationX: 0, y: yOffset))
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
        regionBuilder: HeadRegionBuilder? = nil,
        neckY: CGFloat? = nil,
        crownY: CGFloat? = nil
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
            guard tuning.useSilhouette else { return region }
            return region
                .applyingFilter("CIMultiplyCompositing", parameters: [
                    kCIInputBackgroundImageKey: subject
                ])
                .cropped(to: extent)
        }
        var fullW = face.faceWidth * CGFloat(tuning.ellipseWidth) * sizeScale
        var fullH = face.faceHeight * CGFloat(tuning.ellipseHeight) * sizeScale
        var derivedCentreY: CGFloat? = nil
        // AUTO FIT: the photo told us where this head starts and ends — size the ellipse from
        // neck to crown (padded a little past each) instead of from the sliders.
        if tuning.autoFit, let neckY, let crownY, crownY > neckY {
            let span = crownY - neckY
            fullH = span * 1.25
            fullW = min(fullW, span * 1.1)
            derivedCentreY = (neckY + crownY) / 2
        }
        let centre = CGPoint(
            // Yaw pushes the ellipse toward the back of a turned head — the skull extends
            // behind the face, and a centred ellipse can only reach it by growing everywhere.
            x: face.faceCenter.x + yawShift(for: face, tuning: tuning),
            y: derivedCentreY ?? (face.faceCenter.y + face.faceHeight * CGFloat(tuning.centerYOffset))
        )
        let bounds = CGRect(
            x: centre.x - fullW / 2, y: centre.y - fullH / 2, width: fullW, height: fullH
        )
        guard bounds.hasFiniteComponents, bounds.width >= 2, bounds.height >= 2,
              let ellipse = FaceRegionMaskBuilder.ellipticalMask(
                bounds: bounds, feather: CGFloat(max(0.02, min(1, tuning.feather)))
              )
        else { return nil }

        // Build and pose the geometric prior first. The source silhouette belongs to the photo,
        // so rotating an already-intersected mask moves real hair/skin away from those pixels.
        var regionMask = ellipse.cropped(to: extent)

        // The chin cut: a vertical ramp, solid above the cut line, gone `chinFade` below it,
        // so the grown copy stops carrying neck and collar.
        let chinY = (tuning.autoFit ? neckY : nil)
            ?? (face.faceCenter.y + face.faceHeight * CGFloat(tuning.chinCutOffset))
        let fade = max(4, face.faceHeight * CGFloat(max(0.02, tuning.chinFade)))
        if let ramp = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: extent.midX, y: chinY - fade),
            "inputPoint1": CIVector(x: extent.midX, y: chinY),
            "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: 1),
            "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        ])?.outputImage {
            regionMask = regionMask
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
            regionMask = regionMask.transformed(by: rotate).cropped(to: extent)
        }

        // Intersect only after all geometric transforms. With SILHOUETTE off the geometric
        // region alone remains the classic background-carrying big-head cutout.
        guard tuning.useSilhouette else { return regionMask }
        return regionMask
            .applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: subject
            ])
            .cropped(to: extent)
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
        grow(
            face: face, from: image, over: image, progress: progress,
            hardEdge: false, denseGroup: false
        )
    }

    /// STACKED PASS *(user's call, 2026-08-20: "make sure faces won't blur into each other")*.
    ///
    /// The sequential default re-blends each face over the previous face's output, so two
    /// overlapping grown heads cross-fade into translucent ghosts — the recorded smear, and a
    /// mask cannot reach it because it is a property of the pass structure. With the toggle on,
    /// every head is cut from the **original** frame and composited back-to-front — widest face
    /// last, since a wider face is nearer the camera — with the mask edge hardened so the front
    /// head **occludes** the back one instead of blending with it. Off (the default), behaviour
    /// is byte-identical to the sequential loop.
    func apply(to image: CIImage, faces: [DetectedFace], progress: CGFloat, frameIndex: Int) -> CIImage {
        guard tuning.stackedPass, faces.count > 1 else {
            var result = image
            for face in faces {
                result = apply(to: result, face: face, progress: progress, frameIndex: frameIndex)
            }
            return result
        }
        let ordered = faces.sorted { $0.faceWidth < $1.faceWidth }
        let widths = faces.map(\.faceWidth).sorted()
        let medianWidth = widths[widths.count / 2]
        let denseGroup = faces.count > 3 && medianWidth / max(1, image.extent.width) < 0.10
        var canvas = image
        for face in ordered {
            canvas = grow(
                face: face, from: image, over: canvas, progress: progress,
                hardEdge: true, denseGroup: denseGroup
            )
        }
        return canvas
    }

    /// One head: cut from `source`, composited over `canvas`. The two are the same image in the
    /// sequential pass and deliberately different in the stacked one.
    private func grow(
        face: DetectedFace, from image: CIImage, over canvas: CIImage,
        progress: CGFloat, hardEdge: Bool, denseGroup: Bool
    ) -> CIImage {
        let extent = image.extent
        guard !suppressedFaceIDs.contains(face.id) else { return canvas }
        guard extent.width > 1, extent.height > 1,
              mask != nil || perFace.contains(where: { $0.isSemanticHeadMask })
        else { return canvas }

        // Quadratic, like HANDSOME: most of the growth arrives late, so the head inflates as
        // the zoom lands rather than being large for the whole loop.
        let amount = growth * (progress * progress)
        guard amount > 0.01 else { return canvas }

        // Person-mask approach: this face's own silhouette when one is available, matched in
        // normalized space; the union otherwise. Off by default — the shared union is the
        // approved baseline.
        let chosen: CIImage
        var derived: PerFaceMask? = nil
        // The scan results ride on the per-face entries even when the person-mask *silhouette*
        // is toggled off — AUTO FIT and PERSON MASKS are independent switches, and matching is
        // in normalized space either way.
        if let nearest = nearestPerFaceMask(to: face, extent: extent) {
            derived = nearest
            if nearest.isSemanticHeadMask || tuning.usePersonMasks {
                chosen = nearest.mask
            } else if let mask {
                chosen = mask
            } else {
                return canvas
            }
        } else if let mask {
            chosen = mask
        } else {
            return canvas
        }
        let subjectInFrame = scaled(chosen, to: extent)
        // Derived rows are normalized to the mask's own space; the frame is a uniform scale of
        // it, so a multiply re-expresses them here — the indirection that survives the preview.
        let neckY = derived?.neckNormY.map { CGFloat($0) * extent.height + extent.origin.y }
        let crownY = derived?.crownNormY.map { CGFloat($0) * extent.height + extent.origin.y }
        let headMask: CIImage
        if derived?.isSemanticHeadMask == true {
            // The provider has already removed clothes, neck and neighbouring people. Applying
            // another ellipse here would throw away the semantic boundary we paid to obtain.
            headMask = subjectInFrame.cropped(to: extent)
        } else {
            guard let legacy = Self.headMask(
                for: face, subject: subjectInFrame, extent: extent,
                tuning: tuning, sizeScale: sizeScale, regionBuilder: regionBuilder,
                neckY: neckY, crownY: crownY
            ) else { return canvas }
            headMask = legacy
        }

        // Pin low in the head so it grows upward and outward off the neck — but not at the
        // very bottom, which sends all growth upward and clips a tightly framed crown.
        // **Each mode pivots on its own geometry.** The ellipse path pivots in the ellipse's
        // bounds; the jaw path pivots just under its traced cut — an earlier version pivoted the
        // jaw mode on the ellipse bounds, which meant the "inert" ellipse sliders silently moved
        // where a jaw-mode head grew from.
        let pivot: CGPoint
        if derived?.isSemanticHeadMask == true, collisionSafe {
            // V2 grows *over* the detected face. V1 pivoted at the semantic mask's bottom,
            // which translates the source face upward by (scale - 1) × face-to-neck distance
            // and exposes the untouched face underneath. The face centre is stable across mask
            // shapes (hair, hats, profiles) and keeps the enlarged eyes/nose registered with the
            // original head while the outline expands in every direction.
            pivot = face.faceCenter
        } else if derived?.isSemanticHeadMask == true, let neckY {
            pivot = CGPoint(x: face.faceCenter.x, y: neckY)
        } else if tuning.useJawRegion,
           face.landmarkQuality == .precise,
           face.faceContourPoints.count >= HeadRegionBuilder.minContourPoints,
           let jawLowY = face.faceContourPoints.map(\.y).min() {
            let cut = jawLowY - face.faceHeight * CGFloat(tuning.jawDrop)
            let headSpan = face.faceHeight * 2.4
            pivot = CGPoint(x: face.faceCenter.x, y: cut + headSpan * CGFloat(tuning.pivotY) - headSpan * 0.3)
        } else {
            let bounds: CGRect
            if tuning.autoFit, let neckY, let crownY, crownY > neckY {
                let span = crownY - neckY
                let height = span * 1.25
                let centreY = (neckY + crownY) / 2
                let width = min(
                    face.faceWidth * CGFloat(tuning.ellipseWidth) * sizeScale,
                    span * 1.1
                )
                bounds = CGRect(
                    x: face.faceCenter.x - width / 2, y: centreY - height / 2,
                    width: width, height: height
                )
            } else {
                bounds = Self.ellipseBounds(for: face, tuning: tuning, sizeScale: sizeScale)
            }
            pivot = CGPoint(
                x: face.faceCenter.x,
                y: bounds.minY + bounds.height * CGFloat(tuning.pivotY)
            )
        }
        // Group membership must not change the requested size. Occlusion is resolved by the
        // ordered stacked compositor; every head receives the same intensity-driven scale as it
        // would in a one-person photo.
        let requestedScale = 1 + amount * CGFloat(tuning.growthMax)
        let transform: CGAffineTransform
        if derived?.isSemanticHeadMask == true, collisionSafe {
            transform = Self.semanticGrowthTransform(
                faceCenter: pivot, faceHeight: face.faceHeight,
                requestedScale: requestedScale, position: secondaryPosition
            )
        } else {
            transform = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
                .concatenating(CGAffineTransform(scaleX: requestedScale, y: requestedScale))
                .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))
        }

        // Clamped before transforming: a head near the frame edge should extend its border
        // pixels rather than sample transparency and tear a hole as it grows.
        let grownHead = image.clampedToExtent().transformed(by: transform)
        var grownMask = headMask.transformed(by: transform)
        guard grownHead.extent.hasFiniteComponents, grownMask.extent.hasFiniteComponents else {
            return canvas
        }
        if derived?.isSemanticHeadMask == true, collisionSafe {
            // Close model-resolution pinholes on the *grown* matte. An earlier repair unioned
            // the original footprint into this mask. In a dense group that made a later face
            // repaint its old footprint with pixels sampled through another face's transform,
            // producing the vertical dark slices seen in the night-selfie fixture. A small
            // dilation of the transformed matte still hides normal-size hair/hat slivers while
            // preserving the stacked compositor's depth ordering.
            let repairRadius = max(1, min(6, face.faceWidth * 0.014))
            grownMask = grownMask
                .applyingFilter("CIMorphologyMaximum", parameters: [
                    kCIInputRadiusKey: repairRadius
                ])
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: max(0.75, repairRadius * 0.45)
                ])
                // Keep one antialiased outer seam, but do not let the blur turn the enlarged
                // face into a translucent overlay. The semantic service has already decided
                // membership and made the protected face interior fully opaque.
                .cropped(to: extent)
            if !denseGroup {
                grownMask = grownMask
                    .applyingFilter("CIColorControls", parameters: [
                        kCIInputContrastKey: 3.0,
                        kCIInputBrightnessKey: 0.08
                    ])
                    .applyingFilter("CIColorClamp")
                    .cropped(to: extent)
            }
        }
        if hardEdge, derived?.isSemanticHeadMask != true {
            // Occlusion needs a step, not a feather: a soft edge here is exactly the
            // cross-fade the stacked pass exists to remove. Alpha is flattened first — the
            // region raster carries its coverage in alpha, and contrast alone would steepen
            // the wrong channel (the settingAlphaOne lesson, LEARNINGS 2026-08-20).
            grownMask = grownMask
                .settingAlphaOne(in: extent)
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 4.0,
                    kCIInputBrightnessKey: 0.05
                ])
                .applyingFilter("CIColorClamp")
        }

        return grownHead
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: canvas,
                kCIInputMaskImageKey: grownMask
            ])
            .cropped(to: extent)
    }

    /// The stored mask whose owner's face sits closest to `face`, compared in unit space so the
    /// match is immune to the preview's downsampling. The tolerance is face-relative: a missing
    /// semantic result must not borrow a nearby person's complete head matte and duplicate them.
    private func nearestPerFaceMask(to face: DetectedFace, extent: CGRect) -> PerFaceMask? {
        guard !perFace.isEmpty, extent.width > 0, extent.height > 0 else { return nil }
        if let exact = perFace.first(where: { $0.ownerID == face.id }) { return exact }
        let target = CGPoint(
            x: (face.faceCenter.x - extent.origin.x) / extent.width,
            y: (face.faceCenter.y - extent.origin.y) / extent.height
        )
        let best = perFace.min {
            hypot($0.normCenter.x - target.x, $0.normCenter.y - target.y) <
            hypot($1.normCenter.x - target.x, $1.normCenter.y - target.y)
        }
        let tolerance = max(0.01, face.faceWidth / extent.width * 0.35)
        guard let best,
              hypot(best.normCenter.x - target.x, best.normCenter.y - target.y) < tolerance
        else { return nil }
        return best
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
