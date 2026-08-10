import Testing
import CoreImage
import UIKit
@testable import Enhance

/// Correctness invariants for Feature Scrambler V1 (THIRD EYE) and its reusable compositor.
/// These guard extent preservation, timeline no-ops, missing-landmark safety, region
/// resolution, and coordinate scaling — not appearance, which is judged on device.
struct FeatureScramblerTests {

    private let ctx = CIContext(options: [.useSoftwareRenderer: true])
    private let bg: CGFloat = 128  // mid-grey background level

    // MARK: - Fixtures

    /// A 300x300 face-like fixture in CIImage space (bottom-left origin). The left eye is a
    /// distinctive pure cyan blob so a copy elsewhere is detectable by pixel, not by eye.
    private func makeFixture() -> CIImage {
        let size = CGSize(width: 300, height: 300)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        let g = UIGraphicsGetCurrentContext()!
        g.setFillColor(UIColor(white: bg / 255, alpha: 1).cgColor)
        g.fill(CGRect(origin: .zero, size: size))
        // Left eye (cyan) at CIImage (100,190): flip y for the top-left UIGraphics context.
        g.setFillColor(UIColor(red: 0, green: 1, blue: 1, alpha: 1).cgColor)
        g.fillEllipse(in: CGRect(x: 100 - 26, y: (300 - 190) - 15, width: 52, height: 30))
        let ui = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return CIImage(cgImage: ui.cgImage!)
    }

