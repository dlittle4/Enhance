import Testing
import CoreImage
import UIKit
@testable import Enhance

/// Tests for `BigHeadEffect`'s contract.
///
/// The assertions are deliberately coarse — *something changed*, or *nothing did*. Whether it
/// looks right is not testable and is judged by rendering (ROADMAP §1g); whether it drew at all
/// is exactly the kind of structural claim a test should pin, and is how the effect failed
/// silently in the app once before.
///
/// **This effect takes only the face it is handed**, so the caller owns the coordinate space.
/// That is deliberate: a version that carried its own face lists drew every head at
/// full-resolution coordinates on the downsampled preview and rendered nothing at all. Keeping
/// the space with the caller — which already scales the face — removes the chance to disagree.
struct BigHeadTests {

    private let context = CIContext(options: [.useSoftwareRenderer: true])

    /// A face measured against an image of `measuredAgainst` points square.
    private func makeFace(
        measuredAgainst: CGFloat, centre: CGPoint, width: CGFloat,
        quality: LandmarkQuality = .precise, contourPoints: Int = 16
    ) -> DetectedFace {
        let norm = CGRect(
            x: (centre.x - width / 2) / measuredAgainst,
            y: (centre.y - width / 2) / measuredAgainst,
            width: width / measuredAgainst,
            height: width / measuredAgainst
        )
        // A ring of points around the chin. This version bounds the head with an ellipse and
        // reads no contour, so these only make the fixture realistic.
        let contour = (0..<contourPoints).map { i -> CGPoint in
            let t = CGFloat(i) / CGFloat(max(1, contourPoints)) * .pi
            return CGPoint(x: centre.x - cos(t) * width / 2, y: centre.y - sin(t) * width / 3)
        }
        return DetectedFace(
            boundingBox: CGRect(x: centre.x - width / 2, y: centre.y - width / 2,
                                width: width, height: width),
            faceCenter: centre,
            faceWidth: width, faceHeight: width,
            leftPupilCenter: nil, rightPupilCenter: nil,
            leftEyeWidth: 0, rightEyeWidth: 0,
            leftEyebrowPoints: [], rightEyebrowPoints: [],
            faceContourPoints: contour,
            normalizedBoundingBox: norm,
            landmarkQuality: quality
        )
    }

    private func makeMask(side: CGFloat) -> CIImage {
        CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
    }

