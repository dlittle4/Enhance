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

    init(
        maskProvider: @escaping MaskProvider = SubjectSegmentationService.visionMaskProvider,
        personProvider: @escaping PersonSegmentationProvider = SubjectSegmentationService.visionPersonProvider
    ) {
        self.maskProvider = maskProvider
        self.personProvider = personProvider
    }

    private var cachedImageHash: Int?
    private var cachedMask: CIImage??
    private var cachedAccurateHash: Int?
    private var cachedAccurateMask: CIImage??

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

    /// `VNGeneratePersonSegmentationRequest` at `.accurate` — a soft confidence matte with
    /// better hair edges than the instance masks, people-only. The lab's alternative union
    /// source (user's call, 2026-08-20); a photo with no people yields an empty matte, which
    /// coverage-checks as "no subject" downstream rather than throwing.
    static func personAccurateUnionProvider(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) throws -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw Failure.visionFailed(error)
        }
        guard let buffer = request.results?.first?.pixelBuffer else { return nil }
        return CIImage(cvPixelBuffer: buffer)
    }

    /// The union mask via a caller-chosen source. `.foreground` is the cached shipped path;
    /// `.personAccurate` runs its own request and keeps its own single-slot cache, so flipping
    /// the lab toggle back and forth costs one segmentation per source, not per flip.
    func subjectMask(for image: UIImage, source: HeadMaskTuning.UnionSource) throws -> CIImage? {
        switch source {
        case .foreground:
            return try subjectMaskOrThrow(for: image)
        case .personAccurate:
            let hash = image.hashValue
            if hash == cachedAccurateHash, let cached = cachedAccurateMask { return cached }
            guard let cgImage = image.cgImage else { throw Failure.noCGImage }
            segmentationCount += 1
            let raw = try Self.personAccurateUnionProvider(
                cgImage: cgImage, orientation: visionOrientation(from: image)
            )
            let mask = raw.map { scaled($0, toMatch: image) }
            cachedAccurateHash = hash
            cachedAccurateMask = .some(mask)
            return mask
        }
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

    // MARK: - Per-person masks

    /// Everything one person-segmentation pass produced, in the provider's raw (un-oriented)
    /// pixel space: one mask per instance, and a label lookup over the instance buffer.
    ///
    /// A struct of closures rather than Vision types so the whole path stubs — Vision throws on
    /// the Simulator, and `instanceMask(for:containing:)` bypassing the injectable provider is
    /// exactly what made it untestable (it is deleted in this rebuild).
    struct PersonSegmentation {
        /// Masks keyed by instance label (1-based, Vision's numbering).
        let masks: [Int: CIImage]
        /// The instance label at a point given in **normalized oriented space**, x right,
        /// y **down** (buffer convention), both 0…1. Returns 0 for background.
        let labelAt: (CGPoint) -> Int
    }

    typealias PersonSegmentationProvider =
        (CGImage, CGImagePropertyOrientation) throws -> PersonSegmentation?

    private let personProvider: PersonSegmentationProvider
    private var cachedPersonHash: Int?
    private var cachedPersonSegmentation: PersonSegmentation??

    /// Instances the most recent person pass found — the device diagnostics CSV reads this.
    private(set) var lastPersonInstanceCount: Int = 0

    /// One mask per point, **positionally aligned** with `points` — the silhouette of the
    /// person under each point, or `nil` where the lookup lands on background (label 0). The
    /// *caller* decides the fallback for nil (the union mask), which keeps this API honest
    /// about what person segmentation actually found.
    ///
    /// One segmentation pass per photo regardless of how many points are asked for; the pass
    /// is cached like the union mask.
    ///
    /// **The lookup samples a small patch, not one pixel.** Measured on the fixture corpus: a
    /// single read at a face's centre can land on a neighbour's label — a tilted head puts the
    /// face centre near the collar, where instance attribution is ambiguous — even when the
    /// head itself is cleanly one instance. The patch is weighted upward (toward the forehead,
    /// which is reliably the person's own pixels) and the modal non-zero label wins.
    ///
    /// - Parameter points: locations in the image's pixel space, y-up (Core Image convention),
    ///   e.g. `DetectedFace.faceCenter`.
    /// - Parameter radii: per-point sampling radius — pass roughly a third of the face's
    ///   width. The vote samples across this span of the *face*, which is what makes it robust:
    ///   a tilted head's centre pixel can sit at the collar, where attribution is ambiguous,
    ///   while the face box above it is unambiguously that person (measured: a centre-patch
    ///   vote still assigned a tilted head its neighbour's mask; a face-spanning vote did not).
    func personMasks(for image: UIImage, at points: [CGPoint], radii: [CGFloat] = []) async -> [CIImage?] {
        guard let cgImage = image.cgImage else { return points.map { _ in nil } }

        let segmentation: PersonSegmentation?
        if image.hashValue == cachedPersonHash, let cached = cachedPersonSegmentation {
            segmentation = cached
        } else {
            segmentationCount += 1
            segmentation = (try? personProvider(cgImage, visionOrientation(from: image))) ?? nil
            cachedPersonHash = image.hashValue
            cachedPersonSegmentation = .some(segmentation)
        }

        guard let segmentation else {
            lastPersonInstanceCount = 0
            return points.map { _ in nil }
        }
        lastPersonInstanceCount = segmentation.masks.count

        let orientation = visionOrientation(from: image)
        let orientedSize: CGSize
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            orientedSize = CGSize(width: cgImage.height, height: cgImage.width)
        default:
            orientedSize = CGSize(width: cgImage.width, height: cgImage.height)
        }
        guard orientedSize.width > 0, orientedSize.height > 0 else {
            return points.map { _ in nil }
        }

        // One scaled instance per label, so two faces sharing a label receive the *identical*
        // CIImage object — mask sharing is detectable by identity downstream, which is how the
        // effect knows the mask cannot separate those faces and a midline bound must.
        var scaledByLabel: [Int: CIImage] = [:]
        return points.enumerated().map { index, point in
            let radius = index < radii.count
                ? radii[index]
                : min(orientedSize.width, orientedSize.height) * 0.015
            let label = Self.modalLabel(
                at: point, radius: radius, in: segmentation, orientedSize: orientedSize
            )
            guard label > 0, let mask = segmentation.masks[label] else { return nil }
            if let cached = scaledByLabel[label] { return cached }
            let scaledMask = scaled(mask, toMatch: image)
            scaledByLabel[label] = scaledMask
            return scaledMask
        }
    }

    /// The modal non-zero label over a face-spanning patch around `point`, weighted upward.
    private static func modalLabel(
        at point: CGPoint, radius: CGFloat,
        in segmentation: PersonSegmentation, orientedSize: CGSize
    ) -> Int {
        let dx = max(1, radius)
        let dy = max(1, radius)
        // y-up offsets; positive dy moves toward the forehead — a 3×3 grid over the face plus
        // two extra rows up, where the pixels are most reliably the person's own.
        let offsets: [(CGFloat, CGFloat)] = [
            (0, 0), (-dx, 0), (dx, 0),
            (0, dy), (-dx, dy), (dx, dy),
            (0, 2 * dy), (-dx, 2 * dy), (dx, 2 * dy)
        ]
        var votes: [Int: Int] = [:]
        for (ox, oy) in offsets {
            let nx = (point.x + ox) / orientedSize.width
            // Flip: pixel space is y-up, the label buffer is y-down.
            let ny = 1 - ((point.y + oy) / orientedSize.height)
            guard nx >= 0, nx < 1, ny >= 0, ny < 1 else { continue }
            let label = segmentation.labelAt(CGPoint(x: nx, y: ny))
            if label > 0 { votes[label, default: 0] += 1 }
        }
        return votes.max { $0.value < $1.value }?.key ?? 0
    }

    /// The real Vision path for person segmentation. Returns `nil` when no people are found.
    static func visionPersonProvider(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) throws -> PersonSegmentation? {
        let request = VNGeneratePersonInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw Failure.visionFailed(error)
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            return nil
        }

        var masks: [Int: CIImage] = [:]
        for instance in observation.allInstances {
            guard let buffer = try? observation.generateScaledMaskForImage(
                forInstances: IndexSet(integer: instance), from: handler
            ) else { continue }
            masks[instance] = CIImage(cvPixelBuffer: buffer)
        }
        guard !masks.isEmpty else { return nil }

        let labelBuffer = observation.instanceMask
        return PersonSegmentation(masks: masks) { normalized in
            CVPixelBufferLockBaseAddress(labelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(labelBuffer, .readOnly) }
            let w = CVPixelBufferGetWidth(labelBuffer)
            let h = CVPixelBufferGetHeight(labelBuffer)
            guard w > 0, h > 0,
                  let base = CVPixelBufferGetBaseAddress(labelBuffer) else { return 0 }
            let x = min(w - 1, max(0, Int(normalized.x * CGFloat(w))))
            let y = min(h - 1, max(0, Int(normalized.y * CGFloat(h))))
            let stride = CVPixelBufferGetBytesPerRow(labelBuffer)
            return Int(base.assumingMemoryBound(to: UInt8.self)[y * stride + x])
        }
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
            // The person model is a separate load, and BIG HEAD's first tap pays it otherwise.
            let personRequest = VNGeneratePersonInstanceMaskRequest()
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([personRequest])
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
        cachedAccurateHash = nil
        cachedAccurateMask = nil
        cachedPersonHash = nil
        cachedPersonSegmentation = nil
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
