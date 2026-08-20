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
    private func makeFace(measuredAgainst: CGFloat, centre: CGPoint, width: CGFloat) -> DetectedFace {
        let norm = CGRect(
            x: (centre.x - width / 2) / measuredAgainst,
            y: (centre.y - width / 2) / measuredAgainst,
            width: width / measuredAgainst,
            height: width / measuredAgainst
        )
        // A ring of points around the chin. This version bounds the head with an ellipse and
        // reads no contour, so these only make the fixture realistic.
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
