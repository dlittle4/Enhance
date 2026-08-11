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
            innerLips: [], nose: eyePolygon(cx: 150, cy: 155, rx: 10, ry: 18)
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

    // MARK: - Stage E layouts

    /// One eye (left) plus a precise mouth — the case that allows EYE MOUTH but not swaps.
    private func makeOneEyeMouthFace() -> DetectedFace {
        let regions = FaceRegions(
            leftEye: eyePolygon(cx: 100, cy: 190, rx: 26, ry: 15),
            rightEye: [], outerLips: eyePolygon(cx: 150, cy: 120, rx: 34, ry: 14),
            innerLips: [], nose: []
        )
        return DetectedFace(
            boundingBox: CGRect(x: 70, y: 80, width: 160, height: 160),
            faceCenter: CGPoint(x: 150, y: 160), faceWidth: 160, faceHeight: 160,
            leftPupilCenter: CGPoint(x: 100, y: 190), rightPupilCenter: nil,
            leftEyeWidth: 52, rightEyeWidth: 0,
            leftEyebrowPoints: [], rightEyebrowPoints: [], faceContourPoints: [],
            normalizedBoundingBox: CGRect(x: 70.0 / 300, y: 80.0 / 300, width: 160.0 / 300, height: 160.0 / 300),
            regions: regions, landmarkQuality: .precise
        )
    }

    @Test func layoutAvailability_preciseFaceSupportsAll() {
        let face = makePreciseFace()
        for layout in ScrambleLayout.allCases {
            #expect(layout.isAvailable(for: face), "\(layout.rawValue) should be available")
        }
    }

    @Test func layoutAvailability_noLipsOffersOnlyThirdEye() {
        let face = makePupilOnlyFace()  // pupils but no lip polygon
        #expect(ScrambleLayout.thirdEye.isAvailable(for: face))
        #expect(!ScrambleLayout.eyeMouth.isAvailable(for: face))
        #expect(!ScrambleLayout.mouthEyes.isAvailable(for: face))
        #expect(!ScrambleLayout.shuffle.isAvailable(for: face))
    }

    @Test func layoutAvailability_oneEyePlusMouthAllowsEyeMouthNotSwaps() {
        let face = makeOneEyeMouthFace()  // one eye, mouth, no nose
        #expect(ScrambleLayout.thirdEye.isAvailable(for: face))
        #expect(ScrambleLayout.eyeMouth.isAvailable(for: face))
        #expect(!ScrambleLayout.mouthEyes.isAvailable(for: face), "needs both eyes")
        #expect(!ScrambleLayout.shuffle.isAvailable(for: face), "needs both eyes and a nose")
        #expect(!ScrambleLayout.noseSwap.isAvailable(for: face), "needs a nose")
    }

    @Test func placements_countMatchesLayout() {
        let face = makePreciseFace()
        #expect(ScrambleLayout.thirdEye.placements(for: face, size: 0.5).count == 1)
        #expect(ScrambleLayout.eyeMouth.placements(for: face, size: 0.5).count == 1)
        #expect(ScrambleLayout.noseSwap.placements(for: face, size: 0.5).count == 2)
        #expect(ScrambleLayout.mouthEyes.placements(for: face, size: 0.5).count == 2)
        #expect(ScrambleLayout.shuffle.placements(for: face, size: 0.5).count == 4)
    }

    @Test func placements_emptyWhenLayoutUnavailable() {
        #expect(ScrambleLayout.mouthEyes.placements(for: makePupilOnlyFace(), size: 0.5).isEmpty)
    }

    @Test func effect_everyLayoutPreservesExtent() {
        let input = makeFixture()
        for layout in ScrambleLayout.allCases {
            let out = FeatureScramblerEffect(size: 0.5, intensity: 0.9, layout: layout)
                .apply(to: input, face: makePreciseFace(), progress: 1.0, frameIndex: 0)
            #expect(out.extent == input.extent, "\(layout.rawValue) extent")
        }
    }

    @Test func effect_mouthEyesCopiesMouthOntoEyes() {
        let input = makeFixture()
        let out = FeatureScramblerEffect(size: 0.5, intensity: 0.95, layout: .mouthEyes)
            .apply(to: input, face: makePreciseFace(), progress: 1.0, frameIndex: 0)
        // The mouth is dark/reddish (low green, low blue) — the eye it lands on stops being cyan.
        #expect(!isCyanish(pixel(out, x: 100, y: 190)))
    }

    @Test func effect_unavailableLayoutIsNoOp() {
        let input = makeFixture()
        // MOUTH EYES on a face with no lips has no placements → original image untouched.
        let out = FeatureScramblerEffect(size: 0.5, intensity: 0.9, layout: .mouthEyes)
            .apply(to: input, face: makePupilOnlyFace(), progress: 1.0, frameIndex: 0)
        #expect(out.extent == input.extent)
        #expect(isCyanish(pixel(out, x: 100, y: 190)), "left eye must be untouched")
    }

    // MARK: - Skin heal

    @Test func healRegions_matchWhatEachLayoutReplaces() {
        #expect(ScrambleLayout.thirdEye.healRegions().isEmpty)
        #expect(ScrambleLayout.eyeMouth.healRegions() == [.mouth])
        #expect(ScrambleLayout.noseSwap.healRegions() == [.nose, .mouth])
        #expect(ScrambleLayout.mouthEyes.healRegions().count == 2)
        #expect(ScrambleLayout.shuffle.healRegions().count == 4)
    }

    @Test func compositor_fillRegionCoversTheOriginalFeature() {
        let input = makeFixture()
        let green = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 1)).clampedToExtent()
        let out = FaceRegionCompositor().fillRegion(
            .leftEye, in: makePreciseFace(), with: green, over: input,
            padding: 0.55, feather: 0.3, opacity: 1.0
        )
        let p = pixel(out, x: 100, y: 190)
        #expect(p.g > 180 && p.r < 90 && p.b < 90, "left eye should be green-filled")
        #expect(!isCyanish(p))
    }

    @Test func compositor_fillRegionZeroOpacityIsNoOp() {
        let input = makeFixture()
        let green = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 1)).clampedToExtent()
        let out = FaceRegionCompositor().fillRegion(
            .leftEye, in: makePreciseFace(), with: green, over: input,
            padding: 0.55, feather: 0.3, opacity: 0.0
        )
        #expect(isCyanish(pixel(out, x: 100, y: 190)), "zero-opacity heal leaves the eye")
    }

    /// THIRD EYE keeps the real eyes — it heals nothing, so the source eye stays put while a
    /// copy also appears on the forehead.
    @Test func thirdEye_leavesTheSourceEyeInPlace() {
        let input = makeFixture()
        let out = FeatureScramblerEffect(size: 0.5, intensity: 0.9, layout: .thirdEye)
            .apply(to: input, face: makePreciseFace(), progress: 1.0, frameIndex: 0)
        #expect(isCyanish(pixel(out, x: 100, y: 190)), "the original left eye must remain")
    }

    @Test func thirdEye_growsInPlaceWithGlow() {
        let specs = ScrambleLayout.thirdEye.placements(for: makePreciseFace(), size: 0.5)
        #expect(specs.count == 1)
        let spec = specs[0]
        #expect(spec.glows)
        #expect(spec.startScaleFraction == 0, "grows from nothing")
        #expect(spec.sourceCenter == spec.destination, "grows in place, does not travel")
    }

    @Test func swapLayouts_travelAndDoNotGlow() {
        let specs = ScrambleLayout.shuffle.placements(for: makePreciseFace(), size: 0.5)
        #expect(!specs.isEmpty)
        #expect(specs.allSatisfy { !$0.glows })
        #expect(specs.contains { $0.sourceCenter != $0.destination }, "a swap travels")
    }
}
