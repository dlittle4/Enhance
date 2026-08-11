import Testing
import CoreImage
import UIKit
@testable import Enhance

/// Correctness invariants for THIRD EYE and its reusable landmark compositor. These guard
/// extent preservation, timeline no-ops, missing-landmark safety, region resolution, the eye
/// tint, and coordinate scaling — not appearance, which is judged on device.
struct ThirdEyeTests {

    private let ctx = CIContext(options: [.useSoftwareRenderer: true])
    private let bg: CGFloat = 128

    // MARK: - Fixtures

    /// A 300x300 face-like fixture with a distinctive cyan left eye.
    private func makeFixture() -> CIImage {
        let size = CGSize(width: 300, height: 300)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        let g = UIGraphicsGetCurrentContext()!
        g.setFillColor(UIColor(white: bg / 255, alpha: 1).cgColor)
        g.fill(CGRect(origin: .zero, size: size))
        g.setFillColor(UIColor(red: 0, green: 1, blue: 1, alpha: 1).cgColor)
        g.fillEllipse(in: CGRect(x: 100 - 26, y: (300 - 190) - 15, width: 52, height: 30))
        let ui = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return CIImage(cgImage: ui.cgImage!)
    }

    private func eyePolygon(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat) -> [CGPoint] {
        (0..<12).map { CGPoint(x: cx + rx * cos(CGFloat($0) / 12 * 2 * .pi),
                               y: cy + ry * sin(CGFloat($0) / 12 * 2 * .pi)) }
    }

    private func makePreciseFace() -> DetectedFace {
        let regions = FaceRegions(
            leftEye: eyePolygon(cx: 100, cy: 190, rx: 26, ry: 15),
            rightEye: eyePolygon(cx: 200, cy: 190, rx: 26, ry: 15),
            outerLips: eyePolygon(cx: 150, cy: 120, rx: 34, ry: 14),
            innerLips: [], nose: eyePolygon(cx: 150, cy: 155, rx: 10, ry: 18)
        )
        return DetectedFace(
            boundingBox: CGRect(x: 70, y: 80, width: 160, height: 160),
            faceCenter: CGPoint(x: 150, y: 160), faceWidth: 160, faceHeight: 160,
            leftPupilCenter: CGPoint(x: 100, y: 190), rightPupilCenter: CGPoint(x: 200, y: 190),
            leftEyeWidth: 52, rightEyeWidth: 52,
            leftEyebrowPoints: [CGPoint(x: 84, y: 208), CGPoint(x: 100, y: 210), CGPoint(x: 116, y: 208)],
            rightEyebrowPoints: [CGPoint(x: 184, y: 208), CGPoint(x: 200, y: 210), CGPoint(x: 216, y: 208)],
            faceContourPoints: [],
            normalizedBoundingBox: CGRect(x: 70.0 / 300, y: 80.0 / 300, width: 160.0 / 300, height: 160.0 / 300),
            regions: regions, landmarkQuality: .precise
        )
    }

    /// No region polygons, but pupils + eye width (the eye fallback path).
    private func makePupilOnlyFace() -> DetectedFace {
        DetectedFace(
            boundingBox: CGRect(x: 70, y: 80, width: 160, height: 160),
            faceCenter: CGPoint(x: 150, y: 160), faceWidth: 160, faceHeight: 160,
            leftPupilCenter: CGPoint(x: 100, y: 190), rightPupilCenter: CGPoint(x: 200, y: 190),
            leftEyeWidth: 52, rightEyeWidth: 52,
            leftEyebrowPoints: [], rightEyebrowPoints: [], faceContourPoints: [],
            normalizedBoundingBox: CGRect(x: 70.0 / 300, y: 80.0 / 300, width: 160.0 / 300, height: 160.0 / 300)
        )
    }

    /// No regions, no pupils — nothing to copy.
    private func makeBareFace() -> DetectedFace {
        DetectedFace(
            boundingBox: CGRect(x: 70, y: 80, width: 160, height: 160),
            faceCenter: CGPoint(x: 150, y: 160), faceWidth: 160, faceHeight: 160,
            leftPupilCenter: nil, rightPupilCenter: nil, leftEyeWidth: 0, rightEyeWidth: 0,
            leftEyebrowPoints: [], rightEyebrowPoints: [], faceContourPoints: [],
            normalizedBoundingBox: CGRect(x: 70.0 / 300, y: 80.0 / 300, width: 160.0 / 300, height: 160.0 / 300)
        )
    }

