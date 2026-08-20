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
    func region(for face: DetectedFace, coverage: CGFloat, extent: CGRect) -> CIImage? {
        guard extent.width > 1, extent.height > 1 else { return nil }

        let key = cacheKey(for: face, coverage: coverage, extent: extent)
        if let cached = cache[key] { return cached }

        let built: CIImage?
        if face.landmarkQuality == .precise, face.faceContourPoints.count >= Self.minContourPoints {
            built = jawCutRegion(for: face, extent: extent)
        } else {
            built = ellipseRegion(for: face, coverage: coverage, extent: extent)
        }

        if let built { cache[key] = built }
        return built
    }

    // MARK: - Traced jaw

    private func jawCutRegion(for face: DetectedFace, extent: CGRect) -> CIImage? {
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

        // Left-to-right so the closing run over the top cannot cross back through the face.
        let jaw = face.faceContourPoints.sorted { $0.x < $1.x }.map(draw)
        guard let first = jaw.first, let last = jaw.last, last.x > first.x else { return nil }

        // Bottom boundary: frame edge at ear level, along the traced jaw, out to the other
        // edge at ear level. Ear level (the jaw's endpoints) sits above the chin, so shoulders
        // — which start below it — stay excluded at the sides without any wall doing it.
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -1, y: first.y))
        path.addLine(to: first)
        for p in jaw.dropFirst() { path.addLine(to: p) }
        path.addLine(to: CGPoint(x: CGFloat(w) + 1, y: last.y))
        // Up the right edge, across the top, down the left — open above by construction.
        path.addLine(to: CGPoint(x: CGFloat(w) + 1, y: -1))
        path.addLine(to: CGPoint(x: -1, y: -1))
        path.close()

        ctx.setFillColor(UIColor.white.cgColor)
        ctx.addPath(path.cgPath)
        ctx.fillPath()

        guard let cg = UIGraphicsGetImageFromCurrentImageContext()?.cgImage else { return nil }
        rasterCount += 1

        // The jaw cut is the only seam, and it should read as a fade into the neck rather
        // than a knife line. Clamped first: an unclamped blur samples the void past the frame
        // edge and fades the region exactly where a tightly framed crown needs it solid.
        let featherRadius = max(1.5, face.faceWidth * scale * 0.05)
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
        return FaceRegionMaskBuilder.ellipticalMask(bounds: bounds, feather: 0.35)?
            .cropped(to: extent)
    }

    private func cacheKey(for face: DetectedFace, coverage: CGFloat, extent: CGRect) -> String {
        "\(Int(extent.width))x\(Int(extent.height))|\(Int(face.faceCenter.x)),\(Int(face.faceCenter.y))|" +
        "\(Int(face.faceWidth))x\(Int(face.faceHeight))|\(face.faceContourPoints.count)|" +
        "\(face.landmarkQuality == .precise ? "p" : "e")|\(Int(coverage * 100))"
    }
}
