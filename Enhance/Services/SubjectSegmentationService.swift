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
///   So `subjectMask(for:)` returns `nil` for "this photo has no subject". `nil` is a
///   normal answer here; only `Failure` means something went wrong.
///
///   **The editor's response to `nil` follows the face precedent: a toast, with the cards
///   left live** — `detectFacesIfNeeded` (`EditorViewModel.swift:689-703`) shows
///   "NO FACES DETECTED" and disables nothing, and the subject effects match it rather than
///   inventing a second answer to the same situation. The consequence for §2f is a
///   requirement on the *effects*, not on this service: **a subject effect handed a `nil`
///   mask must return the frame unchanged**, the way face effects degrade when no face is
///   selected. A card that stays tappable must not render a broken frame.
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

    /// Per-instance masks, keyed by image and by the point that selected the instance. A group
    /// photo asks for one of these per face, so they cannot share the single-mask slot.
    private struct InstanceKey: Hashable { let hash: Int; let x: Int; let y: Int }
    private var cachedInstanceMasks: [InstanceKey: CIImage?] = [:]

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

    /// The silhouette of the **one** foreground instance under `point`, in the image's pixel
    /// space — or `nil` if nothing is segmented there.
    ///
    /// `subjectMask(for:)` unions every instance, which is right for effects that treat
    /// "subject vs background" as the whole question. It is wrong for anything that has to act
    /// on *one person in a group*: BIG HEAD grew a head bounded by geometric walls, and the walls
    /// cut a straight line through the subject's own hair rather than following him
    /// *(user-reported: the head read as a cardboard cutout)*. The boundary should follow the
    /// silhouette, and only a per-instance mask can do that.
    ///
    /// **How the instance is chosen is the part worth keeping.** `instanceMask` is a per-pixel
    /// buffer of instance *indices*, so the instance owning a face is a single buffer read at
    /// that face's location — no rendering, no per-instance mask generation and comparison. That
    /// keeps this to one segmentation pass regardless of how many people are in the shot.
    ///
    /// - Parameter point: a location in the image's pixel space, y-up (Core Image convention),
    ///   such as `DetectedFace.faceCenter`.
    func instanceMask(for image: UIImage, containing point: CGPoint) throws -> CIImage? {
        guard let cgImage = image.cgImage else { throw Failure.noCGImage }

        let key = InstanceKey(hash: image.hashValue, x: Int(point.x), y: Int(point.y))
        if let cached = cachedInstanceMasks[key] { return cached }

        segmentationCount += 1

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: visionOrientation(from: image),
            options: [:]
        )
        do { try handler.perform([request]) } catch { throw Failure.visionFailed(error) }

        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            cachedInstanceMasks[key] = .some(nil)
            return nil
        }

        let instance = Self.instanceIndex(
            at: point,
            in: observation.instanceMask,
            imageSize: CGSize(width: cgImage.width, height: cgImage.height)
        )

        // 0 is background in Vision's indexing. Falling back to the union rather than to nothing
        // matters: a face just outside its own silhouette — hair sampled at the edge, or a
        // detection box slightly off — should still get a usable mask instead of the effect
        // silently doing nothing.
        let instances: IndexSet = (instance > 0) ? IndexSet(integer: instance) : observation.allInstances

        do {
            let buffer = try observation.generateScaledMaskForImage(forInstances: instances, from: handler)
            let mask = scaled(CIImage(cvPixelBuffer: buffer), toMatch: image)
            cachedInstanceMasks[key] = .some(mask)
            return mask
        } catch {
            throw Failure.maskGenerationFailed(error)
        }
    }

    /// Reads the instance index at a point straight out of Vision's label buffer.
    ///
    /// The buffer is one byte per pixel, top-left origin, at Vision's own working resolution —
    /// so the point is converted from Core Image's y-up image space and rescaled to the buffer.
    private static func instanceIndex(at point: CGPoint, in buffer: CVPixelBuffer, imageSize: CGSize) -> Int {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        guard w > 0, h > 0, imageSize.width > 0, imageSize.height > 0,
              let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }

        let nx = point.x / imageSize.width
        // Flip: image space is y-up, the buffer is y-down.
        let ny = 1 - (point.y / imageSize.height)
        guard nx >= 0, nx < 1, ny >= 0, ny < 1 else { return 0 }

        let x = min(w - 1, max(0, Int(nx * CGFloat(w))))
        let y = min(h - 1, max(0, Int(ny * CGFloat(h))))
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        return Int(base.assumingMemoryBound(to: UInt8.self)[y * stride + x])
    }

    /// Whether this photo has a subject to build on. The editor uses this to decide whether
    /// to show the "no subject" toast — not whether to enable the cards, which stay live
    /// either way. See the note on absence above.
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
        cachedInstanceMasks = [:]
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
