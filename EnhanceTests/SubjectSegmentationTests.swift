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
        SubjectSegmentationService { _, _ in self.makeMask(side: maskSide) }
    }

    /// A service whose segmentation never finds one.
    private func serviceFindingNothing() -> SubjectSegmentationService {
        SubjectSegmentationService { _, _ in nil }
    }

    // MARK: - Absence is an answer, not an error

    @Test func noSubject_returnsNil() async {
        #expect(await serviceFindingNothing().subjectMask(for: makeImage()) == nil)
    }

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

    /// A caller that cannot tell these apart would disable the effect on a transient Vision
    /// error, so the distinction is part of the contract rather than a convenience.
    @Test func providerThrows_propagatesRatherThanReportingNoSubject() {
        struct Boom: Error {}
        let service = SubjectSegmentationService { _, _ in throw Boom() }

        #expect(throws: Boom.self) {
            _ = try service.subjectMaskOrThrow(for: self.makeImage())
        }
    }

    /// A failure must not be cached as "no subject" — otherwise one transient error would
    /// disable the effect for that photo for the rest of the session.
    @Test func providerThrows_doesNotPoisonTheCache() async {
        struct Boom: Error {}
        final class Gate: @unchecked Sendable { var shouldThrow = true }
        let gate = Gate()
        let service = SubjectSegmentationService { _, _ in
            if gate.shouldThrow { throw Boom() }
            return self.makeMask()
        }
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
