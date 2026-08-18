import Testing
import CoreImage
import UIKit
@testable import Enhance

/// Tests for `SubjectMaskCompositor` — the shared half of the §2f subject-mask effects.
///
/// The load-bearing case is **geometry**: the mask is produced in the source photo's pixel
/// space, while effects run on a frame that has already been aspect-filled and zoomed. If that
/// mapping is wrong the cutout slides off the subject as the animation pans, and it would look
/// like a segmentation failure rather than a transform one. So these render real pixels and
/// check *where* the split lands, not merely that a graph came back.
struct SubjectMaskCompositorTests {

    private let ctx = CIContext(options: [.useSoftwareRenderer: true])
    private let compositor = SubjectMaskCompositor()

    private func solid(_ color: CIColor, side: CGFloat) -> CIImage {
        CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
    }

    /// A mask whose left half is subject (white) and right half background (black).
    private func leftHalfMask(side: CGFloat) -> CIImage {
        let white = CIImage(color: .white)
            .cropped(to: CGRect(x: 0, y: 0, width: side / 2, height: side))
        let black = CIImage(color: .black)
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        return white.composited(over: black).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
    }

    /// RGBA of one pixel, sampled with a bottom-left origin to match CIImage coordinates.
    private func pixel(_ image: CIImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var buf = [UInt8](repeating: 0, count: 4)
        ctx.render(image, toBitmap: &buf, rowBytes: 4,
                   bounds: CGRect(x: x, y: y, width: 1, height: 1),
                   format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return (buf[0], buf[1], buf[2], buf[3])
    }

    private func isRed(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
        p.r > 200 && p.g < 60 && p.b < 60
    }

    private func isBlue(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
        p.b > 200 && p.r < 60 && p.g < 60
    }

    // MARK: - No mask degrades to identity

    /// ROADMAP §1g: the editor keeps cards live on a photo with no subject, so every effect
    /// built on this must return the frame untouched rather than render something broken.
    @Test func subject_withoutMask_returnsFrameUnchanged() {
        let frame = solid(.red, side: 32)
        let out = compositor.subject(of: frame, over: solid(.blue, side: 32),
                                     mask: nil, geometry: .identity)
        #expect(isRed(pixel(out, x: 16, y: 16)))
    }

    @Test func cutout_withoutMask_returnsNil() {
        #expect(compositor.cutout(of: solid(.red, side: 32), mask: nil, geometry: .identity) == nil)
    }

    /// The effect must not run at all when there is no mask — otherwise a photo with no
    /// subject would show the effect applied to the whole frame, which is a different effect.
    @Test func applyingToBackground_withoutMask_leavesFrameUntouched() {
        let frame = solid(.red, side: 32)
        let out = compositor.applyingToBackground(
            InversionEffect(), of: frame, mask: nil, progress: 1.0, frameIndex: 0
        )
        #expect(isRed(pixel(out, x: 16, y: 16)))
    }

    // MARK: - Geometry — the case that fails silently

    /// Identity geometry: source and frame are the same space, which is the preview's path.
    @Test func identityGeometry_splitsWhereTheMaskSays() {
        let side: CGFloat = 64
        let out = compositor.subject(
            of: solid(.red, side: side), over: solid(.blue, side: side),
            mask: leftHalfMask(side: side), geometry: .identity
        )

        #expect(isRed(pixel(out, x: 16, y: 32)))   // left half → subject
        #expect(isBlue(pixel(out, x: 48, y: 32)))  // right half → background
    }

    /// A 32pt source aspect-filled into a 64pt frame. Without `contentScale` the mask would
    /// cover only the left quarter of the frame and the split would land at x=16 instead of
    /// x=32 — the drift this field exists to prevent.
    @Test func contentScale_stretchesTheMaskToTheFilledFrame() {
        let source: CGFloat = 32
        let frameSide: CGFloat = 64
        let geometry = FrameGeometry(scale: 1.0, contentOrigin: .zero, contentScale: 2.0)

        let out = compositor.subject(
            of: solid(.red, side: frameSide), over: solid(.blue, side: frameSide),
            mask: leftHalfMask(side: source), geometry: geometry
        )

        #expect(isRed(pixel(out, x: 8, y: 32)))
        #expect(isRed(pixel(out, x: 28, y: 32)))   // still subject — would be background if contentScale were ignored
        #expect(isBlue(pixel(out, x: 40, y: 32)))
        #expect(isBlue(pixel(out, x: 56, y: 32)))
    }

    /// Zoom multiplies on top of the fill factor, and the origin shifts with the pan.
    @Test func zoomAndPan_moveTheSplitWithTheContent() {
        let frameSide: CGFloat = 64
        // Source 32pt, filled ×1 then zoomed ×2 → the 16pt mask boundary lands at 32pt,
        // then the pan pushes it a further 8pt right.
        let geometry = FrameGeometry(scale: 2.0,
                                     contentOrigin: CGPoint(x: 8, y: 0),
                                     contentScale: 1.0)

        let out = compositor.subject(
            of: solid(.red, side: frameSide), over: solid(.blue, side: frameSide),
            mask: leftHalfMask(side: 32), geometry: geometry
        )

        #expect(isRed(pixel(out, x: 32, y: 32)))   // just inside the boundary at 8 + 16*2 = 40
        #expect(isBlue(pixel(out, x: 48, y: 32)))
    }

    /// The mask is clamped before cropping, so a pan that carries the mask's edge inside the
    /// frame extends its border rather than exposing an untreated strip.
    @Test func maskIsClampedRatherThanLeavingAnUntreatedEdge() {
        let frameSide: CGFloat = 64
        let geometry = FrameGeometry(scale: 1.0,
                                     contentOrigin: CGPoint(x: 16, y: 0),
                                     contentScale: 1.0)

        let out = compositor.subject(
            of: solid(.red, side: frameSide), over: solid(.blue, side: frameSide),
            mask: leftHalfMask(side: 32), geometry: geometry
        )

        // x < 16 is outside the placed mask entirely; clamping extends the white edge, so it
        // reads as subject rather than as an abrupt untreated band.
        #expect(isRed(pixel(out, x: 4, y: 32)))
    }

    // MARK: - Degenerate input

    @Test func nonFiniteGeometry_returnsFrameUnchanged() {
        let frame = solid(.red, side: 32)
        let geometry = FrameGeometry(scale: .nan, contentOrigin: .zero, contentScale: 1.0)

        let out = compositor.subject(of: frame, over: solid(.blue, side: 32),
                                     mask: leftHalfMask(side: 32), geometry: geometry)
        #expect(isRed(pixel(out, x: 16, y: 16)))
    }

    @Test func zeroContentScale_returnsFrameUnchanged() {
        let frame = solid(.red, side: 32)
        let geometry = FrameGeometry(scale: 1.0, contentOrigin: .zero, contentScale: 0)

        let out = compositor.subject(of: frame, over: solid(.blue, side: 32),
                                     mask: leftHalfMask(side: 32), geometry: geometry)
        #expect(isRed(pixel(out, x: 16, y: 16)))
    }

    // MARK: - Cutout

    @Test func cutout_keepsSubjectAndClearsBackground() {
        let side: CGFloat = 64
        let out = compositor.cutout(of: solid(.red, side: side),
                                    mask: leftHalfMask(side: side), geometry: .identity)

        #expect(out != nil)
        #expect(isRed(pixel(out!, x: 16, y: 32)))
        #expect(pixel(out!, x: 48, y: 32).a < 20)
    }

    // MARK: - Laziness

    /// Mirrors `FaceRegionCompositor`'s contract — the graph must stay unevaluated so the
    /// caller's shared context renders once per frame.
    @Test func compositeStaysLazy() {
        let out = compositor.subject(of: solid(.red, side: 64), over: solid(.blue, side: 64),
                                     mask: leftHalfMask(side: 64), geometry: .identity)
        #expect(out.extent == CGRect(x: 0, y: 0, width: 64, height: 64))
    }
}
