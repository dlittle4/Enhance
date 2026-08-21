import CoreImage
import UIKit

/// Builds the "this part of the subject is head" region for `BigHeadEffect`.
///
/// The region answers exactly one question — *where does the head stop and the body start* —
/// and deliberately answers nothing else. Person separation is the segmentation mask's job
/// (`SubjectSegmentationService`), and the day this file's predecessors spent trying to do it
/// with side walls is recorded on ROADMAP §2a: every wall tight enough to exclude a neighbour
/// cut the subject's own hair. There are no walls here.
///
/// Two paths:
///
/// 1. **Traced jaw** — when landmarks are `.precise` and the contour is real (Vision's
///    `faceContour`, 12+ points ear-to-ear). The region is everything above the jaw curve,
///    extended horizontally to the frame edges at ear level and open to the top of frame.
///    Crown, hats and hair are *not* traced — they come from the segmentation silhouette this
///    region is intersected with, which is the only source that actually knows where a cap ends.
/// 2. **Ellipse** — animals (synthetic 5-point contours) and `.estimated` faces. The corrected
///    geometry from the version whose cat renders were approved: half-extents are *halved*
///    (`faceWidth × coverage` is the full width — an earlier version used it as the half-extent,
///    which made the ellipse enclose the whole animal and scaled the entire subject).
///
/// **The raster is capped** at `maxRasterSide` on the long edge and scaled into place — a mask
/// is a smooth shape, not detail, and an uncapped version drew ~98MB bitmaps per face on a 24MP
/// photo and killed the process (§2a). Filters are `.clampedToExtent()` first, because an
/// unclamped blur fades the region at the frame edge and ghosts a crown that sits near the top
/// of frame — both constraints are paid-for lessons, not style.
///
/// A reference type so the cache survives `BigHeadEffect` (a struct) being copied: the effect
/// is rebuilt per preview update but reused across a GIF's frames, so a render costs one raster
/// per face, not one per face per frame.
final class HeadRegionBuilder {

    /// Long edge of the region raster.
    static let maxRasterSide: CGFloat = 1400

    /// The contour path requires this many traced points. Vision's real `faceContour` is 17;
    /// animal and fallback contours are synthetic 5-point arcs that describe nothing.
    static let minContourPoints = 12

    private var cache: [String: CIImage] = [:]

    /// How many rasters have actually been drawn — the cache's job is to keep this at one per
    /// face per builder lifetime, and counting is how the tests assert that without timing.
    private(set) var rasterCount = 0

    /// The scale that fits `extent` inside `maxRasterSide`, 1 when it already fits.
    /// Pure and static so the cap is testable without rendering anything.
    static func rasterScale(for extent: CGRect) -> CGFloat {
        let longEdge = max(extent.width, extent.height)
        guard longEdge > maxRasterSide else { return 1 }
        return maxRasterSide / longEdge
    }