    private func eyePolygon(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat) -> [CGPoint] {
        (0..<12).map { i in
            let a = CGFloat(i) / 12 * 2 * .pi
            return CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a))
        }
    }

    /// Face centred in 300x300 with precise eye + lip regions and matching pupils.
    private func makePreciseFace() -> DetectedFace {
        let regions = FaceRegions(
            leftEye: eyePolygon(cx: 100, cy: 190, rx: 26, ry: 15),
            rightEye: eyePolygon(cx: 200, cy: 190, rx: 26, ry: 15),
            outerLips: eyePolygon(cx: 150, cy: 120, rx: 34, ry: 14),
            innerLips: [], nose: []
        )
        return DetectedFace(
            boundingBox: CGRect(x: 70, y: 80, width: 160, height: 160),
            faceCenter: CGPoint(x: 150, y: 160),
            faceWidth: 160, faceHeight: 160,
            leftPupilCenter: CGPoint(x: 100, y: 190), rightPupilCenter: CGPoint(x: 200, y: 190),
            leftEyeWidth: 52, rightEyeWidth: 52,
            leftEyebrowPoints: [CGPoint(x: 84, y: 208), CGPoint(x: 100, y: 210), CGPoint(x: 116, y: 208)],
            rightEyebrowPoints: [CGPoint(x: 184, y: 208), CGPoint(x: 200, y: 210), CGPoint(x: 216, y: 208)],
            faceContourPoints: [],
            normalizedBoundingBox: CGRect(x: 70.0 / 300, y: 80.0 / 300, width: 160.0 / 300, height: 160.0 / 300),
            regions: regions, landmarkQuality: .precise
        )
    }

    /// Estimated face: no region polygons, but pupils + eye width present (the eye fallback).
    private func makePupilOnlyFace() -> DetectedFace {
        DetectedFace(
            boundingBox: CGRect(x: 70, y: 80, width: 160, height: 160),
            faceCenter: CGPoint(x: 150, y: 160),
            faceWidth: 160, faceHeight: 160,
            leftPupilCenter: CGPoint(x: 100, y: 190), rightPupilCenter: CGPoint(x: 200, y: 190),
            leftEyeWidth: 52, rightEyeWidth: 52,
            leftEyebrowPoints: [], rightEyebrowPoints: [],
            faceContourPoints: [],
            normalizedBoundingBox: CGRect(x: 70.0 / 300, y: 80.0 / 300, width: 160.0 / 300, height: 160.0 / 300)
        )
    }

    /// Bare face: no regions, no pupils, no eye width — nothing to copy.
    private func makeBareFace() -> DetectedFace {
        DetectedFace(
            boundingBox: CGRect(x: 70, y: 80, width: 160, height: 160),
            faceCenter: CGPoint(x: 150, y: 160),
            faceWidth: 160, faceHeight: 160,
            leftPupilCenter: nil, rightPupilCenter: nil,
            leftEyeWidth: 0, rightEyeWidth: 0,
            leftEyebrowPoints: [], rightEyebrowPoints: [],
            faceContourPoints: [],
            normalizedBoundingBox: CGRect(x: 70.0 / 300, y: 80.0 / 300, width: 160.0 / 300, height: 160.0 / 300)
        )
    }

    /// Read one RGBA pixel at a CIImage-space point.
    private func pixel(_ image: CIImage, x: CGFloat, y: CGFloat) -> (r: UInt8, g: UInt8, b: UInt8) {
        var px = [UInt8](repeating: 0, count: 4)
        ctx.render(image, toBitmap: &px, rowBytes: 4,
                   bounds: CGRect(x: x, y: y, width: 1, height: 1),
                   format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return (px[0], px[1], px[2])
    }

    private func isCyanish(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool {
        p.g > 150 && p.b > 150 && p.r < 120
    }

    private func isBackground(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool {
        abs(Int(p.r) - 128) < 25 && abs(Int(p.g) - 128) < 25 && abs(Int(p.b) - 128) < 25
    }

    // The forehead target the effect computes: face-centre X, midway between brow line and
    // the top of the face box. For makePreciseFace: browTopY = 210, faceTopY = 240 → y = 225.
    private let forehead = CGPoint(x: 150, y: 225)

    // MARK: - Timeline

    @Test func beforeReveal_returnsInputUnchanged() {
        let input = makeFixture()
        let out = FeatureScramblerEffect(size: 0.5, intensity: 0.8)
            .apply(to: input, face: makePreciseFace(), progress: 0.1, frameIndex: 0)
        #expect(out.extent == input.extent)
        // The forehead is still background — nothing has been copied yet.
        #expect(isBackground(pixel(out, x: forehead.x, y: forehead.y)))
    }

    @Test func fullProgress_preservesExtent() {
        let input = makeFixture()
        let out = FeatureScramblerEffect(size: 0.5, intensity: 0.8)
            .apply(to: input, face: makePreciseFace(), progress: 1.0, frameIndex: 0)
        #expect(out.extent == input.extent)
    }

    @Test func fullProgress_copiesEyeToForehead() {
        let input = makeFixture()
        let out = FeatureScramblerEffect(size: 0.6, intensity: 0.9)
            .apply(to: input, face: makePreciseFace(), progress: 1.0, frameIndex: 0)
        // The cyan left eye now sits on the forehead.
        #expect(isCyanish(pixel(out, x: forehead.x, y: forehead.y)))
    }

    @Test func emptyRegions_fallBackToPupil() {
        let input = makeFixture()
        let out = FeatureScramblerEffect(size: 0.6, intensity: 0.9)
            .apply(to: input, face: makePupilOnlyFace(), progress: 1.0, frameIndex: 0)
        // No polygon, but the pupil + eye width still resolve a source box to copy.
        #expect(isCyanish(pixel(out, x: forehead.x, y: forehead.y)))
    }

    @Test func noEyeSource_isNoOp() {
        let input = makeFixture()
        let out = FeatureScramblerEffect(size: 0.6, intensity: 0.9)
            .apply(to: input, face: makeBareFace(), progress: 1.0, frameIndex: 0)
        #expect(out.extent == input.extent)
        #expect(isBackground(pixel(out, x: forehead.x, y: forehead.y)))
    }

    @Test func zeroIntensity_isIdenticalToInput() {
        let input = makeFixture()
        let out = FeatureScramblerEffect(size: 0.6, intensity: 0.0)
            .apply(to: input, face: makePreciseFace(), progress: 1.0, frameIndex: 0)
        #expect(out.extent == input.extent)
        #expect(isBackground(pixel(out, x: forehead.x, y: forehead.y)))
    }

    // MARK: - FaceRegion resolution

    @Test func faceRegion_eyeBoundsComeFromPolygon() {
        let face = makePreciseFace()
        let box = FaceRegion.leftEye.sourceBounds(in: face)
        #expect(box != nil)
        // Centre of the eye polygon is (100, 190).
        #expect(abs((box?.midX ?? 0) - 100) < 1)
        #expect(abs((box?.midY ?? 0) - 190) < 1)
    }

    @Test func faceRegion_eyeFallsBackToPupilBox() {
        let face = makePupilOnlyFace()
        #expect(FaceRegion.leftEye.isAvailable(in: face))
        let box = FaceRegion.leftEye.sourceBounds(in: face)
        #expect(abs((box?.midX ?? 0) - 100) < 1)
        #expect((box?.width ?? 0) > 0)
    }

    @Test func faceRegion_mouthUnavailableWithoutLips() {
        #expect(!FaceRegion.mouth.isAvailable(in: makePupilOnlyFace()))
        #expect(!FaceRegion.mouth.isAvailable(in: makeBareFace()))
    }

    @Test func faceRegion_mouthAvailableWithLips() {
        #expect(FaceRegion.mouth.isAvailable(in: makePreciseFace()))
    }

    // MARK: - Compositor safety

    @Test func compositor_unavailableRegionReturnsBackground() {
        let input = makeFixture()
        let placement = FaceRegionPlacement(region: .mouth, destinationCenter: forehead, scale: 1)
        let out = FaceRegionCompositor().composite(
            placement, source: input, over: input, face: makeBareFace(), padding: 0.3, feather: 0.5
        )
        #expect(out.extent == input.extent)
        #expect(isBackground(pixel(out, x: forehead.x, y: forehead.y)))
    }

    @Test func compositor_placesSampledPixelsAtDestination() {
        let input = makeFixture()
        let placement = FaceRegionPlacement(region: .leftEye, destinationCenter: forehead, scale: 1)
        let out = FaceRegionCompositor().composite(
            placement, source: input, over: input, face: makePreciseFace(), padding: 0.3, feather: 0.5
        )
        #expect(isCyanish(pixel(out, x: forehead.x, y: forehead.y)))
    }

    // MARK: - Model scaling

    @Test func faceRegions_scaledScalesEveryArray() {
        let regions = FaceRegions(
            leftEye: [CGPoint(x: 10, y: 20)], rightEye: [CGPoint(x: 30, y: 40)],
            outerLips: [CGPoint(x: 50, y: 60)], innerLips: [CGPoint(x: 70, y: 80)],
            nose: [CGPoint(x: 90, y: 100)]
        )
        let s = regions.scaled(x: 2, y: 3)
        #expect(s.leftEye == [CGPoint(x: 20, y: 60)])
        #expect(s.rightEye == [CGPoint(x: 60, y: 120)])
        #expect(s.outerLips == [CGPoint(x: 100, y: 180)])
        #expect(s.innerLips == [CGPoint(x: 140, y: 240)])
        #expect(s.nose == [CGPoint(x: 180, y: 300)])
    }

    @Test func detectedFace_scaledCarriesRegionsAndQuality() {
        let face = makePreciseFace()
        let scaled = face.scaled(x: 0.5, y: 0.5)
        #expect(scaled.landmarkQuality == .precise)
        // Left-eye centre 100,190 → 50,95 after half scale.
        let box = FaceRegion.leftEye.sourceBounds(in: scaled)
        #expect(abs((box?.midX ?? 0) - 50) < 1)
        #expect(abs((box?.midY ?? 0) - 95) < 1)
    }

    /// Guards the "a future region field cannot be forgotten in scaled()" concern: every
    /// stored region point must move under scaling.
    @Test func detectedFace_scaledMovesEveryRegionPoint() {
        let face = makePreciseFace()
        let scaled = face.scaled(x: 2, y: 2)
        func doubled(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
            a.count == b.count && zip(a, b).allSatisfy { abs($0.x * 2 - $1.x) < 0.001 && abs($0.y * 2 - $1.y) < 0.001 }
        }
        #expect(doubled(face.regions.leftEye, scaled.regions.leftEye))
        #expect(doubled(face.regions.rightEye, scaled.regions.rightEye))
        #expect(doubled(face.regions.outerLips, scaled.regions.outerLips))
    }
}
