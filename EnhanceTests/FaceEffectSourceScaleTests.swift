import Testing
import UIKit
import CoreGraphics
@testable import Enhance

/// The rule that decides how much of a source image the face-effect pass keeps.
///
/// Face effects are the only part of the generator that re-renders a whole image per frame, so
/// this scale is the difference between rendering ~28× more pixels than the output can show and
/// rendering just enough. Continuous speed made it matter more: the frame count now reaches 100.
struct FaceEffectSourceScaleTests {

    private let output: CGFloat = 600

    /// fillScale for a source laid into a square output, matching `calculateDrawRect`.
    private func fillScale(_ size: CGSize) -> CGFloat {
        max(output / size.width, output / size.height)
    }

    // MARK: - Never makes things worse

    /// A source smaller than the output must be left alone. Upscaling it would cost more and
    /// add nothing, and it is the case where a naive `fillScale * zoom` would exceed 1.
    @Test func scale_neverUpscales() {
        let small = CGSize(width: 200, height: 200)
        for zoom in [CGFloat(1), 2, 4, 50] {
            let s = GIFGenerator.faceEffectSourceScale(fillScale: fillScale(small), maxZoom: zoom)
            #expect(s == 1.0, "zoom \(zoom) produced \(s)")
        }
    }

    @Test func scale_withDegenerateInput_isIdentity() {
        #expect(GIFGenerator.faceEffectSourceScale(fillScale: 0, maxZoom: 2) == 1)
        #expect(GIFGenerator.faceEffectSourceScale(fillScale: 0.2, maxZoom: 0) == 1)
        #expect(GIFGenerator.faceEffectSourceScale(fillScale: -1, maxZoom: 2) == 1)
    }

    @Test func scale_isAlwaysInUsableRange() {
        for w in [CGFloat(100), 600, 1200, 4032, 8000] {
            for zoom in [CGFloat(1), 1.5, 3, 50] {
                let s = GIFGenerator.faceEffectSourceScale(
                    fillScale: fillScale(CGSize(width: w, height: w * 0.75)), maxZoom: zoom
                )
                #expect(s > 0 && s <= 1, "w=\(w) zoom=\(zoom) → \(s)")
            }
        }
    }

    // MARK: - Keeps what the zoom can reveal

    /// The load-bearing property: whatever the zoom can magnify to must survive. At zoom `z`
    /// the output shows 1/z of the drawn image across `output` pixels, so the source needs
    /// `drawRect.width * z` pixels — and the retained width must be at least that.
    @Test func scale_retainsEveryPixelTheZoomCanReveal() {
        let source = CGSize(width: 4032, height: 3024)
        let fs = fillScale(source)
        let drawnWidth = source.width * fs

        for zoom in [CGFloat(1), 1.5, 2, 3, 4] {
            let s = GIFGenerator.faceEffectSourceScale(fillScale: fs, maxZoom: zoom)
            let retained = source.width * s
            let needed = drawnWidth * zoom
            #expect(retained >= needed - 0.001,
                    "zoom \(zoom): kept \(retained)px but the zoom can reveal \(needed)px")
        }
    }

    /// A 12MP photo at zoom 1 into a 600² output. The whole point of the change.
    @Test func scale_onATypicalPhotoAtNoZoom_cutsPixelsDramatically() {
        let source = CGSize(width: 4032, height: 3024)
        let s = GIFGenerator.faceEffectSourceScale(fillScale: fillScale(source), maxZoom: 1)

        let before = source.width * source.height
        let after = (source.width * s) * (source.height * s)
        let ratio = before / after

        #expect(ratio > 20, "expected a >20x pixel reduction, got \(ratio)x")
        // Still covers the drawn region exactly — 600/3024 * 4032 = 800px wide.
        #expect(abs(source.width * s - 800) < 1, "kept \(source.width * s)px, expected 800")
    }

    @Test func scale_growsWithZoom() {
        let fs = fillScale(CGSize(width: 4032, height: 3024))
        var previous = GIFGenerator.faceEffectSourceScale(fillScale: fs, maxZoom: 1)
        for zoom in [CGFloat(1.5), 2, 2.5, 3] {
            let s = GIFGenerator.faceEffectSourceScale(fillScale: fs, maxZoom: zoom)
            #expect(s > previous, "zoom \(zoom) did not increase the retained scale")
            previous = s
        }
    }

    /// Past the point where the generator is already upsampling, there is nothing left to trim.
    @Test func scale_saturatesAtOneOnceUpsampling() {
        let fs = fillScale(CGSize(width: 4032, height: 3024))   // 0.1984
        #expect(GIFGenerator.faceEffectSourceScale(fillScale: fs, maxZoom: 5) < 1)
        #expect(GIFGenerator.faceEffectSourceScale(fillScale: fs, maxZoom: 6) == 1)
    }
}