    private func pixel(_ image: CIImage, x: CGFloat, y: CGFloat) -> (r: UInt8, g: UInt8, b: UInt8) {
        var px = [UInt8](repeating: 0, count: 4)
        ctx.render(image, toBitmap: &px, rowBytes: 4,
                   bounds: CGRect(x: x, y: y, width: 1, height: 1),
                   format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return (px[0], px[1], px[2])
    }

    private func isBackground(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool {
        abs(Int(p.r) - 128) < 25 && abs(Int(p.g) - 128) < 25 && abs(Int(p.b) - 128) < 25
    }

    // The forehead target: face-centre X, midway between brow line (y 210) and face top (y 240).
    private let forehead = CGPoint(x: 150, y: 225)

    // MARK: - Timeline

    @Test func beforeReveal_returnsInputUnchanged() {
        let input = makeFixture()
        let out = ThirdEyeEffect(size: 0.5).apply(to: input, face: makePreciseFace(), progress: 0.1, frameIndex: 0)
        #expect(out.extent == input.extent)
        #expect(isBackground(pixel(out, x: forehead.x, y: forehead.y)), "nothing placed yet")
    }

    @Test func fullProgress_preservesExtent() {
        let input = makeFixture()
        let out = ThirdEyeEffect(size: 0.5).apply(to: input, face: makePreciseFace(), progress: 1.0, frameIndex: 0)
        #expect(out.extent == input.extent)
    }

    @Test func fullProgress_placesTheThirdEyeOnTheForehead() {
        let input = makeFixture()
        let out = ThirdEyeEffect(size: 0.6).apply(to: input, face: makePreciseFace(), progress: 1.0, frameIndex: 0)
        #expect(!isBackground(pixel(out, x: forehead.x, y: forehead.y)), "the eye + light landed here")
    }

    @Test func emptyRegions_fallBackToPupil() {
        let input = makeFixture()
        let out = ThirdEyeEffect(size: 0.6).apply(to: input, face: makePupilOnlyFace(), progress: 1.0, frameIndex: 0)
        #expect(!isBackground(pixel(out, x: forehead.x, y: forehead.y)))
    }

    @Test func noEyeSource_isNoOp() {
        let input = makeFixture()
        let out = ThirdEyeEffect(size: 0.6).apply(to: input, face: makeBareFace(), progress: 1.0, frameIndex: 0)
        #expect(out.extent == input.extent)
        #expect(isBackground(pixel(out, x: forehead.x, y: forehead.y)))
    }

    /// THIRD EYE is an addition — the real eyes stay (the glow casts warm light on the left
    /// eye, raising red, so this checks it is still present via its dominant blue).
    @Test func realEyesRemainInPlace() {
        let input = makeFixture()
        let out = ThirdEyeEffect(size: 0.5).apply(to: input, face: makePreciseFace(), progress: 1.0, frameIndex: 0)
        #expect(pixel(out, x: 100, y: 190).b > 150, "the original left eye must remain")
    }

    /// The colour picker must actually tint the third eye. Compared *across* renders rather
    /// than within one: the warm ray glow lifts every channel at the eye, so absolute
    /// channel ordering in a single frame is not a reliable signal — but a blue eye must
    /// still be bluer than a red one at the same pixel, and vice versa.
    @Test func eyeColour_tintsTheThirdEye() {
        let input = makeFixture()
        let face = makePreciseFace()
        let blue = ThirdEyeEffect(size: 0.6, eyeColor: .blue).apply(to: input, face: face, progress: 1.0, frameIndex: 0)
        let red = ThirdEyeEffect(size: 0.6, eyeColor: .red).apply(to: input, face: face, progress: 1.0, frameIndex: 0)
        let pb = pixel(blue, x: forehead.x, y: forehead.y)
        let pr = pixel(red, x: forehead.x, y: forehead.y)
        #expect(pb.b > pr.b, "the blue eye must be bluer than the red one")
        #expect(pr.r > pb.r, "the red eye must be redder than the blue one")
    }

    // MARK: - FaceRegion resolution

    @Test func faceRegion_eyeBoundsComeFromPolygon() {
        let box = FaceRegion.leftEye.sourceBounds(in: makePreciseFace())
        #expect(box != nil)
        #expect(abs((box?.midX ?? 0) - 100) < 1)
        #expect(abs((box?.midY ?? 0) - 190) < 1)
    }

    @Test func faceRegion_eyeFallsBackToPupilBox() {
        let face = makePupilOnlyFace()
        #expect(FaceRegion.leftEye.isAvailable(in: face))
        #expect(abs((FaceRegion.leftEye.sourceBounds(in: face)?.midX ?? 0) - 100) < 1)
    }

    // MARK: - Compositor primitives

    @Test func compositor_fillRegionCoversTheOriginalFeature() {
        let input = makeFixture()
        let green = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 1)).clampedToExtent()
        let out = FaceRegionCompositor().fillRegion(
            .leftEye, in: makePreciseFace(), with: green, over: input,
            padding: 0.55, feather: 0.3, opacity: 1.0)
        let p = pixel(out, x: 100, y: 190)
        #expect(p.g > 180 && p.r < 90 && p.b < 90, "left eye should be green-filled")
    }

    @Test func compositor_placesSampledPixelsAtDestination() {
        let input = makeFixture()
        let placement = FaceRegionPlacement(region: .leftEye, destinationCenter: forehead, scale: 1)
        let out = FaceRegionCompositor().composite(
            placement, source: input, over: input, face: makePreciseFace(), padding: 0.3, feather: 0.5)
        let p = pixel(out, x: forehead.x, y: forehead.y)
        #expect(p.g > 150 && p.b > 150 && p.r < 120, "cyan eye copied to the forehead")
    }

    // MARK: - Model scaling

    @Test func faceRegions_scaledScalesEveryArray() {
        let regions = FaceRegions(
            leftEye: [CGPoint(x: 10, y: 20)], rightEye: [CGPoint(x: 30, y: 40)],
            outerLips: [CGPoint(x: 50, y: 60)], innerLips: [CGPoint(x: 70, y: 80)],
            nose: [CGPoint(x: 90, y: 100)])
        let s = regions.scaled(x: 2, y: 3)
        #expect(s.leftEye == [CGPoint(x: 20, y: 60)])
        #expect(s.nose == [CGPoint(x: 180, y: 300)])
    }

    @Test func detectedFace_scaledCarriesRegionsAndQuality() {
        let scaled = makePreciseFace().scaled(x: 0.5, y: 0.5)
        #expect(scaled.landmarkQuality == .precise)
        #expect(abs((FaceRegion.leftEye.sourceBounds(in: scaled)?.midX ?? 0) - 50) < 1)
    }
}