    /// The head region for `face`, in `extent`'s space — white where head is allowed, black
    /// where it is not, feathered only at the jaw/neck cut.
    /// - Parameter xBounds: optional hard horizontal limits in frame space. Used only when two
    ///   faces share one segmentation mask — the mask cannot separate them there, so the region
    ///   is cut at the midline between them. Per-person-mask faces never pass this.
    func region(
        for face: DetectedFace, coverage: CGFloat, extent: CGRect,
        xBounds: ClosedRange<CGFloat>? = nil,
        jawDrop: CGFloat = 0.12, jawFeather: CGFloat = 0.08
    ) -> CIImage? {
        guard extent.width > 1, extent.height > 1 else { return nil }

        let key = cacheKey(for: face, coverage: coverage, extent: extent, xBounds: xBounds)
            + "|d\(Int(jawDrop * 100))f\(Int(jawFeather * 100))"
        if let cached = cache[key] { return cached }

        var built: CIImage?
        if face.landmarkQuality == .precise, face.faceContourPoints.count >= Self.minContourPoints {
            built = jawCutRegion(for: face, extent: extent, jawDrop: jawDrop, jawFeather: jawFeather)
        } else {
            built = ellipseRegion(for: face, coverage: coverage, extent: extent)
        }
        if let bounds = xBounds, let unbounded = built {
            // A hard vertical cut at the shared-mask midline. Hard on purpose: a feathered cut
            // here would translucently blend two neighbours' grown heads — the cross-fade this
            // pipeline just finished eliminating.
            let clip = CGRect(
                x: bounds.lowerBound, y: extent.origin.y - 1,
                width: bounds.upperBound - bounds.lowerBound, height: extent.height + 2
            )
            let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0))
                .cropped(to: extent)
            built = unbounded.cropped(to: clip).composited(over: black)
                .cropped(to: extent)
        }

        if let built { cache[key] = built }
        return built
    }

    // MARK: - Traced jaw

    private func jawCutRegion(
        for face: DetectedFace, extent: CGRect, jawDrop: CGFloat, jawFeather: CGFloat
    ) -> CIImage? {
        let scale = Self.rasterScale(for: extent)
        let w = max(2, Int((extent.width * scale).rounded()))
        let h = max(2, Int((extent.height * scale).rounded()))

        UIGraphicsBeginImageContextWithOptions(CGSize(width: w, height: h), true, 1)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }

        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Image coordinates are y-up; the drawing context is y-down.
        func draw(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: (p.x - extent.origin.x) * scale,
                y: CGFloat(h) - (p.y - extent.origin.y) * scale
            )
        }

        // **Vision's native order, not sorted.** The contour is traced ear-to-ear in order;
        // sorting by x scrambles a tilted head's curve into a zigzag that slices through the
        // face — rendered as hair and cheek refusing to grow on a profile. Only the direction
        // is normalized, so the polygon closes consistently.
        // **The contour is a reference line, not the boundary.** Vision traces the face oval —
        // cheeks, not the anatomical jaw — so ears sit *outside* it, and a cut placed on the
        // trace both clips them and draws a visible seam along the face (user-reported: ears
        // cut off, an artificial line around the jaw). The cut is therefore pushed ~12% of a
        // face-height *below* the trace: under the chin and ear lobes, where the seam hides in
        // the neck, while ears and everything above stay inside the region.
        let drop = face.faceHeight * scale * jawDrop
        var jaw = face.faceContourPoints.map(draw).map { CGPoint(x: $0.x, y: $0.y + drop) }
        guard jaw.count >= 2 else { return nil }
        if let f = jaw.first, let l = jaw.last, f.x > l.x { jaw.reverse() }
        guard let first = jaw.first, let last = jaw.last else { return nil }

        // **The region is local — bounded at ±2.2 face-widths — not frame-wide.** This is not a
        // person-separating wall (2.2 face-widths clears any hat or hair; the person mask does
        // the separating). It exists for the shared-mask case: past Vision's 4-instance cap a
        // mask covers several people, and a frame-wide region grown once per face duplicated
        // every face and torso in the shared silhouette across the photo.
        let bound = face.faceWidth * scale * 2.2
        let leftX = max(-1, min(first.x, last.x) - bound + (last.x - first.x) * 0.5)
        let rightX = min(CGFloat(w) + 1, max(first.x, last.x) + bound - (last.x - first.x) * 0.5)

        // From each jaw endpoint the cut continues *downward-outward* (~25°) to the bound,
        // rather than flat at ear level: hair that hangs below the ears — a bun, a bob —
        // otherwise gets a hard horizontal cut behind the head.
        let slope: CGFloat = 0.47   // tan(25°)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: leftX, y: first.y + (first.x - leftX) * slope))
        path.addLine(to: first)
        for p in jaw.dropFirst() { path.addLine(to: p) }
        path.addLine(to: CGPoint(x: rightX, y: last.y + (rightX - last.x) * slope))
        // Up the sides, across the top — open above within the bounds.
        path.addLine(to: CGPoint(x: rightX, y: -1))
        path.addLine(to: CGPoint(x: leftX, y: -1))
        path.close()

        ctx.setFillColor(UIColor.white.cgColor)
        ctx.addPath(path.cgPath)
        ctx.fillPath()

        guard let cg = UIGraphicsGetImageFromCurrentImageContext()?.cgImage else { return nil }
        rasterCount += 1

        // The jaw cut is the only seam, and it should read as a fade into the neck rather
        // than a knife line. Clamped first: an unclamped blur samples the void past the frame
        // edge and fades the region exactly where a tightly framed crown needs it solid.
        let featherRadius = max(2, face.faceWidth * scale * jawFeather)
        return CIImage(cgImage: cg)
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: featherRadius])
            .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
            .transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
            .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
            .cropped(to: extent)
    }

    // MARK: - Ellipse fallback

    private func ellipseRegion(for face: DetectedFace, coverage: CGFloat, extent: CGRect) -> CIImage? {
        // Half-extents halved — `faceWidth × coverage` is the full width. The unhalved version
        // is the recorded bug that scaled entire animals instead of their heads.
        let halfW = face.faceWidth * 0.5 * coverage
        let halfH = face.faceHeight * 0.5 * coverage
        let bounds = CGRect(
            x: face.faceCenter.x - halfW,
            // Biased upward: a face box is centred on the face, while a head runs from the
            // chin to above the crown — centred on the face it clips hair while dipping into
            // the chest.
            y: face.faceCenter.y - halfH * 0.85,
            width: halfW * 2,
            height: halfH * 2.2
        )
        guard bounds.hasFiniteComponents, bounds.width >= 2, bounds.height >= 2 else { return nil }
        rasterCount += 1
        // `ellipticalMask` is a lazy CIRadialGradient — no bitmap, so no cap needed here.
        //
        // **`settingAlphaOne` is load-bearing.** The gradient feathers via *falling alpha over
        // white RGB*, and a mask that carries its value in alpha misbehaves downstream: colour
        // filters (contrast hardening) adjust unpremultiplied RGB — solid white everywhere in
        // that gradient — and never touch alpha, and the composite honoured neither the value
        // probes showed nor the one intended. Days ago this surfaced as stacked heads
        // cross-fading at a constant ~14% for no discernible reason. Flattening premultiplied
        // RGB (white × alpha = the ramp) into an opaque grayscale mask makes it behave like
        // every other mask in this pipeline — the segmentation masks are opaque one-component
        // buffers, which is why they never hit this.
        return FaceRegionMaskBuilder.ellipticalMask(bounds: bounds, feather: 0.35)?
            .cropped(to: extent)
            .settingAlphaOne(in: extent)
    }

    private func cacheKey(
        for face: DetectedFace, coverage: CGFloat, extent: CGRect, xBounds: ClosedRange<CGFloat>?
    ) -> String {
        let bounds = xBounds.map { "\(Int($0.lowerBound))..\(Int($0.upperBound))" } ?? "open"
        return baseCacheKey(for: face, coverage: coverage, extent: extent) + "|" + bounds
    }

    private func baseCacheKey(for face: DetectedFace, coverage: CGFloat, extent: CGRect) -> String {
        "\(Int(extent.width))x\(Int(extent.height))|\(Int(face.faceCenter.x)),\(Int(face.faceCenter.y))|" +
        "\(Int(face.faceWidth))x\(Int(face.faceHeight))|\(face.faceContourPoints.count)|" +
        "\(face.landmarkQuality == .precise ? "p" : "e")|\(Int(coverage * 100))"
    }
}
