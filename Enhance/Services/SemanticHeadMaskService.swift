import CoreImage
import UIKit
import MediaPipeTasksVision
import Vision

/// One model-backed, head-only matte for a detected face.
struct SemanticHeadMask {
    let mask: CIImage
    let neckNormY: Double
    let crownNormY: Double
    let confidence: Double
    let hasAccessory: Bool
}

/// Semantic V2's aligned output plus the compositor exclusion set. V2 currently grows every
/// distinct detected face; overlap is resolved by ordered compositing and bounded growth rather
/// than silently leaving members of a group unchanged.
struct SemanticHeadMaskBatch {
    let masks: [SemanticHeadMask?]
    let suppressedFaceIDs: Set<UUID>
}

/// Runs Google's six-class selfie segmenter on a face-centred crop, then keeps only the
/// hair/face/accessory component owned by that face. The output is in the oriented source image's
/// pixel space, matching `DetectedFace` and the existing Vision masks.
// Mutable model/cache state is confined to `queue`; callers only cross that boundary through
// `headMasks` and `clearCache`.
final class SemanticHeadMaskService: @unchecked Sendable {

    enum Failure: Error, LocalizedError {
        case modelMissing
        case imageUnavailable
        case badLabels([String])
        case noConfidenceMasks

        var errorDescription: String? {
            switch self {
            case .modelMissing: return "The semantic head model is missing from the app bundle."
            case .imageUnavailable: return "The source image could not be normalized."
            case .badLabels(let labels): return "Unexpected segmentation labels: \(labels.joined(separator: ", "))"
            case .noConfidenceMasks: return "The model did not return confidence masks."
            }
        }
    }

    struct Configuration {
        var cropWidthInFaces: CGFloat = 3.2
        var cropHeightInFaces: CGFloat = 4.0
        var cropUpwardBiasInFaces: CGFloat = 0.35
        var coreThreshold: Float = 0.55
        var growThreshold: Float = 0.23
        // The six-class selfie model is much less certain about hats than it is about skin or
        // hair. Treat `others` as a candidate at a lower confidence, then rely on ownership,
        // upper-head bounds and connectivity to keep unrelated props out.
        var accessoryThreshold: Float = 0.18
        var ownershipSlack: CGFloat = 1.12
        // Vision exposes only a few person instances and can assign the same instance to
        // multiple face seeds in a crowd. Above this count, semantic ownership is safer than
        // supplementing hats from a potentially shared or misassigned whole-person matte.
        var maxFacesForPersonHatSupplement = 3

        static let `default` = Configuration()
    }

    private struct CachedResult {
        let key: String
        let masks: [SemanticHeadMask?]
    }

    private let configuration: Configuration
    private let modelURL: URL?
    private let queue = DispatchQueue(label: "Enhance.SemanticHeadMask", qos: .userInitiated)
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private var segmenter: ImageSegmenter?
    private var cache: CachedResult?

    init(configuration: Configuration = .default, modelURL: URL? = nil) {
        self.configuration = configuration
        self.modelURL = modelURL
    }

