import Testing
import CoreImage
import UIKit
@testable import Enhance

/// Tests for `BigHeadEffect`'s coordinate handling.
///
/// **These exist because the fixture renders could not catch this class of bug.** Those feed a
/// full-resolution image together with full-resolution faces, which is the one combination where
/// a coordinate-space mismatch cancels out. The app does not do that: the preview renders a
/// downsampled copy and scales the face it passes in, while the effect's own face lists stay at
/// full resolution. The effect then drew every head far outside the frame and rendered nothing —
/// visible on device as the card simply not working, and invisible to every test we had.
///
/// So the assertion here is deliberately coarse: *something changed*. Whether it looks right is
/// not testable and is judged by rendering (ROADMAP §1g); whether it drew at all is exactly the
/// kind of structural claim a test should pin.
struct BigHeadTests {

    private let context = CIContext(options: [.useSoftwareRenderer: true])

    /// A face whose pixel geometry was measured against `measuredAgainst`, so its normalized box
    /// disagrees with any frame of a different size — the situation the preview creates.
    private func makeFace(measuredAgainst: CGFloat, centre: CGPoint, width: CGFloat) -> DetectedFace {
        let norm = CGRect(
            x: (centre.x - width / 2) / measuredAgainst,
            y: (centre.y - width / 2) / measuredAgainst,
            width: width / measuredAgainst,
            height: width / measuredAgainst
        )
        // A ring of contour points around the chin, enough to pass the 12-point gate so the
        // contour path is what gets exercised rather than the ellipse fallback.
        let contour = (0..<16).map { i -> CGPoint in
            let t = CGFloat(i) / 16 * .pi
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
            landmarkQuality: .precise
        )
    }

    private func makeMask(side: CGFloat) -> CIImage {
        CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
    }

    /// Mean absolute difference between two images, 0 when identical.
    private func difference(_ a: CIImage, _ b: CIImage, side: Int) -> Double {
        func bytes(_ image: CIImage) -> [UInt8] {
            var buf = [UInt8](repeating: 0, count: side * side * 4)
            context.render(
                image,
                toBitmap: &buf,
                rowBytes: side * 4,
                bounds: CGRect(x: 0, y: 0, width: side, height: side),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            return buf
        }
        let x = bytes(a), y = bytes(b)
        let total = zip(x, y).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(total) / Double(x.count)
    }

    // MARK: - Coordinate spaces

    /// The regression. Faces measured against a 4000px image, applied to a 1000px frame — which
    /// is what the preview does every time it renders.
    @Test func facesFromALargerImage_stillGrowTheHead() {
        let side: CGFloat = 1000
        let source = CIImage(image: UIImage.checkerboard(side: side))!
        let face = makeFace(measuredAgainst: 4000, centre: CGPoint(x: 2000, y: 2000), width: 800)

        let effect = BigHeadEffect(
            intensity: 1.0, size: 0.5, mask: makeMask(side: side),
            facesToGrow: [face], neighbourFaces: [face]
        )
        let out = effect.apply(to: source, face: face, progress: 1.0, frameIndex: 7)

        #expect(difference(out, source, side: Int(side)) > 0.5)
    }

    /// The case the fixture renders already covered, kept so a fix for the above cannot silently
    /// break the path that was working.
    @Test func facesFromTheSameImage_stillGrowTheHead() {
        let side: CGFloat = 1000
        let source = CIImage(image: UIImage.checkerboard(side: side))!
        let face = makeFace(measuredAgainst: side, centre: CGPoint(x: 500, y: 500), width: 200)

        let effect = BigHeadEffect(
            intensity: 1.0, size: 0.5, mask: makeMask(side: side),
            facesToGrow: [face], neighbourFaces: [face]
        )
        let out = effect.apply(to: source, face: face, progress: 1.0, frameIndex: 7)

        #expect(difference(out, source, side: Int(side)) > 0.5)
    }

    /// A nil mask must return the frame untouched — §1g's rule, since the editor leaves the card
    /// live on a photo with no subject.
    @Test func withoutAMask_returnsTheFrameUnchanged() {
        let side: CGFloat = 400
        let source = CIImage(image: UIImage.checkerboard(side: side))!
        let face = makeFace(measuredAgainst: side, centre: CGPoint(x: 200, y: 200), width: 120)

        let effect = BigHeadEffect(intensity: 1.0, size: 0.5, mask: nil,
                                   facesToGrow: [face], neighbourFaces: [face])
        let out = effect.apply(to: source, face: face, progress: 1.0, frameIndex: 7)

        #expect(difference(out, source, side: Int(side)) == 0)
    }

    /// Progress 0 is the untouched frame, so the card can be previewed part-way.
    @Test func atZeroProgress_returnsTheFrameUnchanged() {
        let side: CGFloat = 400
        let source = CIImage(image: UIImage.checkerboard(side: side))!
        let face = makeFace(measuredAgainst: side, centre: CGPoint(x: 200, y: 200), width: 120)

        let effect = BigHeadEffect(intensity: 1.0, size: 0.5, mask: makeMask(side: side),
                                   facesToGrow: [face], neighbourFaces: [face])
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
