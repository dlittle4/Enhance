import Vision
import UIKit
import CoreImage

/// Separates the foreground subject from the background in a still image, producing a
/// mask the subject-mask effects (ROADMAP §2f) composite against.
///
/// Shaped after `FaceDetectionService`: one Vision request, cached per image, with an
/// explicit `clearCache()` for when the source changes. Two things learned from the §1g
/// spike shape this API and are worth not re-deriving:
///
/// - **Absence is a first-class result, not an error.** 1 of the app's own 8 showcase
///   photos returns no observation at all — a low-contrast, heavily occluded subject.
///   So `subjectMask(for:)` returns `nil` for "this photo has no subject", and the editor
///   disables the effect rather than offering one that would silently do nothing.
///   `nil` is a normal answer here; only `Failure` means something went wrong.
/// - **The first call is the expensive one.** Warm, the request is ~12–17 ms plus mask
///   generation; cold it is ~215 ms of one-time model load. `prewarm()` exists so that
///   cost can be paid at photo-pick rather than on the tap that turns the effect on.
///
/// The mask is deliberately *not* softened here. The spike found Vision returns a smooth
/// silhouette with only 1–2px of antialiasing, and that this is fine: the background
/// effect is applied to the whole frame and the mask only chooses between two versions of
/// each pixel, so fine detail like hair and whiskers is never cut off — it simply receives
/// the background's treatment. An effect wanting a softer edge should blur the mask itself
/// rather than changing it for everyone.
final class SubjectSegmentationService {

    /// Why a mask could not be produced. `nil` from `subjectMask(for:)` means "no subject
    /// in this photo", which is an ordinary outcome; these are the genuine failures.
    enum Failure: Error {
        case noCGImage
        case visionFailed(Error)
        case maskGenerationFailed(Error)
    }

    /// Produces a mask for one image, or `nil` when the photo has no subject.
    ///
    /// Injectable for one blunt reason: **`VNGenerateForegroundInstanceMaskRequest` throws
    /// on the iOS Simulator**, so any test that reaches real Vision either fails there or —
    /// worse — passes for the wrong reason, because a thrown error and an absent subject
    /// both arrive at the call site as `nil`. That is the same shape of trap LEARNINGS
    /// records from the CIKernel gate: the green result proved the pipeline ran, not that it
    /// worked. Tests inject a stub and assert cache behaviour deterministically; the real
    /// Vision path is judged by `Tools/segmentation-spike.swift` on real hardware, which is
    /// the only place it can honestly be judged.
    typealias MaskProvider = (CGImage, CGImagePropertyOrientation) throws -> CIImage?

    private let maskProvider: MaskProvider

    init(maskProvider: @escaping MaskProvider = SubjectSegmentationService.visionMaskProvider) {
        self.maskProvider = maskProvider
    }

    private var cachedImageHash: Int?
    private var cachedMask: CIImage??

    /// How many real segmentation passes have run. The cache's whole job is to keep this
    /// near one per photo, and counting is the only way to assert that without timing —
    /// a warm pass on a small image finishes faster than any threshold worth writing.
    private(set) var segmentationCount = 0

    /// The subject mask for this image in its pixel space — white subject, black
    /// background, values in 0...1 — or `nil` if the photo has no discernible subject.
    ///
    /// Returns the cached answer when the image is unchanged, including a cached `nil`,
    /// so a photo without a subject costs one segmentation pass rather than one per query.
    func subjectMask(for image: UIImage) async -> CIImage? {
        try? subjectMaskOrThrow(for: image)
    }

    /// As `subjectMask(for:)`, but surfaces why the mask could not be produced. Useful in
    /// tests and when a caller needs to tell "no subject" apart from "Vision failed".
    func subjectMaskOrThrow(for image: UIImage) throws -> CIImage? {
        let hash = image.hashValue
        if hash == cachedImageHash, let cached = cachedMask { return cached }

        guard let cgImage = image.cgImage else { throw Failure.noCGImage }

        segmentationCount += 1

        guard let raw = try maskProvider(cgImage, visionOrientation(from: image)) else {
            // "Nothing in this photo reads as a subject" — an ordinary answer, and cached
            // like any other so a subjectless photo costs one pass rather than one per query.
            cache(nil, for: hash)
            return nil
        }

        let mask = scaled(raw, toMatch: image)
        cache(mask, for: hash)
        return mask
    }

    /// The real Vision path. Returns `nil` for "no subject", throws for genuine failure.
    static func visionMaskProvider(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) throws -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw Failure.visionFailed(error)
        }

        // No observation, or one with no instances, both mean the same thing: no subject.
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            return nil
        }

        // The union of every instance is the single-subject cutout. Vision groups a scene
        // into foreground instances, and a photo of a person holding a cat can come back as
        // one instance covering both — taking the union means the effects do not have to
        // care which way it split.
        do {
            let buffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,
                from: handler
            )
            return CIImage(cvPixelBuffer: buffer)
        } catch {
            throw Failure.maskGenerationFailed(error)
        }
    }

    /// Whether this photo has a subject to build on — the editor's gate for enabling the
    /// subject effects.
    func hasSubject(in image: UIImage) async -> Bool {
        await subjectMask(for: image) != nil
    }

    /// Pay the one-time model load up front. Cold, the first segmentation costs ~215 ms
    /// against ~15 ms warm, so calling this when a photo is picked keeps that cost off the
    /// tap that switches an effect on. Cheap to call more than once; the result is discarded
    /// and deliberately not cached, since the caller's real image will differ.
    func prewarm() {
        Task.detached(priority: .utility) {
            let side = 64
            UIGraphicsBeginImageContextWithOptions(CGSize(width: side, height: side), true, 1)
            UIColor.gray.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
            let warmupImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            guard let cgImage = warmupImage?.cgImage else { return }
            let request = VNGenerateForegroundInstanceMaskRequest()
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        }
    }

    /// Force re-segmentation by clearing the cache first.
    func resegment(in image: UIImage) async -> CIImage? {
        clearCache()
        return await subjectMask(for: image)
    }

    func clearCache() {
        cachedImageHash = nil
        cachedMask = nil
    }

    // MARK: - Private

    private func cache(_ mask: CIImage?, for hash: Int) {
        cachedImageHash = hash
        cachedMask = .some(mask)
    }

    /// Vision returns the mask at its own working resolution, which is usually but not
    /// always the source's. Rescale so callers can blend against the image directly without
    /// each effect repeating this check.
    private func scaled(_ mask: CIImage, toMatch image: UIImage) -> CIImage {
        let target = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        guard mask.extent.width > 0, mask.extent.height > 0,
              mask.extent.width != target.width || mask.extent.height != target.height else {
            return mask
        }
        return mask.transformed(by: CGAffineTransform(
            scaleX: target.width / mask.extent.width,
            y: target.height / mask.extent.height
        ))
    }

    private func visionOrientation(from image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
