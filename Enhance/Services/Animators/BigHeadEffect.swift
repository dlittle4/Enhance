import CoreImage
import UIKit

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
/// the whole body; the region decides where the head stops.
///
/// **The mask should be one person's silhouette, not the union of everyone** — see
/// `SubjectSegmentationService.instanceMask(for:containing:)`. With a shared mask, a group photo
/// forced the region's side walls in tight to keep the neighbour out, and they cut a straight
/// line through the subject's own hair instead of following him. Handed a per-person mask the
/// walls can stay far out, and the boundary follows the silhouette the way it always should
/// have. Two sources for that region, in
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
    /// Whether another face shares the photo. Decides how the head region is bounded — see
    /// `contourRegion`. Not a style choice: the two cases fail in opposite directions.
    private let isCrowded: Bool
    /// The faces whose heads this effect should grow — what the pipeline iterates. When the user
    /// isolates one face this is just that face.
    private let facesToGrow: [DetectedFace]

    /// **Every** face detected in the photo, selected or not. Kept separate from `facesToGrow`
    /// for one reason, and it is the bug that made this distinction necessary: the walls are
    /// placed relative to the *nearest other face*, and if the effect only knows about the
    /// selected face it concludes there are no neighbours and opens to full width — straight
    /// into the person beside them *(user-reported: adjacent faces still being enlarged even
    /// with a single face selected)*. Which heads grow and where the neighbours are are two
    /// different questions, and one list cannot answer both.
    private let neighbourFaces: [DetectedFace]
    private let cache = RegionCache()

    /// The region depends only on the face and the frame size, neither of which changes across
    /// a GIF's frames, so it is rendered once. A class so it survives the struct being copied.
    private final class RegionCache {
        var region: CIImage?
        var key: String?
    }

    /// - Parameters:
    ///   - intensity: how much the head grows — up to 3× at full.
    ///   - size: how much around the face the head ellipse covers. Larger catches tall hair and
    ///     ears; too large starts taking shoulder with it. Only reaches the ellipse fallback —
    ///     the contour path bounds itself.
    ///   - isCrowded: whether another face shares the photo.
    init(intensity: Double = 0.5, size: Double = 0.5, mask: CIImage? = nil,
         isCrowded: Bool = false, facesToGrow: [DetectedFace] = [],
         neighbourFaces: [DetectedFace] = []) {
        self.growth = CGFloat(max(0, min(1, intensity)))
        self.coverage = 1.05 + CGFloat(max(0, min(1, size))) * 0.6
        self.mask = mask
        self.isCrowded = isCrowded
        self.facesToGrow = facesToGrow
        // Falling back to the growing set keeps a caller that passes only one list correct rather
        // than silently wall-less.
        self.neighbourFaces = neighbourFaces.isEmpty ? facesToGrow : neighbourFaces
    }

    /// Same effect with the segmentation mask attached — the view model has it, the factory does not.
    func withMask(
        _ mask: CIImage?, isCrowded: Bool,
        facesToGrow: [DetectedFace], neighbourFaces: [DetectedFace]
    ) -> BigHeadEffect {
        BigHeadEffect(intensity: Double(growth), size: Double((coverage - 1.05) / 0.6),
                      mask: mask, isCrowded: isCrowded,
                      facesToGrow: facesToGrow, neighbourFaces: neighbourFaces)
    }

    /// **Every head is composited in one pass, from the original frame, back to front.**
    ///
    /// `GIFGenerator.faceEffectedSource` calls a `FaceEffect` once per face, feeding each call the
    /// *previous* call's output. For a distortion that is fine. For this effect it is not: once
    /// two enlarged heads overlap, the second pass re-scales pixels that already contain the
    /// first enlarged head, so the two smear into each other rather than one sitting in front of
    /// the other *(user-reported: "they overlap and blur together")*.
    ///
    /// So the work happens once. The first face in `allFaces` renders every head; the remaining
    /// calls return their input untouched. Each head is cut from the **original** frame, never
    /// from a partly-composited one, and they are drawn in depth order — widest face last, since
    /// a face is wider the closer it is to the camera — so the nearest head lands on top.
    ///
    /// The mask is thresholded to hard edges before compositing. A soft edge is what lets two
    /// overlapping heads cross-fade into a translucent mush; a hard one makes the front head
    /// occlude the one behind, which is what overlapping heads should do.
    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let extent = image.extent
        guard let mask, extent.width > 1, extent.height > 1 else { return image }

        // One pass does all of them; the rest are no-ops.
        let faces = facesToGrow.isEmpty ? [face] : facesToGrow
        // Only the pipeline's first call does the work. If `face` is not in the growing set at
        // all, fall through and grow it anyway rather than rendering nothing — a mismatch between
        // the list and what the pipeline iterates should degrade to the old per-face behaviour,
        // not to a silently dead effect.
        if let first = faces.first, faces.contains(where: { $0.faceCenter == face.faceCenter }),
           first.faceCenter != face.faceCenter {
            return image
        }

        // Farthest first, so the nearest head is composited last and occludes the others.
        let ordered = faces.sorted { $0.faceWidth < $1.faceWidth }
        var result = image
        for f in ordered {
            result = grow(head: f, from: image, over: result, mask: mask, progress: progress)
        }
        return result
    }

    /// One head, cut from `source` and composited over `canvas`.
    private func grow(
        head face: DetectedFace,
        from image: CIImage,
        over canvas: CIImage,
        mask: CIImage,
        progress: CGFloat
    ) -> CIImage {
        let extent = image.extent

        // Quadratic, like HANDSOME: most of the growth arrives late, so the head inflates as the
        // zoom lands rather than being large for the whole loop.
        let amount = growth * (progress * progress)
        guard amount > 0.01 else { return canvas }

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
        else { return canvas }

        let subjectInFrame = scaled(mask, to: extent)

        // The region that says "this part of the subject is head". Prefer the traced contour;
        // fall back to the ellipse where Vision gave none.
        let region = contourRegion(for: face, extent: extent)
            ?? FaceRegionMaskBuilder.ellipticalMask(bounds: headBounds, feather: 0.35)
        guard let region else { return canvas }

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
        // **Max 3.0×**, raised from 1.55× on the user's call (2026-08-19). The old ceiling was
        // set against a tightly framed cat, where 1.85× already overflowed the frame. Real
        // photos frame a head as a small share of the picture — in `IMG_0624` it is a few
        // percent — so the same multiplier that overwhelmed the cat is barely visible there.
        // The ceiling belongs to the *framing*, not the effect, and the wider range covers both.
        let scale = 1 + amount * 2.0
        let transform = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))

        // Clamped before transforming: a head near the frame edge should extend its border
        // pixels rather than sample transparency and tear a hole as it grows.
        let grownHead = image.clampedToExtent().transformed(by: transform)
        let grownMask = headMask.transformed(by: transform)

        guard grownHead.extent.hasFiniteComponents, grownMask.extent.hasFiniteComponents else {
            return canvas
        }

        // **Hard edge, deliberately.** A feathered mask cross-fades this head with whatever is
        // already on the canvas, and where two enlarged heads overlap that is a translucent mush
        // rather than one head in front of another. Clamping the mask to a step makes the
        // compositing an occlusion.
        let hardMask = grownMask.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 12.0,
            kCIInputBrightnessKey: -0.15
        ]).applyingFilter("CIColorClamp")

        return grownHead
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: canvas,
                kCIInputMaskImageKey: hardMask
            ])
            .cropped(to: extent)
    }

    /// A head region built from Vision's traced face contour, or `nil` when there is none.
    ///
    /// **The contour is not a head outline** — it runs ear-to-ear round the jaw with nothing
    /// above the brow, so filling it alone would cut the head off at the eyebrows. What it gives
    /// is the one thing segmentation cannot: **where the head stops and the neck starts.** So the
    /// region is the contour *extended upward* — bounded below by the real jaw, open above — and
    /// the subject mask supplies crown and hair inside it.
    ///
    /// **Following the curve is the whole point.** An earlier version cut horizontally at the
    /// contour's lowest point, which is the chin. A jaw rises toward the ears, so a flat cut at
    /// chin height sits *below* the jaw on both sides and scooped up neck — reported as "still
    /// including the neck and not outlining around the chin". Only the traced path bounds it
    /// correctly, and no amount of moving a straight line fixes a curve.
    ///
    /// Rendered rather than composed from gradients, because a curve through arbitrary points is
    /// not a product of linear ramps. Cached on the face and frame size, neither of which changes
    /// across a GIF's frames — the same trick `AnimeBackgroundEffect` uses, and the reason this
    /// does not cost a render per frame.
    private func contourRegion(for face: DetectedFace, extent: CGRect) -> CIImage? {
        let points = face.faceContourPoints
        // **12, not 5.** Vision's real `faceContour` returns dozens of points along the jaw; a
        // handful means detection fell back and the "contour" is a few landmarks that do not
        // describe a jawline. The corpus caught this: the person in `showcase-3` faces away, so
        // Vision returned 5 points at `.estimated` quality and a 5-point guard let that through
        // to place a chin cut from noise.
        guard points.count >= 12, face.landmarkQuality != .estimated else { return nil }

        let w = Int(extent.width), h = Int(extent.height)
        guard w > 1, h > 1 else { return nil }

        let key = "\(w)x\(h)|\(Int(face.faceCenter.x)),\(Int(face.faceCenter.y))|\(points.count)|\(Int(face.faceWidth))"
        if cache.key == key, let cached = cache.region { return cached }

        UIGraphicsBeginImageContextWithOptions(CGSize(width: w, height: h), true, 1)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }

        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Image coordinates are y-up; the drawing context is y-down.
        func draw(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x - extent.origin.x, y: CGFloat(h) - (p.y - extent.origin.y))
        }

        // Sorted left-to-right so the closing edge over the top of the head cannot cross back
        // through the face. Vision returns the contour in order, but sorting makes the polygon
        // well-formed regardless of which ear it starts from.
        let jaw = points.sorted { $0.x < $1.x }.map(draw)
        guard let first = jaw.first, let last = jaw.last else { return nil }

        // **The sides flare outward going up, rather than rising straight from the jaw.**
        // A jaw is the narrowest part of a head: hair, ears and anything worn are all wider,
        // and vertical walls at jaw width sliced them off — reported as not capturing the top
        // of the head, on a photo where the subject is wearing a cap much wider than his chin.
        //
        // The flare is centred on the **face centre**, not on the jaw's own extremes, which is
        // what makes it survive a profile. In profile the contour traces only the visible side,
        // so its extremes are lopsided and the skull sits behind the far edge; widening about
        // the face centre reaches back over it, where widening about the contour would lean the
        // region further off the head.
        let centreX = draw(face.faceCenter).x
        let jawHalf = max((last.x - first.x) * 0.5, face.faceWidth * 0.35)
        let top = -CGFloat(h)

        // **Two models, chosen by whether anyone else is in the photo.** They fail in opposite
        // directions, which is why one setting cannot serve both:
        //
        // - *Alone in the frame:* above the jaw, everything in the subject mask **is** the head,
        //   so the walls only need to be loose enough not to clip it. Tight walls were the bug
        //   reported as the back of the head going missing — `faceCenter` sits toward the
        //   *front* of a head in profile, and the skull runs much further back than forward, so
        //   a region centred there and symmetric could not reach it. Widening is free here.
        // - *Someone beside them:* loose walls reach straight into the next person's head and
        //   grow two heads as one. Here the walls are the only thing preventing that, so they
        //   stay near the face.
        //
        // The earlier single setting was a compromise that did neither job: too tight for a
        // profile, and it would have been too loose had the group photos been rendered.
        // **The wall is still the only thing separating people, and here is why.**
        //
        // These were briefly widened on the belief that a per-person mask made them redundant.
        // Measured on the fixture corpus, that belief is false:
        // `VNGenerateForegroundInstanceMaskRequest` returns **one** foreground instance for every
        // photo tested, including a three-face and a ten-face one. It segments a group as a
        // single blob, so there is no per-person instance to select and the mask cannot exclude
        // a neighbour. Widening them enlarged everyone's head at once *(user-reported)*.
        //
        // So a crowded photo keeps a tight wall, and keeps the seam that comes with it — cutting
        // through the subject's own hair is the price of not growing the person beside them.
        // Solo photos stay loose, where there is nobody to reach into and the silhouette can do
        // the bounding properly.
        //
        // **The real fix is a different Vision request**, not a better constant — see ROADMAP §2a.
        // **The wall goes as wide as it can without reaching the next person.**
        //
        // A fixed crowded wall was the compromise that clipped hair: narrow enough to miss the
        // neighbour in the worst case, so needlessly narrow in every other case, and hair sits
        // exactly where it cut *(user-reported: "struggling with hair along the sides of the
        // face")*. Since segmentation cannot separate people here — see the note below — the
        // constraint has to come from the *faces*, and the honest limit is halfway to whichever
        // face is nearest on that side. Nobody beside them means nothing to avoid, so it opens
        // up to the solo width.
        let generous = max(jawHalf * 3.4, face.faceWidth * 1.9)
        let neighbours = neighbourFaces.filter { $0.faceCenter != face.faceCenter }
        let gapLeft = neighbours
            .filter { $0.faceCenter.x < face.faceCenter.x }
            .map { (face.faceCenter.x - $0.faceCenter.x) * 0.5 }
            .min() ?? generous
        let gapRight = neighbours
            .filter { $0.faceCenter.x > face.faceCenter.x }
            .map { ($0.faceCenter.x - face.faceCenter.x) * 0.5 }
            .min() ?? generous
        // A floor, or two faces almost touching leave no head at all.
        let topHalf = max(face.faceWidth * 0.7, min(generous, min(gapLeft, gapRight)))

        let path = UIBezierPath()
        path.move(to: first)
        for p in jaw.dropFirst() { path.addLine(to: p) }
        // Out and up on the right, across the top, then back down to the jaw on the left. The
        // region stays open above so the subject mask still decides how much hair is included —
        // the flare only stops the walls from clipping it.
        path.addLine(to: CGPoint(x: centreX + topHalf, y: last.y - jawHalf * 0.6))
        path.addLine(to: CGPoint(x: centreX + topHalf, y: top))
        path.addLine(to: CGPoint(x: centreX - topHalf, y: top))
        path.addLine(to: CGPoint(x: centreX - topHalf, y: first.y - jawHalf * 0.6))
        path.close()

        ctx.setFillColor(UIColor.white.cgColor)
        ctx.addPath(path.cgPath)
        ctx.fillPath()

        guard let cg = UIGraphicsGetImageFromCurrentImageContext()?.cgImage else { return nil }

        // Ears and hair sit outside the contour, which traces skin only — grow the region to
        // take them in, then soften so the jaw reads as a fade rather than a cut line.
        // **Clamped before each filter, and that is not a detail.** Both the dilation and the
        // blur sample outside the region image, where there is nothing — so without clamping
        // they fade the region toward zero along the *frame's* edges. The head is open above by
        // design, so on any photo where the head sits near the top of the frame that falloff
        // lands right on the crown: the mask drops to a partial value, `CIBlendWithMask`
        // cross-fades the enlarged head against the original underneath, and the hair ghosts
        // into a doubled halo *(user-reported: "details at the top of the head are being blended
        // into the face")*. It reads as a blending bug in the compositing and is really an edge
        // condition in the mask's own construction.
        let grow = max(2, face.faceWidth * 0.10)
        let region = CIImage(cgImage: cg)
            .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
            .clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": grow])
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: grow * 0.5])
            .cropped(to: extent)

        cache.key = key
        cache.region = region
        return region
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
