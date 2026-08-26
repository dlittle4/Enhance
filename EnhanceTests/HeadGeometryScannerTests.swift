import Testing
import CoreImage
import UIKit
@testable import Enhance

/// The scanner runs pure Core Image + CPU row counting, so unlike segmentation it is fully
/// exercisable in the Simulator — a synthetic silhouette with a known neck is the ground truth
/// no real photo can provide.
struct HeadGeometryScannerTests {

    private let context = CIContext(options: [.useSoftwareRenderer: true])

    /// A 400×400 silhouette: head (rows 240…360, width 120), neck (rows 200…240, width 40),
    /// shoulders (rows 80…200, width 300). y-up: shoulders low, head high.
    private func makeSilhouette() -> CIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 400, height: 400), true, 1)
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        ctx.setFillColor(UIColor.white.cgColor)
        // UIKit is y-down: head at top.
        ctx.fill(CGRect(x: 140, y: 40, width: 120, height: 120))   // head: image y 240…360
        ctx.fill(CGRect(x: 180, y: 160, width: 40, height: 40))    // neck: image y 200…240
        ctx.fill(CGRect(x: 50, y: 200, width: 300, height: 120))   // shoulders: image y 80…200
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return CIImage(cgImage: image.cgImage!)
    }

    /// A face sitting in the head block: centre (200, 290), 100×100.
    private func makeFace() -> DetectedFace {
        DetectedFace(
            boundingBox: CGRect(x: 150, y: 240, width: 100, height: 100),
            faceCenter: CGPoint(x: 200, y: 290),
            faceWidth: 100, faceHeight: 100,
            leftPupilCenter: nil, rightPupilCenter: nil,
            leftEyeWidth: 0, rightEyeWidth: 0,
            leftEyebrowPoints: [], rightEyebrowPoints: [],
            faceContourPoints: [],
            normalizedBoundingBox: CGRect(x: 0.375, y: 0.6, width: 0.25, height: 0.25)
        )
    }

    @Test func findsTheNeckAtTheNarrowestRow() {
        let derived = HeadGeometryScanner.scan(
            mask: makeSilhouette(), face: makeFace(), context: context
        )
        let neckY = try! #require(derived.neckNormY) * 400
        // The narrowest rows span image y 200…240; the chin sits at 240. Anywhere inside the
        // pinch counts — the scan resolution quantises within it.
        #expect(neckY > 190 && neckY < 245)
    }

    @Test func findsTheCrownAtTheTopOfTheHead() {
        let derived = HeadGeometryScanner.scan(
            mask: makeSilhouette(), face: makeFace(), context: context
        )
        let crownY = try! #require(derived.crownNormY) * 400
        // Head top is image y 360.
        #expect(crownY > 345 && crownY < 375)
    }

    /// A straight column has no pinch — the scanner must return nil rather than inventing a
    /// neck, because a false neck cuts a real head.
    @Test func straightSilhouette_findsNoNeck() {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 400, height: 400), true, 1)
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 140, y: 40, width: 120, height: 320))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        let column = CIImage(cgImage: image.cgImage!)

        let derived = HeadGeometryScanner.scan(mask: column, face: makeFace(), context: context)
        #expect(derived.neckNormY == nil)
    }

    @Test func emptyMask_returnsNothing() {
        let empty = CIImage(color: CIColor(red: 0, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 400, height: 400))
        let derived = HeadGeometryScanner.scan(mask: empty, face: makeFace(), context: context)
        #expect(derived.neckNormY == nil)
        #expect(derived.crownNormY == nil)
    }
}