    func headMasks(for image: UIImage, faces: [DetectedFace]) async -> [SemanticHeadMask?] {
        guard !faces.isEmpty else { return [] }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: (try? prepare(image: image, faces: faces))
                    ?? faces.map { _ in nil })
            }
        }
    }

    /// V2 keeps the model-backed outline, intersects it with Vision's per-person instance only
    /// when that instance is unique and the photo is not a crowd, and applies an explicit
    /// safe-overlap policy. If the 256px semantic crop cannot
    /// resolve a small/background face, a conservative face-relative matte keeps that detected
    /// person in the group effect instead of silently leaving one normal-sized head behind.
    /// It remains positionally aligned with `faces`; the stable face id is carried separately
    /// into the compositor.
    func headMasksV2(
        for image: UIImage, faces: [DetectedFace], personMasks: [CIImage?]
    ) async -> SemanticHeadMaskBatch {
        let raw = await headMasks(for: image, faces: faces)
        let sourceExtent = image.orientationAppliedCIImage()?.extent
        let hybrid = raw.enumerated().map { index, head -> SemanticHeadMask? in
            let person = index < personMasks.count ? personMasks[index] : nil
            guard let candidate = head ?? sourceExtent.map({
                geometricFallback(for: faces[index], extent: $0)
            }) else { return nil }
            let denseCrowd = sourceExtent.map { isDenseCrowd(faces, extent: $0) }
                ?? (faces.count > configuration.maxFacesForPersonHatSupplement)
            let owned = boundedToOwner(candidate, face: faces[index], denseGroup: denseCrowd)
            // Instance segmentation often retains hats that the six-class semantic model calls
            // background. Recover only the person's upper-head silhouette, then intersect the
            // complete result with that same instance so no background can enter the cutout.
            let personIsUnique = person.map { candidate in
                personMasks.enumerated().allSatisfy { otherIndex, other in
                    otherIndex == index || (other.map { $0 !== candidate } ?? true)
                }
            } ?? false
            // A shared or crowd-assigned person instance is unsafe for both supplementation and
            // clipping. Simulator fixtures usually return no person instances, while physical
            // devices can return the same soft instance for several people; intersecting with it
            // makes those heads translucent and lets neighbouring cutouts bleed through.
            let safePerson = faces.count <= configuration.maxFacesForPersonHatSupplement
                && personIsUnique ? person : nil
            let supplemented: SemanticHeadMask
            if let safePerson {
                supplemented = supplementHeadwear(owned, with: safePerson, face: faces[index])
            } else {
                supplemented = owned
            }
            let intersected = safePerson.map { intersect(supplemented, with: $0) } ?? supplemented
            return keepingFaceConnectedComponent(intersected, face: faces[index])
        }
        return SemanticHeadMaskBatch(
            masks: hybrid,
            suppressedFaceIDs: []
        )
    }

    func clearCache() {
        queue.sync { cache = nil }
    }

    private func prepare(image: UIImage, faces: [DetectedFace]) throws -> [SemanticHeadMask?] {
        let key = cacheKey(image: image, faces: faces)
        if cache?.key == key { return cache?.masks ?? [] }

        guard let normalizedCG = normalizedCGImage(from: image) else { throw Failure.imageUnavailable }
        let extent = CGRect(x: 0, y: 0, width: normalizedCG.width, height: normalizedCG.height)
        let segmenter = try imageSegmenter()
        let labels = segmenter.labels.map { $0.lowercased() }
        guard let hairIndex = labels.firstIndex(of: "hair"),
              let faceIndex = labels.firstIndex(of: "face-skin"),
              let otherIndex = labels.firstIndex(of: "others") else {
            throw Failure.badLabels(labels)
        }

        let poseNecks = detectedPoseNecks(in: normalizedCG, faces: faces)
        var prepared: [SemanticHeadMask?] = []
        prepared.reserveCapacity(faces.count)
        for (facePosition, face) in faces.enumerated() {
            let crop = cropRect(for: face, in: extent)
            guard crop.width >= 2, crop.height >= 2,
                  let cropCG = normalizedCG.cropping(to: cgCropRect(from: crop, imageHeight: extent.height))
            else {
                prepared.append(nil)
                continue
            }

            // The model is 256×256. Feeding it a 24MP crop makes the SDK allocate and resize
            // thousands of unnecessary pixels for every face; render the exact input size once.
            guard let inferenceCG = fixedModelInput(from: cropCG) else {
                prepared.append(nil)
                continue
            }
            let cropImage = UIImage(cgImage: inferenceCG, scale: 1, orientation: .up)
            let mpImage = try MPImage(uiImage: cropImage)
            let result = try segmenter.segment(image: mpImage)
            guard let confidenceMasks = result.confidenceMasks,
                  hairIndex < confidenceMasks.count,
                  faceIndex < confidenceMasks.count,
                  otherIndex < confidenceMasks.count else {
                throw Failure.noConfidenceMasks
            }
            prepared.append(makeHeadMask(
                confidenceMasks: confidenceMasks,
                hairIndex: hairIndex,
                faceIndex: faceIndex,
                otherIndex: otherIndex,
                guide: CIImage(cgImage: cropCG),
                crop: crop,
                sourceExtent: extent,
                target: face,
                allFaces: faces,
                poseNeckY: poseNecks[facePosition]
            ))
        }

        cache = CachedResult(key: key, masks: prepared)
        return prepared
    }

    private func imageSegmenter() throws -> ImageSegmenter {
        if let segmenter { return segmenter }
        let located = modelURL
            ?? Bundle.main.url(
                forResource: "selfie_multiclass_256x256", withExtension: "tflite",
                subdirectory: "Models"
            )
            ?? Bundle.main.url(forResource: "selfie_multiclass_256x256", withExtension: "tflite")
        guard let located else { throw Failure.modelMissing }

        let options = ImageSegmenterOptions()
        options.baseOptions.modelAssetPath = located.path
        options.runningMode = .image
        options.shouldOutputConfidenceMasks = true
        options.shouldOutputCategoryMask = false
        let made = try ImageSegmenter(options: options)
        segmenter = made
        return made
    }

    private func intersect(_ head: SemanticHeadMask, with person: CIImage) -> SemanticHeadMask {
        let extent = head.mask.extent
        guard extent.width > 0, extent.height > 0,
              person.extent.width > 0, person.extent.height > 0 else { return head }
        let aligned = person
            .transformed(by: CGAffineTransform(
                translationX: -person.extent.minX,
                y: -person.extent.minY
            ))
            .transformed(by: CGAffineTransform(
                scaleX: extent.width / person.extent.width,
                y: extent.height / person.extent.height
            ))
            .transformed(by: CGAffineTransform(
                translationX: extent.minX,
                y: extent.minY
            ))
            .cropped(to: extent)
        let mask = head.mask
            .applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: aligned
            ])
            .cropped(to: extent)
        return SemanticHeadMask(
            mask: mask, neckNormY: head.neckNormY, crownNormY: head.crownNormY,
            confidence: head.confidence, hasAccessory: head.hasAccessory
        )
    }

    /// Vision's person-instance matte is a safer source for a missing hat than a geometric fill:
    /// it can add real crown/brim pixels without also copying the sky visible around them. The
    /// face-relative lobe prevents the instance's torso, arms and hands from changing head shape.
    private func supplementHeadwear(
        _ head: SemanticHeadMask, with person: CIImage, face: DetectedFace
    ) -> SemanticHeadMask {
        let extent = head.mask.extent
        guard extent.width > 0, extent.height > 0,
              person.extent.width > 0, person.extent.height > 0 else { return head }
        let aligned = person
            .transformed(by: CGAffineTransform(
                translationX: -person.extent.minX, y: -person.extent.minY
            ))
            .transformed(by: CGAffineTransform(
                scaleX: extent.width / person.extent.width,
                y: extent.height / person.extent.height
            ))
            .transformed(by: CGAffineTransform(
                translationX: extent.minX, y: extent.minY
            ))
            .cropped(to: extent)

        let radiusX = max(1, face.faceWidth * 1.22)
        let radiusY = max(1, face.faceHeight * 0.82)
        let centre = CGPoint(
            x: face.faceCenter.x,
            y: face.faceCenter.y + face.faceHeight * 0.66
        )
        let yScale = radiusY / radiusX
        let lobe = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: centre.x, y: centre.y / yScale),
            "inputRadius0": radiusX * 0.94,
            "inputRadius1": radiusX,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor.black
        ])?.outputImage?
            .transformed(by: CGAffineTransform(scaleX: 1, y: yScale))
            .cropped(to: extent)
            ?? CIImage(color: .black).cropped(to: extent)
        let recovered = aligned
            .applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: lobe
            ])
            .cropped(to: extent)
        let union = head.mask
            .applyingFilter("CIMaximumCompositing", parameters: [
                kCIInputBackgroundImageKey: recovered
            ])
            .cropped(to: extent)
        return SemanticHeadMask(
            mask: union, neckNormY: head.neckNormY, crownNormY: head.crownNormY,
            confidence: head.confidence, hasAccessory: true
        )
    }

    /// Last-resort V2 matte for a face the semantic model cannot resolve. The ellipse is wider
    /// and taller than the detector's facial rectangle so it includes hair and a modest hat,
    /// but it stops above the shoulders. A soft edge prevents the fallback from reading as a
    /// pasted oval. When a unique person-instance mask exists in a photo of at most three people,
    /// `headMasksV2` intersects this shape with it immediately after construction.
    private func geometricFallback(for face: DetectedFace, extent: CGRect) -> SemanticHeadMask {
        let radiusX = max(1, face.faceWidth * 0.82)
        let radiusY = max(1, face.faceHeight * 1.02)
        let centre = CGPoint(
            x: face.faceCenter.x,
            y: face.faceCenter.y + face.faceHeight * 0.10
        )
        let yScale = radiusY / radiusX
        let feather = max(1, min(face.faceWidth, face.faceHeight) * 0.08)
        let ellipse = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: centre.x, y: centre.y / yScale),
            "inputRadius0": max(0, radiusX - feather),
            "inputRadius1": radiusX,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor.black
        ])?.outputImage?
            .transformed(by: CGAffineTransform(scaleX: 1, y: yScale))
            .cropped(to: extent)
            ?? CIImage(color: .black).cropped(to: extent)

        return SemanticHeadMask(
            mask: ellipse,
            neckNormY: Double(max(extent.minY, centre.y - radiusY) / max(1, extent.height)),
            crownNormY: Double(min(extent.maxY, centre.y + radiusY) / max(1, extent.height)),
            confidence: 0,
            hasAccessory: false
        )
    }

    /// The semantic model knows classes, not instances. A connected hair/skin component can
    /// therefore walk into an undetected neighbour and make that neighbour part of the copied
    /// source. V2 gives every detected face a soft, face-relative ownership envelope before any
    /// person-instance intersection. The semantic contour still defines the visible outline;
    /// this mask is only a maximum plausible reach.
    private func boundedToOwner(
        _ head: SemanticHeadMask, face: DetectedFace, denseGroup: Bool
    ) -> SemanticHeadMask {
        let extent = head.mask.extent
        // A person-instance mask owns hands and clothing too, so it must not widen the plausible
        // *head* envelope. That wider 1.15x path let a foreground subject's raised hand survive
        // as a detached lobe; after scaling, the lobe landed as a dark slice across a neighbour.
        // Keep the ordinary head compact in every environment. Hats receive their own upper
        // lobe below, rather than making the entire face envelope wide.
        let radiusX = max(1, face.faceWidth * 0.92)
        let radiusY = max(1, face.faceHeight * (denseGroup ? 1.38 : 1.18))
        let centre = CGPoint(
            x: face.faceCenter.x,
            y: face.faceCenter.y + face.faceHeight * (denseGroup ? 0.12 : 0.30)
        )
        func ellipse(centre: CGPoint, radiusX: CGFloat, radiusY: CGFloat) -> CIImage {
            let yScale = radiusY / radiusX
            return CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: centre.x, y: centre.y / yScale),
                "inputRadius0": radiusX * 0.90,
                "inputRadius1": radiusX,
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black
            ])?.outputImage?
                .transformed(by: CGAffineTransform(scaleX: 1, y: yScale))
                .cropped(to: extent)
                ?? CIImage(color: .white).cropped(to: extent)
        }
        var radial = ellipse(centre: centre, radiusX: radiusX, radiusY: radiusY)
        if head.hasAccessory {
            // Hats need width above the brow, not a wider face envelope. Union a shallow upper
            // lobe so crowns and brims survive without reopening the neighbouring-cheek leak.
            let hat = ellipse(
                centre: CGPoint(x: face.faceCenter.x,
                                y: face.faceCenter.y + face.faceHeight * 0.72),
                radiusX: face.faceWidth * 1.20,
                radiusY: face.faceHeight * 0.72
            )
            radial = hat.applyingFilter("CIMaximumCompositing", parameters: [
                kCIInputBackgroundImageKey: radial
            ]).cropped(to: extent)
        }
        let bounded = head.mask
            .applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: radial
            ])
            .cropped(to: extent)
        let lower = max(0, centre.y - radiusY) / max(1, extent.height)
        let upper = min(extent.height, centre.y + radiusY) / max(1, extent.height)
        return SemanticHeadMask(
            mask: bounded,
            neckNormY: max(head.neckNormY, Double(lower)),
            crownNormY: min(head.crownNormY, Double(upper)),
            confidence: head.confidence, hasAccessory: head.hasAccessory
        )
    }

    /// Keeps only the matte component connected to the detected face. The semantic model can
    /// connect a nearby hand or cheek at its 256px working resolution; the owner envelope or
    /// person-instance intersection can then sever that borrowed region into a detached island.
    /// Scaling such an island around the face moves it across a neighbour. Flood filling a small
    /// raster from the strongest point inside the face box removes those islands while retaining
    /// hair and hats that are genuinely connected to the subject's head.
    private func keepingFaceConnectedComponent(
        _ head: SemanticHeadMask, face: DetectedFace
    ) -> SemanticHeadMask {
        let extent = head.mask.extent
        guard extent.width >= 2, extent.height >= 2 else { return head }
        let rasterScale = min(1, 512 / max(extent.width, extent.height))
        let normalized = head.mask
            .transformed(by: CGAffineTransform(
                translationX: -extent.minX, y: -extent.minY
            ))
            .transformed(by: CGAffineTransform(scaleX: rasterScale, y: rasterScale))
        let width = max(1, Int(ceil(extent.width * rasterScale)))
        let height = max(1, Int(ceil(extent.height * rasterScale)))
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        var coverage = [UInt8](repeating: 0, count: width * height)
        context.render(
            normalized, toBitmap: &coverage, rowBytes: width, bounds: bounds,
            format: .R8, colorSpace: nil
        )

        let faceBox = face.boundingBox
            .offsetBy(dx: -extent.minX, dy: -extent.minY)
            .applying(CGAffineTransform(scaleX: rasterScale, y: rasterScale))
            .insetBy(dx: -face.faceWidth * rasterScale * 0.12,
                     dy: -face.faceHeight * rasterScale * 0.12)
            .intersection(bounds)
        guard !faceBox.isNull else { return head }
        let minX = max(0, Int(floor(faceBox.minX)))
        let maxX = min(width - 1, Int(ceil(faceBox.maxX)))
        let minY = max(0, Int(floor(faceBox.minY)))
        let maxY = min(height - 1, Int(ceil(faceBox.maxY)))
        var seed = -1
        var seedCoverage: UInt8 = 0
        for y in minY...maxY {
            for x in minX...maxX {
                let index = y * width + x
                if coverage[index] > seedCoverage {
                    seedCoverage = coverage[index]
                    seed = index
                }
            }
        }
        let threshold: UInt8 = 20
        guard seed >= 0, seedCoverage >= threshold else { return head }

        var kept = [Bool](repeating: false, count: coverage.count)
        var queue = [Int](repeating: 0, count: coverage.count)
        var read = 0
        var write = 1
        kept[seed] = true
        queue[0] = seed
        while read < write {
            let index = queue[read]
            read += 1
            let x = index % width
            let y = index / width
            for offsetY in -1...1 {
                for offsetX in -1...1 where offsetX != 0 || offsetY != 0 {
                    let nextX = x + offsetX
                    let nextY = y + offsetY
                    guard nextX >= 0, nextX < width, nextY >= 0, nextY < height else {
                        continue
                    }
                    let next = nextY * width + nextX
                    guard !kept[next], coverage[next] >= threshold else { continue }
                    kept[next] = true
                    queue[write] = next
                    write += 1
                }
            }
        }

        let gateBytes = kept.map { $0 ? UInt8.max : 0 }
        guard let gateCG = grayscaleImage(bytes: gateBytes, width: width, height: height) else {
            return head
        }
        let gate = CIImage(cgImage: gateCG)
            .transformed(by: CGAffineTransform(
                scaleX: 1 / rasterScale, y: 1 / rasterScale
            ))
            .transformed(by: CGAffineTransform(
                translationX: extent.minX, y: extent.minY
            ))
            .cropped(to: extent)
        let cleaned = head.mask
            .applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: gate
            ])
            .cropped(to: extent)
        return SemanticHeadMask(
            mask: cleaned, neckNormY: head.neckNormY, crownNormY: head.crownNormY,
            confidence: head.confidence, hasAccessory: head.hasAccessory
        )
    }

    private func makeHeadMask(
        confidenceMasks: [Mask], hairIndex: Int, faceIndex: Int, otherIndex: Int,
        guide: CIImage, crop: CGRect, sourceExtent: CGRect, target: DetectedFace,
        allFaces: [DetectedFace], poseNeckY: CGFloat?
    ) -> SemanticHeadMask? {
        let hair = confidenceMasks[hairIndex]
        let skin = confidenceMasks[faceIndex]
        let accessory = confidenceMasks[otherIndex]
        let width = hair.width
        let height = hair.height
        guard width > 1, height > 1, skin.width == width, skin.height == height,
              accessory.width == width, accessory.height == height else { return nil }

        let count = width * height
        let hairData = hair.float32Data
        let skinData = skin.float32Data
        let accessoryData = accessory.float32Data
        let denseGroup = isDenseCrowd(allFaces, extent: sourceExtent)
        var probability = [Float](repeating: 0, count: count)
        var base = [Bool](repeating: false, count: count)
        var accessoryCandidate = [Bool](repeating: false, count: count)

        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let sourcePoint = sourcePoint(x: x, y: y, width: width, height: height, crop: crop)
                guard owns(sourcePoint, target: target, allFaces: allFaces) else { continue }
                let primary = max(hairData[i], skinData[i])
                probability[i] = primary
                base[i] = primary >= configuration.growThreshold

                // `others` contains hats but also arbitrary props. Admit it only in the head
                // envelope; a dilation from the hair/face component below supplies connectivity.
                let lowerReach: CGFloat = denseGroup ? 0.70 : 0.30
                let sideReach: CGFloat = denseGroup ? 1.80 : 1.65
                let accessoryThreshold = denseGroup ? Float(0.35) : configuration.accessoryThreshold
                let aboveJaw = sourcePoint.y >= target.faceCenter.y - target.faceHeight * lowerReach
                let nearHead = abs(sourcePoint.x - target.faceCenter.x) <= target.faceWidth * sideReach
                accessoryCandidate[i] = aboveJaw && nearHead
                    && accessoryData[i] >= accessoryThreshold
            }
        }

        var connectedAccessory = base
        for _ in 0..<24 {
            var next = connectedAccessory
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let i = y * width + x
                    guard accessoryCandidate[i], !connectedAccessory[i] else { continue }
                    if connectedAccessory[i - 1] || connectedAccessory[i + 1]
                        || connectedAccessory[i - width] || connectedAccessory[i + width] {
                        next[i] = true
                        probability[i] = max(probability[i], accessoryData[i])
                    }
                }
            }
            connectedAccessory = next
        }

        guard let seed = bestSeed(
            probability: probability, width: width, height: height, crop: crop, face: target
        ), probability[seed] >= configuration.coreThreshold else { return nil }

        var selected = [Bool](repeating: false, count: count)
        var queue = [Int](repeating: 0, count: count)
        var read = 0
        var write = 1
        queue[0] = seed
        selected[seed] = true
        while read < write {
            let i = queue[read]
            read += 1
            let x = i % width
            let y = i / width
            let neighbours = [
                x > 0 ? i - 1 : -1,
                x + 1 < width ? i + 1 : -1,
                y > 0 ? i - width : -1,
                y + 1 < height ? i + width : -1
            ]
            for n in neighbours where n >= 0 && !selected[n] {
                guard base[n] || connectedAccessory[n] else { continue }
                selected[n] = true
                queue[write] = n
                write += 1
            }
        }

        // Hats are frequently split into several accessory lobes by highlights, logos and
        // ventilation openings. Fill only between already-owned pixels on an upper-head row;
        // this closes crown/brim notches without inventing a wider silhouette or reaching into
        // a neighbour. A light majority pass then removes one-cell spikes from the 256px model.
        if !denseGroup {
            for y in 0..<height {
                let rowY = sourcePoint(
                    x: width / 2, y: y, width: width, height: height, crop: crop
                ).y
                guard rowY >= target.faceCenter.y + target.faceHeight * 0.05 else { continue }
                var first: Int?
                var last: Int?
                for x in 0..<width where selected[y * width + x] {
                    let point = sourcePoint(
                        x: x, y: y, width: width, height: height, crop: crop
                    )
                    guard abs(point.x - target.faceCenter.x) <= target.faceWidth * 1.25 else {
                        continue
                    }
                    first = first ?? x
                    last = x
                }
                guard let first, let last, last - first >= 2 else { continue }
                for x in first...last {
                    let point = sourcePoint(
                        x: x, y: y, width: width, height: height, crop: crop
                    )
                    if owns(point, target: target, allFaces: allFaces) {
                        selected[y * width + x] = true
                    }
                }
            }
            for _ in 0..<2 {
                var smoothed = selected
                for y in 1..<(height - 1) {
                    for x in 1..<(width - 1) {
                        var neighbours = 0
                        for offsetY in -1...1 {
                            for offsetX in -1...1 where selected[(y + offsetY) * width + x + offsetX] {
                                neighbours += 1
                            }
                        }
                        let i = y * width + x
                        smoothed[i] = selected[i] ? neighbours >= 3 : neighbours >= 6
                    }
                }
                selected = smoothed
            }
        }

        // Confidence masks commonly punch holes through glasses, eyes and shadowed cheeks.
        // Those holes turn the enlarged layer translucent and reveal a second, normal-sized
        // face underneath it. The detector rectangle is a stronger geometric guarantee for the
        // *interior* of the face than semantic class confidence, so make a deliberately inset
        // ellipse opaque. Keeping it inset preserves the model-backed jaw, ears and hair edge.
        var protectedFaceCore = [Bool](repeating: false, count: count)
        for y in 0..<height {
            for x in 0..<width {
                let point = sourcePoint(
                    x: x, y: y, width: width, height: height, crop: crop
                )
                guard owns(point, target: target, allFaces: allFaces) else { continue }
                let dx = (point.x - target.faceCenter.x) / max(1, target.faceWidth * 0.46)
                let dy = (point.y - target.faceCenter.y) / max(1, target.faceHeight * 0.52)
                if dx * dx + dy * dy <= 1 {
                    let i = y * width + x
                    selected[i] = true
                    protectedFaceCore[i] = true
                }
            }
        }

        var bytes = [UInt8](repeating: 0, count: count)
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        var confidenceTotal: Double = 0
        var selectedCount = 0
        var selectedAccessoryCount = 0
        for i in 0..<count where selected[i] {
            let p = probability[i]
            // `selected` is already the thresholded, face-connected membership decision. Do
            // not reuse raw class confidence as opacity: a 0.35-confidence cap is still a cap,
            // not a 35%-transparent cap. EdgePreserveUpsample supplies the outer antialiasing.
            if denseGroup, !protectedFaceCore[i] {
                let denominator = max(0.01, configuration.coreThreshold - configuration.growThreshold)
                let linear = max(0, min(1, (p - configuration.growThreshold) / denominator))
                let coverage = linear * linear * (3 - 2 * linear)
                bytes[i] = UInt8(coverage * 255)
            } else {
                bytes[i] = .max
            }
            let point = sourcePoint(
                x: i % width, y: i / width, width: width, height: height, crop: crop
            )
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
            confidenceTotal += Double(p)
            selectedCount += 1
            if accessoryCandidate[i], accessoryData[i] > max(hairData[i], skinData[i]) {
                // A target hat must occupy the upper region of this target face. This prevents
                // a nearby person's cap from opening the wide hat lobe around an un-hatted face.
                if abs(point.x - target.faceCenter.x) <= target.faceWidth * 0.78,
                   point.y >= target.faceCenter.y + target.faceHeight * 0.12 {
                    selectedAccessoryCount += 1
                }
            }
        }
        guard selectedCount > max(20, count / 500), minY.isFinite, maxY.isFinite,
              let cropMask = grayscaleImage(bytes: bytes, width: width, height: height)
        else { return nil }

        let guideScale = min(1, 1024 / max(guide.extent.width, guide.extent.height))
        let boundedGuide = guideScale < 1
            ? guide.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: guideScale
            ])
            : guide
        let smallMask = CIImage(cgImage: cropMask)
        let refined = CIFilter(name: "CIEdgePreserveUpsample", parameters: [
            kCIInputImageKey: boundedGuide,
            "inputSmallImage": smallMask,
            "inputSpatialSigma": 3.0,
            "inputLumaSigma": 0.12
        ])?.outputImage?.cropped(to: boundedGuide.extent)
            ?? smallMask.transformed(by: CGAffineTransform(
                scaleX: boundedGuide.extent.width / CGFloat(width),
                y: boundedGuide.extent.height / CGFloat(height)
            ))
        let positioned = refined
            .transformed(by: CGAffineTransform(
                scaleX: crop.width / boundedGuide.extent.width,
                y: crop.height / boundedGuide.extent.height
            ))
            .transformed(by: CGAffineTransform(translationX: crop.minX, y: crop.minY))
        let black = CIImage(color: .black).cropped(to: sourceExtent)
        let baseFull = positioned.composited(over: black).cropped(to: sourceExtent)
        let full: CIImage
        if denseGroup {
            full = baseFull
        } else {
            let modelPixel = max(crop.width / CGFloat(width), crop.height / CGFloat(height))
            let smoothingRadius = max(0.75, min(12, modelPixel * 0.65))
            full = baseFull
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: smoothingRadius
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 2.2,
                    kCIInputBrightnessKey: 0.04
                ])
                .applyingFilter("CIColorClamp")
                .cropped(to: sourceExtent)
        }
        return SemanticHeadMask(
            mask: full,
            neckNormY: Double((resolvedNeckY(poseNeckY, semanticBottom: minY, face: target))
                / sourceExtent.height),
            crownNormY: Double(maxY / sourceExtent.height),
            confidence: confidenceTotal / Double(selectedCount),
            hasAccessory: selectedAccessoryCount > max(12, selectedCount / 30)
        )
    }

    /// Face count alone is not enough to choose the crowd-safe reconstruction. Four nearby,
    /// large heads still have enough model resolution for hat bridging; five to ten small heads
    /// do not. Use the median face scale so one foreground selfie face cannot disguise a dense
    /// background group.
    private func isDenseCrowd(_ faces: [DetectedFace], extent: CGRect) -> Bool {
        guard faces.count > configuration.maxFacesForPersonHatSupplement, extent.width > 0 else {
            return false
        }
        let widths = faces.map(\.faceWidth).sorted()
        let medianWidth = widths[widths.count / 2]
        return medianWidth / extent.width < 0.10
    }

    private func bestSeed(
        probability: [Float], width: Int, height: Int, crop: CGRect, face: DetectedFace
    ) -> Int? {
        var result: Int?
        var best: Float = -1
        for y in 0..<height {
            for x in 0..<width {
                let point = sourcePoint(x: x, y: y, width: width, height: height, crop: crop)
                let seedBox = CGRect(
                    x: face.boundingBox.minX + face.boundingBox.width * 0.15,
                    y: face.boundingBox.minY + face.boundingBox.height * 0.20,
                    width: face.boundingBox.width * 0.70,
                    height: face.boundingBox.height * 0.70
                )
                let i = y * width + x
                if seedBox.contains(point), probability[i] > best {
                    result = i
                    best = probability[i]
                }
            }
        }
        return result
    }

    private func owns(_ point: CGPoint, target: DetectedFace, allFaces: [DetectedFace]) -> Bool {
        func protectedCore(of face: DetectedFace) -> CGRect {
            face.boundingBox.insetBy(
                dx: face.faceWidth * 0.12,
                dy: face.faceHeight * 0.12
            )
        }
        if protectedCore(of: target).contains(point) { return true }
        let others = allFaces.filter { $0.id != target.id }
        if others.contains(where: { protectedCore(of: $0).contains(point) }) { return false }

        // Compare in source pixels, not in units of each candidate's face width. Normalizing
        // each distance independently gave a large foreground face an enormous ownership field:
        // its nearby raised hand could be "closer" than the small neighbour whose cheek it sat
        // beside. Absolute Voronoi ownership keeps perspective from changing who owns a pixel;
        // the small slack avoids shaving hair exactly on a midpoint boundary.
        let targetDistance = hypot(
            point.x - target.faceCenter.x,
            (point.y - target.faceCenter.y) * 0.85
        )
        let nearestOther = others.map {
            hypot(point.x - $0.faceCenter.x, (point.y - $0.faceCenter.y) * 0.85)
        }.min() ?? .greatestFiniteMagnitude
        return targetDistance <= nearestOther * configuration.ownershipSlack
    }

    private func cropRect(for face: DetectedFace, in extent: CGRect) -> CGRect {
        let width = face.faceWidth * configuration.cropWidthInFaces
        let height = face.faceHeight * configuration.cropHeightInFaces
        let centre = CGPoint(
            x: face.faceCenter.x,
            y: face.faceCenter.y + face.faceHeight * configuration.cropUpwardBiasInFaces
        )
        return CGRect(
            x: centre.x - width / 2, y: centre.y - height / 2, width: width, height: height
        ).intersection(extent)
    }

    /// Vision pose is not a mask; it supplies the lower anchor the semantic classes omit. Match
    /// poses to faces through their nose point and use the neck only when it sits plausibly below
    /// that face. Missing/low-confidence poses simply leave the semantic boundary in charge.
    private func detectedPoseNecks(in image: CGImage, faces: [DetectedFace]) -> [CGFloat?] {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil else { return faces.map { _ in nil } }

        struct Candidate {
            let nose: CGPoint
            let neck: CGPoint
        }
        let size = CGSize(width: image.width, height: image.height)
        let candidates: [Candidate] = (request.results ?? []).compactMap { observation in
            guard let points = try? observation.recognizedPoints(.all),
                  let nose = points[.nose], nose.confidence >= 0.3,
                  let neck = points[.neck], neck.confidence >= 0.3 else { return nil }
            return Candidate(
                nose: CGPoint(x: nose.location.x * size.width, y: nose.location.y * size.height),
                neck: CGPoint(x: neck.location.x * size.width, y: neck.location.y * size.height)
            )
        }

        var result = faces.map { _ in Optional<CGFloat>.none }
        var used = Set<Int>()
        let pairs = faces.indices.flatMap { faceIndex in
            candidates.indices.map { candidateIndex -> (Int, Int, CGFloat) in
                let face = faces[faceIndex]
                let nose = candidates[candidateIndex].nose
                let distance = hypot(nose.x - face.faceCenter.x, nose.y - face.faceCenter.y)
                    / max(1, face.faceWidth)
                return (faceIndex, candidateIndex, distance)
            }
        }.sorted { $0.2 < $1.2 }

        var assignedFaces = Set<Int>()
        for (faceIndex, candidateIndex, cost) in pairs {
            guard cost <= 1.25, !assignedFaces.contains(faceIndex), !used.contains(candidateIndex)
            else { continue }
            let face = faces[faceIndex]
            let neck = candidates[candidateIndex].neck
            guard neck.y < face.faceCenter.y,
                  neck.y > face.faceCenter.y - face.faceHeight * 2.2 else { continue }
            result[faceIndex] = neck.y
            assignedFaces.insert(faceIndex)
            used.insert(candidateIndex)
        }
        return result
    }

    private func resolvedNeckY(
        _ poseNeckY: CGFloat?, semanticBottom: CGFloat, face: DetectedFace
    ) -> CGFloat {
        guard let poseNeckY,
              poseNeckY < face.faceCenter.y,
              poseNeckY > face.faceCenter.y - face.faceHeight * 2.2 else {
            return semanticBottom
        }
        return min(semanticBottom, poseNeckY)
    }

    private func sourcePoint(
        x: Int, y: Int, width: Int, height: Int, crop: CGRect
    ) -> CGPoint {
        CGPoint(
            x: crop.minX + (CGFloat(x) + 0.5) / CGFloat(width) * crop.width,
            // MediaPipe rows are top-to-bottom; Core Image/source coordinates are y-up.
            y: crop.maxY - (CGFloat(y) + 0.5) / CGFloat(height) * crop.height
        )
    }

    private func cgCropRect(from ciRect: CGRect, imageHeight: CGFloat) -> CGRect {
        CGRect(
            x: ciRect.minX, y: imageHeight - ciRect.maxY,
            width: ciRect.width, height: ciRect.height
        ).integral
    }

    private func grayscaleImage(bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    private func normalizedCGImage(from image: UIImage) -> CGImage? {
        guard let oriented = image.orientationAppliedCIImage() else { return nil }
        return context.createCGImage(oriented, from: oriented.extent)
    }

    private func fixedModelInput(from image: CGImage) -> CGImage? {
        let target = CGSize(width: 256, height: 256)
        let source = CIImage(cgImage: image)
        let resized = source.transformed(by: CGAffineTransform(
            scaleX: target.width / source.extent.width,
            y: target.height / source.extent.height
        ))
        return context.createCGImage(
            resized, from: CGRect(origin: .zero, size: target),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        )
    }

    private func cacheKey(image: UIImage, faces: [DetectedFace]) -> String {
        let facePart = faces.map {
            "\(Int($0.faceCenter.x.rounded())):\(Int($0.faceCenter.y.rounded())):\(Int($0.faceWidth.rounded()))"
        }.joined(separator: "|")
        return "\(image.hashValue)-\(image.imageOrientation.rawValue)-\(facePart)"
    }
}