    /// Mean absolute difference between two images over `bounds`, 0 when identical.
    private func difference(
        _ a: CIImage, _ b: CIImage, side: Int, bounds: CGRect? = nil
    ) -> Double {
        let rect = bounds ?? CGRect(x: 0, y: 0, width: side, height: side)
        let w = Int(rect.width), h = Int(rect.height)
        func bytes(_ image: CIImage) -> [UInt8] {
            var buf = [UInt8](repeating: 0, count: w * h * 4)
            context.render(
                image,
                toBitmap: &buf,
                rowBytes: w * 4,
                bounds: rect,
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            return buf
        }
        let x = bytes(a), y = bytes(b)
        let total = zip(x, y).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(total) / Double(x.count)
    }

    @Test func aFaceInTheFrame_growsTheHead() {
        let side: CGFloat = 1000
        let source = CIImage(image: UIImage.checkerboard(side: side))!
        let face = makeFace(measuredAgainst: side, centre: CGPoint(x: 500, y: 500), width: 200)

        let effect = BigHeadEffect(intensity: 1.0, size: 0.5, mask: makeMask(side: side))
        let out = effect.apply(to: source, face: face, progress: 1.0, frameIndex: 7)

        #expect(difference(out, source, side: Int(side)) > 0.5)
    }

    /// A nil mask must return the frame untouched — §1g's rule, since the editor leaves the card
    /// live on a photo with no subject.
    @Test func withoutAMask_returnsTheFrameUnchanged() {
        let side: CGFloat = 400
        let source = CIImage(image: UIImage.checkerboard(side: side))!
        let face = makeFace(measuredAgainst: side, centre: CGPoint(x: 200, y: 200), width: 120)

        let effect = BigHeadEffect(intensity: 1.0, size: 0.5, mask: nil)
        let out = effect.apply(to: source, face: face, progress: 1.0, frameIndex: 7)

        #expect(difference(out, source, side: Int(side)) == 0)
    }

    // MARK: - Stage 1: sizing, gating, range, raster cap, cache

    /// The half-extent regression. With the corrected sizing, a point 1.5 face-widths from the
    /// face centre lies outside any plausible head region, so the effect must leave it alone —
    /// the buggy version's ellipse was ~2× too large and moved it.
    @Test func contentFarFromTheFace_isUntouched() {
        let side: CGFloat = 1000
        let source = CIImage(image: UIImage.checkerboard(side: side))!
        // .estimated → ellipse path, which is where the sizing bug lived.
        let face = makeFace(measuredAgainst: side, centre: CGPoint(x: 500, y: 500), width: 200,
                            quality: .estimated)
        // Moderate intensity, deliberately: at full 3× the *enlarged* head legitimately
        // reaches the probe. At 1.6× the corrected region's content stops ~60px short of it,
        // while the buggy double-size region would carry checkerboard across it — which is the
        // discrimination this test exists for.
        let effect = BigHeadEffect(intensity: 0.3, size: 1.0, mask: makeMask(side: side))
        let out = effect.apply(to: source, face: face, progress: 1.0, frameIndex: 7)

        // Probe a 40px strip at x=800+ (1.5 face-widths from centre): identical to the source.
        let region = CGRect(x: 820, y: 480, width: 40, height: 40)
        #expect(difference(out.cropped(to: region), source.cropped(to: region),
                           side: Int(side), bounds: region) == 0)
    }

    /// The effect must not read the contour at all — the traced-jaw path is parked (§2a), so a
    /// rich contour and a sparse synthetic one must render identically at any quality.
    @Test func contourIsNeverRead() {
        let side: CGFloat = 600
        let source = CIImage(image: UIImage.checkerboard(side: side))!
        let rich = makeFace(measuredAgainst: side, centre: CGPoint(x: 300, y: 300), width: 150,
                            quality: .estimated)
        let sparse = makeFace(measuredAgainst: side, centre: CGPoint(x: 300, y: 300), width: 150,
                              quality: .estimated, contourPoints: 5)
        let mask = makeMask(side: side)

        let a = BigHeadEffect(intensity: 0.8, size: 0.5, mask: mask)
            .apply(to: source, face: rich, progress: 1.0, frameIndex: 3)
        let b = BigHeadEffect(intensity: 0.8, size: 0.5, mask: mask)
            .apply(to: source, face: sparse, progress: 1.0, frameIndex: 3)

        #expect(difference(a, b, side: Int(side)) == 0)
    }

    /// The 3× range: at full intensity, head content reaches a probe point that 1.55× (the old
    /// ceiling) could not have moved anything into.
    @Test func fullIntensity_reachesBeyondTheOldCeiling() {
        let side: CGFloat = 1000
        let source = CIImage(image: UIImage.checkerboard(side: side))!
        let face = makeFace(measuredAgainst: side, centre: CGPoint(x: 500, y: 500), width: 200,
                            quality: .precise)
        let effect = BigHeadEffect(intensity: 1.0, size: 0.5, mask: makeMask(side: side))
        let out = effect.apply(to: source, face: face, progress: 1.0, frameIndex: 7)

        // The pivot sits ~474 in image space. At 3×, content originally ~155px above the pivot
        // lands ~465 above it; at 1.55× nothing above ~300 moves past 465. Probe a strip around
        // y=940 (in image space, near the top): it must differ from the source.
        let region = CGRect(x: 430, y: 900, width: 140, height: 60)
        #expect(difference(out.cropped(to: region), source.cropped(to: region),
                           side: Int(side), bounds: region) > 0.5)
    }

    /// HeadRegionBuilder is parked (§2a) but stays compiled per the retired-effects
    /// convention; its raster cap is a pure function — pin it without rendering.
    @Test func rasterScale_capsTheLongEdge() {
        #expect(HeadRegionBuilder.rasterScale(for: CGRect(x: 0, y: 0, width: 600, height: 600)) == 1)
        let big = HeadRegionBuilder.rasterScale(for: CGRect(x: 0, y: 0, width: 6000, height: 4500))
        #expect(abs(big - 1400.0 / 6000.0) < 0.0001)
        #expect(6000 * big <= HeadRegionBuilder.maxRasterSide + 0.5)
    }

    /// One raster per face per builder, across simulated GIF frames.
    @Test func regionIsCached_acrossFrames() {
        let builder = HeadRegionBuilder()
        let extent = CGRect(x: 0, y: 0, width: 800, height: 800)
        let face = makeFace(measuredAgainst: 800, centre: CGPoint(x: 400, y: 400), width: 160,
                            quality: .precise)
        for _ in 0..<8 {
            _ = builder.region(for: face, coverage: 1.3, extent: extent)
        }
        #expect(builder.rasterCount == 1)
    }

    // MARK: - Stage 2: batch seam and the layered pass

    private func rgbAt(_ image: CIImage, x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
        var buf = [UInt8](repeating: 0, count: 4)
        context.render(
            image, toBitmap: &buf, rowBytes: 4,
            bounds: CGRect(x: x, y: y, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (Double(buf[0]) / 255, Double(buf[1]) / 255, Double(buf[2]) / 255)
    }

    /// The batch method must dispatch dynamically through the `FaceEffect` existential — an
    /// extension-only method binds statically and an override silently never runs, which is
    /// how the layered pass could revert to the smear without any test noticing.
    @Test func batchApply_dispatchesThroughTheExistential() {
        struct Marker: FaceEffect {
            func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
                image
            }
            func apply(to image: CIImage, faces: [DetectedFace], progress: CGFloat, frameIndex: Int) -> CIImage {
                image.applyingFilter("CIColorInvert")
            }
        }
        let side: CGFloat = 64
        let source = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        let face = makeFace(measuredAgainst: side, centre: CGPoint(x: 32, y: 32), width: 20)

        let existential: FaceEffect = Marker()
        let out = existential.apply(to: source, faces: [face], progress: 1, frameIndex: 0)

        // The override inverts; the sequential default would return white untouched.
        let probe = rgbAt(out.cropped(to: source.extent), x: 32, y: 32)
        #expect(probe.r < 0.1)
    }

    /// A non-overriding effect through the batch call must equal the hand-written sequential
    /// loop — the default implementation is a refactor, not a behaviour change.
    @Test func defaultBatch_matchesTheSequentialLoop() {
        let side: CGFloat = 400
        let source = CIImage(image: UIImage.checkerboard(side: side))!
        let faces = [
            makeFace(measuredAgainst: side, centre: CGPoint(x: 120, y: 200), width: 90),
            makeFace(measuredAgainst: side, centre: CGPoint(x: 300, y: 200), width: 90)
        ]
        let effect: FaceEffect = HandsomeEffect(intensity: 0.8)

        let batch = effect.apply(to: source, faces: faces, progress: 1.0, frameIndex: 2)
        var loop = source
        for f in faces {
            loop = effect.apply(to: loop, face: f, progress: 1.0, frameIndex: 2)
        }

        #expect(difference(batch.cropped(to: source.extent),
                           loop.cropped(to: source.extent), side: Int(side)) == 0)
    }

    /// Progress 0 is the untouched frame, so the card can be previewed part-way.
    @Test func atZeroProgress_returnsTheFrameUnchanged() {
        let side: CGFloat = 400
        let source = CIImage(image: UIImage.checkerboard(side: side))!
        let face = makeFace(measuredAgainst: side, centre: CGPoint(x: 200, y: 200), width: 120)

        let effect = BigHeadEffect(intensity: 1.0, size: 0.5, mask: makeMask(side: side))
        let out = effect.apply(to: source, face: face, progress: 0, frameIndex: 0)

        #expect(difference(out, source, side: Int(side)) == 0)
    }
}

private extension UIImage {
    /// Something with enough local contrast that moving it registers as a difference.
    static func checkerboard(side: CGFloat) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: side, height: side), true, 1)
        let ctx = UIGraphicsGetCurrentContext()!
        let step = side / 10
        for row in 0..<10 {
            for col in 0..<10 {
                ctx.setFillColor(((row + col) % 2 == 0 ? UIColor.white : UIColor.black).cgColor)
                ctx.fill(CGRect(x: CGFloat(col) * step, y: CGFloat(row) * step,
                                width: step, height: step))
            }
        }
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image
    }
}
