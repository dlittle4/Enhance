import Testing
import CoreImage
import UIKit
import Vision
@testable import Enhance

/// Tests for `SubjectSegmentationService`.
///
/// **These inject a stub mask provider and never reach Vision, deliberately.**
/// `VNGenerateForegroundInstanceMaskRequest` throws on the iOS Simulator, so a test that
/// called the real path would not merely fail — it would *pass for the wrong reason*, since
/// a thrown error and a genuinely subjectless photo both surface as `nil` at the call site.
/// An earlier draft of this file did exactly that. What is asserted here is the contract the
/// service owns: caching, the absence-vs-failure distinction, and mask rescaling.
///
/// Mask *quality* is not testable here and is not attempted. Per EFFECTS.md a structural
/// test cannot see a wrong-looking effect; `Tools/segmentation-spike.swift` renders real
/// GIFs on real hardware, and that is what judged the mask (ROADMAP §1g).
struct SubjectSegmentationTests {

    private func makeImage(side: CGFloat = 64, color: UIColor = .gray) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: side, height: side), true, 1)
        color.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image
    }

    private func makeMask(side: CGFloat = 64) -> CIImage {
        CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
    }

    /// A service whose segmentation always finds a subject.
    private func serviceFindingSubject(maskSide: CGFloat = 64) -> SubjectSegmentationService {
        SubjectSegmentationService(maskProvider: { _, _ in self.makeMask(side: maskSide) })
    }

    /// A service whose segmentation never finds one.
    private func serviceFindingNothing() -> SubjectSegmentationService {
        SubjectSegmentationService(maskProvider: { _, _ in nil })
    }

    // MARK: - Absence is an answer, not an error

    @Test func noSubject_returnsNil() async {
        #expect(await serviceFindingNothing().subjectMask(for: makeImage()) == nil)
    }

    /// The editor asks this to decide whether to raise the "no subject" toast; the cards
    /// stay live regardless, matching how face effects handle a photo with no faces.
    @Test func noSubject_reportsFalseToTheEditor() async {
        #expect(await serviceFindingNothing().hasSubject(in: makeImage()) == false)
    }

    @Test func subjectPresent_reportsTrueToTheEditor() async {
        #expect(await serviceFindingSubject().hasSubject(in: makeImage()) == true)
    }

    // MARK: - Caching

    /// The absent case must be cached like any other — the one case where the cache matters
    /// most, because there is no mask to show for the work.
    @Test func noSubject_isCachedRatherThanRecomputed() async {
        let service = serviceFindingNothing()
        let image = makeImage()

        _ = await service.subjectMask(for: image)
        _ = await service.subjectMask(for: image)
        _ = await service.hasSubject(in: image)

        #expect(service.segmentationCount == 1)
    }

    @Test func subjectPresent_isCachedRatherThanRecomputed() async {
        let service = serviceFindingSubject()
        let image = makeImage()

        _ = await service.subjectMask(for: image)
        _ = await service.subjectMask(for: image)

        #expect(service.segmentationCount == 1)
    }

    @Test func clearCache_forcesRecomputation() async {
        let service = serviceFindingSubject()
        let image = makeImage()

        _ = await service.subjectMask(for: image)
        service.clearCache()
        _ = await service.subjectMask(for: image)

        #expect(service.segmentationCount == 2)
    }

    @Test func resegment_forcesRecomputation() async {
        let service = serviceFindingSubject()
        let image = makeImage()

        _ = await service.subjectMask(for: image)
        _ = await service.resegment(in: image)

        #expect(service.segmentationCount == 2)
    }

    @Test func differentImage_isNotServedFromCache() async {
        let service = serviceFindingSubject()

        _ = await service.subjectMask(for: makeImage(color: .gray))
        _ = await service.subjectMask(for: makeImage(side: 96, color: .blue))

        #expect(service.segmentationCount == 2)
    }

    // MARK: - Failure is not absence

    /// A caller that cannot tell these apart would tell the user "no subject" on a transient
    /// Vision error, so the distinction is part of the contract rather than a convenience.
    @Test func providerThrows_propagatesRatherThanReportingNoSubject() {
        struct Boom: Error {}
        let service = SubjectSegmentationService(maskProvider: { _, _ in throw Boom() })

        #expect(throws: Boom.self) {
            _ = try service.subjectMaskOrThrow(for: self.makeImage())
        }
    }

    /// A failure must not be cached as "no subject" — otherwise one transient error would
    /// mislabel that photo as subjectless for the rest of the session.
    @Test func providerThrows_doesNotPoisonTheCache() async {
        struct Boom: Error {}
        final class Gate: @unchecked Sendable { var shouldThrow = true }
        let gate = Gate()
        let service = SubjectSegmentationService(maskProvider: { _, _ in
            if gate.shouldThrow { throw Boom() }
            return self.makeMask()
        })
        let image = makeImage()

        _ = try? service.subjectMaskOrThrow(for: image)
        gate.shouldThrow = false

        #expect(await service.subjectMask(for: image) != nil)
    }

    @Test func imageWithoutCGImage_throws() {
        let service = serviceFindingSubject()
        let ciOnly = UIImage(ciImage: CIImage(color: .red).cropped(
            to: CGRect(x: 0, y: 0, width: 32, height: 32)
        ))

        #expect(throws: SubjectSegmentationService.Failure.self) {
            _ = try service.subjectMaskOrThrow(for: ciOnly)
        }
    }

    // MARK: - Geometry

    /// Vision can return the mask at its own working resolution. Rescaling here means each
    /// effect can blend against the image directly instead of repeating the check.
    @Test func maskIsRescaledToTheImage() async {
        let service = serviceFindingSubject(maskSide: 32)
        let mask = await service.subjectMask(for: makeImage(side: 128))

        #expect(mask?.extent.width == 128)
        #expect(mask?.extent.height == 128)
    }

    @Test func maskAlreadyMatchingTheImage_isLeftAlone() async {
        let service = serviceFindingSubject(maskSide: 64)
        let mask = await service.subjectMask(for: makeImage(side: 64))

        #expect(mask?.extent.width == 64)
    }

    // MARK: - Person masks

    private func stubSegmentation(
        masks: [Int: CIImage],
        labels: @escaping (CGPoint) -> Int
    ) -> SubjectSegmentationService.PersonSegmentation {
        SubjectSegmentationService.PersonSegmentation(masks: masks, labelAt: labels)
    }

    /// N points, one segmentation pass — the whole point of the per-photo cache.
    @Test func personMasks_runOnePassForManyPoints() async {
        var providerCalls = 0
        let mask = makeMask()
        let service = SubjectSegmentationService(
            maskProvider: { _, _ in nil },
            personProvider: { _, _ in
                providerCalls += 1
                return self.stubSegmentation(masks: [1: mask]) { _ in 1 }
            }
        )
        let image = makeImage()
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 30), CGPoint(x: 50, y: 50)]

        let first = await service.personMasks(for: image, at: points)
        let second = await service.personMasks(for: image, at: points)

        #expect(providerCalls == 1)
        #expect(first.count == 3)
        #expect(second.count == 3)
        #expect(first.allSatisfy { $0 != nil })
    }

    /// Alignment is positional, and a background (label 0) point yields nil — the caller owns
    /// the union fallback.
    @Test func personMasks_alignPositionally_andBackgroundIsNil() async {
        let maskA = makeMask(side: 32)
        let maskB = makeMask(side: 48)
        let service = SubjectSegmentationService(
            maskProvider: { _, _ in nil },
            personProvider: { _, _ in
                // Left half of the buffer is instance 1, right half instance 2, a background
                // stripe at the very top (normalized y < 0.1 — remember y is DOWN here).
                self.stubSegmentation(masks: [1: maskA, 2: maskB]) { p in
                    if p.y < 0.1 { return 0 }
                    return p.x < 0.5 ? 1 : 2
                }
            }
        )
        let image = makeImage()   // 64×64
        let results = await service.personMasks(for: image, at: [
            CGPoint(x: 16, y: 32),   // left → instance 1
            CGPoint(x: 48, y: 32),   // right → instance 2
            CGPoint(x: 32, y: 62)    // near the top in y-up = top stripe in buffer → background
        ])

        #expect(results.count == 3)
        #expect(results[0]?.extent.width == 64)   // maskA rescaled to the image
        #expect(results[1] != nil)
        #expect(results[2] == nil)
    }

    /// The patch vote: a face centre that reads a neighbour's label at the exact pixel still
    /// resolves to its own instance when the surrounding patch disagrees — the fixture corpus
    /// measured exactly this failure on a tilted head.
    @Test func personMasks_patchVoteOverridesASinglePixelMiss() async {
        let mask = makeMask()
        let service = SubjectSegmentationService(
            maskProvider: { _, _ in nil },
            personProvider: { _, _ in
                self.stubSegmentation(masks: [1: mask, 2: mask]) { p in
                    // Exactly at the centre: the wrong neighbour. Everywhere else: instance 2.
                    (abs(p.x - 0.5) < 0.008 && abs(p.y - 0.5) < 0.008) ? 1 : 2
                }
            }
        )
        let image = makeImage()   // 64×64, centre (32, 32)
        let results = await service.personMasks(for: image, at: [CGPoint(x: 32, y: 32)])

        // Modal label over the patch is 2; a single-pixel read would have said 1.
        #expect(results.count == 1)
        #expect(results[0] != nil)
    }

    /// The oriented conversion, pinned with a stub: a `.right`-oriented image swaps the
    /// dimensions, and a point given in oriented pixel space must arrive at the label lookup
    /// in normalized oriented coordinates. This is the rotated-photo bug that silently returned
    /// label 0, fixed once in the deleted API and kept fixed here.
    @Test func personMasks_convertUsingOrientedDimensions() async {
        var received: [CGPoint] = []
        let mask = makeMask()
        let service = SubjectSegmentationService(
            maskProvider: { _, _ in nil },
            personProvider: { _, _ in
                self.stubSegmentation(masks: [1: mask]) { p in
                    received.append(p); return 1
                }
            }
        )
        // A 64×32 bitmap displayed .right: oriented size is 32×64.
        let raw = makeImage(side: 64).cgImage!
        let context = CGContext(
            data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(raw, in: CGRect(x: 0, y: 0, width: 64, height: 32))
        let wide = context.makeImage()!
        let rotated = UIImage(cgImage: wide, scale: 1, orientation: .right)

        // Oriented space is 32 wide × 64 tall; ask about its centre.
        _ = await service.personMasks(for: rotated, at: [CGPoint(x: 16, y: 32)])

        // Every patch sample must be normalized against 32×64, not 64×32: the centre lands at
        // (0.5, 0.5) and the patch spreads around it, so all samples stay near the middle.
        // Mis-normalizing against the raw dimensions would put x at 16/64 = 0.25.
        #expect(!received.isEmpty)
        #expect(received.allSatisfy { abs($0.x - 0.5) < 0.1 && abs($0.y - 0.5) < 0.12 })
    }

    /// A throwing provider yields nils, not a crash, and is not cached as "no people".
    @Test func personMasks_throwingProviderYieldsNil() async {
        struct Boom: Error {}
        let service = SubjectSegmentationService(
            maskProvider: { _, _ in nil },
            personProvider: { _, _ in throw Boom() }
        )
        let results = await service.personMasks(for: makeImage(), at: [CGPoint(x: 10, y: 10)])
        #expect(results == [nil])
    }

    // MARK: - Prewarm

    /// `prewarm()` moves the ~215 ms cold model load off the user's first tap. It must not
    /// disturb the cache, or the photo the user picked would come back with the warm-up
    /// swatch's answer.
    @Test func prewarm_doesNotPopulateTheCache() async {
        let service = serviceFindingSubject()
        service.prewarm()

        _ = await service.subjectMask(for: makeImage())

        #expect(service.segmentationCount == 1)
    }
}
