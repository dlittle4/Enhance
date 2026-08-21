import Vision
import UIKit
import CoreImage

/// Detects human and animal faces/heads in a still image.
/// Human detection uses a three-tier fallback:
/// 1. Vision landmarks (best quality, requires Neural Engine)
/// 2. Vision rectangles (simpler, still needs Vision inference)
/// 3. CIDetector (Core Image, works everywhere including "Designed for iPad" on Mac)
/// Animal detection uses VNDetectAnimalBodyPoseRequest (cats & dogs, iOS 17+).
/// Both run independently and results are merged, so mixed photos work.
/// Results are cached per image to avoid redundant detection.
final class FaceDetectionService {
    private var cachedImageHash: Int?
    private var cachedFaces: [DetectedFace] = []
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Detect human and animal faces in the given image. Returns cached results if the image hasn't changed.
    func detectFaces(in image: UIImage) async -> [DetectedFace] {
        let hash = image.hashValue
        if hash == cachedImageHash { return cachedFaces }

        guard let cgImage = image.cgImage else { return [] }
        let orientation = visionOrientation(from: image)

        // Vision returns coordinates in the *oriented* image space (it applies the
        // orientation hint internally). We must convert using oriented dimensions,
        // not the raw CGImage pixel buffer dimensions which may be rotated.
        let imageWidth: CGFloat
        let imageHeight: CGFloat
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            imageWidth = CGFloat(cgImage.height)
            imageHeight = CGFloat(cgImage.width)
        default:
            imageWidth = CGFloat(cgImage.width)
            imageHeight = CGFloat(cgImage.height)
        }

        // Human detection: landmarks + rectangles run in parallel, then CIDetector fallback
        var humanFaces = detectWithLandmarks(cgImage: cgImage, orientation: orientation, imageWidth: imageWidth, imageHeight: imageHeight)

        if humanFaces == nil {
            humanFaces = detectWithCIDetector(image: image)
        }

        // Animal detection (cats & dogs)
        let animalFaces = detectAnimals(cgImage: cgImage, orientation: orientation, imageWidth: imageWidth, imageHeight: imageHeight)

        let result = (humanFaces ?? []) + (animalFaces ?? [])
        #if DEBUG
        let humanCount = humanFaces?.count ?? 0
        let animalCount = animalFaces?.count ?? 0
        print("FaceDetectionService: detected \(humanCount) human face(s), \(animalCount) animal face(s)")
        #endif
        cachedImageHash = hash
        cachedFaces = result
        return result
    }

    /// Primary path: run landmarks and rectangles in parallel, merge results.
    /// Landmarks provide precise eye/brow positions; rectangles catch side profiles
    /// and partially occluded faces that landmarks miss.
    private func detectWithLandmarks(cgImage: CGImage, orientation: CGImagePropertyOrientation, imageWidth: CGFloat, imageHeight: CGFloat) -> [DetectedFace]? {
        let landmarkRequest = VNDetectFaceLandmarksRequest()
        // The 76-point constellation (revision 3) traces the jaw far more densely than the
        // 65-point default — raw material for the jaw region. User's call, 2026-08-20.
        landmarkRequest.revision = VNDetectFaceLandmarksRequestRevision3
        landmarkRequest.constellation = .constellation76Points
        let rectRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        do {
            try handler.perform([landmarkRequest, rectRequest])
        } catch {
            #if DEBUG
            print("FaceDetectionService: parallel detection failed — \(error.localizedDescription)")
            #endif
            return nil
        }

        let landmarkFaces = (landmarkRequest.results ?? []).compactMap { obs in
            buildDetectedFace(from: obs, imageWidth: imageWidth, imageHeight: imageHeight)
        }

        let rectOnlyFaces = (rectRequest.results ?? []).compactMap { obs in
            buildEstimatedFace(from: obs, imageWidth: imageWidth, imageHeight: imageHeight)
        }

        if landmarkFaces.isEmpty && rectOnlyFaces.isEmpty { return nil }
        if landmarkFaces.isEmpty { return rectOnlyFaces }
        if rectOnlyFaces.isEmpty { return landmarkFaces }

        // Merge: keep all landmark faces, add rectangle-only faces that don't overlap
        var merged = landmarkFaces
        for rectFace in rectOnlyFaces {
            let overlaps = landmarkFaces.contains { existing in
                existing.boundingBox.intersects(rectFace.boundingBox)
            }
            if !overlaps { merged.append(rectFace) }
        }

        #if DEBUG
        if merged.count > landmarkFaces.count {
            print("FaceDetectionService: rectangles found \(merged.count - landmarkFaces.count) extra face(s) landmarks missed")
        }
        #endif

        return merged
    }

    /// Standalone rectangle fallback for CIDetector path.
    private func detectWithRectanglesOnly(cgImage: CGImage, orientation: CGImagePropertyOrientation, imageWidth: CGFloat, imageHeight: CGFloat) -> [DetectedFace]? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
        } catch {
            #if DEBUG
            print("FaceDetectionService: rectangles fallback also failed — \(error.localizedDescription)")
            #endif
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else { return nil }

        #if DEBUG
        print("FaceDetectionService: using rectangle fallback for \(observations.count) face(s)")
        #endif

        return observations.compactMap { obs in
            buildEstimatedFace(from: obs, imageWidth: imageWidth, imageHeight: imageHeight)
        }
    }

    /// Build a DetectedFace from a rectangle-only observation using estimated
    /// proportional positions for eyes, brows, and contour based on average
    /// facial geometry ratios.
    private func buildEstimatedFace(from obs: VNFaceObservation, imageWidth: CGFloat, imageHeight: CGFloat) -> DetectedFace {
        let bb = obs.boundingBox
        let boxInImage = CGRect(
            x: bb.origin.x * imageWidth,
            y: bb.origin.y * imageHeight,
            width: bb.width * imageWidth,
            height: bb.height * imageHeight
        )
        let center = CGPoint(x: boxInImage.midX, y: boxInImage.midY)
        let w = boxInImage.width
        let h = boxInImage.height

        let eyeY = boxInImage.origin.y + h * 0.65
        let leftPupil = CGPoint(x: center.x - w * 0.18, y: eyeY)
        let rightPupil = CGPoint(x: center.x + w * 0.18, y: eyeY)
        let eyeWidth = w * 0.16

        let browY = boxInImage.origin.y + h * 0.75
        let leftBrow = [
            CGPoint(x: center.x - w * 0.28, y: browY),
            CGPoint(x: center.x - w * 0.18, y: browY + h * 0.03),
            CGPoint(x: center.x - w * 0.08, y: browY)
        ]
        let rightBrow = [
            CGPoint(x: center.x + w * 0.08, y: browY),
            CGPoint(x: center.x + w * 0.18, y: browY + h * 0.03),
            CGPoint(x: center.x + w * 0.28, y: browY)
        ]

        let chinY = boxInImage.origin.y
        let contour = [
            CGPoint(x: center.x - w * 0.4, y: center.y),
            CGPoint(x: center.x - w * 0.35, y: chinY + h * 0.15),
            CGPoint(x: center.x, y: chinY),
            CGPoint(x: center.x + w * 0.35, y: chinY + h * 0.15),
            CGPoint(x: center.x + w * 0.4, y: center.y)
        ]

        return DetectedFace(
            boundingBox: boxInImage, faceCenter: center,
            faceWidth: w, faceHeight: h,
            leftPupilCenter: leftPupil, rightPupilCenter: rightPupil,
            leftEyeWidth: eyeWidth, rightEyeWidth: eyeWidth,
            leftEyebrowPoints: leftBrow, rightEyebrowPoints: rightBrow,
            faceContourPoints: contour, normalizedBoundingBox: bb
        )
    }

    /// Last-resort fallback using CIDetector, which works on all platforms
    /// including "Designed for iPad" on Mac where Vision fails entirely.
    /// We fix the image orientation first so CIDetector sees upright faces
    /// and returns coordinates in the correctly-oriented pixel space.
    private func detectWithCIDetector(image: UIImage) -> [DetectedFace]? {
        let oriented = fixOrientation(image)
        guard let cgImage = oriented.cgImage else { return nil }
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        let ciImage = CIImage(cgImage: cgImage)
        guard let detector = CIDetector(
            ofType: CIDetectorTypeFace,
            context: ciContext,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ) else {
            #if DEBUG
            print("FaceDetectionService: CIDetector failed to initialize")
            #endif
            return nil
        }

        let features = detector.features(in: ciImage, options: [CIDetectorSmile: false, CIDetectorEyeBlink: false])
        let faceFeatures = features.compactMap { $0 as? CIFaceFeature }
        guard !faceFeatures.isEmpty else {
            #if DEBUG
            print("FaceDetectionService: CIDetector found 0 faces in image (\(Int(imageWidth))x\(Int(imageHeight)))")
            #endif
            return nil
        }

        #if DEBUG
        print("FaceDetectionService: using CIDetector fallback for \(faceFeatures.count) face(s)")
        #endif

        return faceFeatures.map { feature in
            buildFaceFromCIFeature(feature, imageWidth: imageWidth, imageHeight: imageHeight)
        }
    }

    // MARK: - Animal Detection

    /// Detect cat/dog faces by running both body pose and recognition in parallel,
    /// then merging results. Body pose gives precise landmarks but needs a visible body;
    /// recognition gives bounding boxes and works even when the body is mostly hidden.
    private func detectAnimals(cgImage: CGImage, orientation: CGImagePropertyOrientation, imageWidth: CGFloat, imageHeight: CGFloat) -> [DetectedFace]? {
        let poseFaces = detectAnimalBodyPose(cgImage: cgImage, orientation: orientation, imageWidth: imageWidth, imageHeight: imageHeight) ?? []
        let boxFaces = detectAnimalBoundingBoxes(cgImage: cgImage, orientation: orientation, imageWidth: imageWidth, imageHeight: imageHeight) ?? []

        if poseFaces.isEmpty && boxFaces.isEmpty { return nil }

        // If we got pose results, prefer those; add any box results that don't
        // overlap with existing pose detections (for animals pose missed).
        if poseFaces.isEmpty { return boxFaces }
        if boxFaces.isEmpty { return poseFaces }

        var merged = poseFaces
        for boxFace in boxFaces {
            let overlaps = poseFaces.contains { existing in
                existing.boundingBox.intersects(boxFace.boundingBox)
            }
            if !overlaps { merged.append(boxFace) }
        }
        return merged
    }

    private func detectAnimalBodyPose(cgImage: CGImage, orientation: CGImagePropertyOrientation, imageWidth: CGFloat, imageHeight: CGFloat) -> [DetectedFace]? {
        let request = VNDetectAnimalBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
        } catch {
            #if DEBUG
            print("FaceDetectionService: animal body pose detection failed — \(error.localizedDescription)")
            #endif
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else { return nil }

        let faces = observations.compactMap { obs in
            buildAnimalFace(from: obs, imageWidth: imageWidth, imageHeight: imageHeight)
        }

        guard !faces.isEmpty else { return nil }

        #if DEBUG
        print("FaceDetectionService: animal body pose found \(faces.count) animal(s)")
        #endif
        return faces
    }

    /// Fallback: detect animals by bounding box when body pose fails
    /// (e.g., partially hidden body, unusual pose). Estimates eye positions
    /// from the bounding box using typical cat/dog facial proportions.
    private func detectAnimalBoundingBoxes(cgImage: CGImage, orientation: CGImagePropertyOrientation, imageWidth: CGFloat, imageHeight: CGFloat) -> [DetectedFace]? {
        let request = VNRecognizeAnimalsRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
        } catch {
            #if DEBUG
            print("FaceDetectionService: animal recognition failed — \(error.localizedDescription)")
            #endif
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else { return nil }

        #if DEBUG
        print("FaceDetectionService: animal recognition found \(observations.count) animal(s) (bounding box fallback)")
        #endif

        return observations.compactMap { obs in
            buildEstimatedAnimalFace(from: obs, imageWidth: imageWidth, imageHeight: imageHeight)
        }
    }

    /// Build a DetectedFace from a bounding-box-only animal observation.
    /// The bounding box covers the whole visible body, so we estimate the head
    /// as the top ~45% of the box and place eyes within that region.
    private func buildEstimatedAnimalFace(from obs: VNRecognizedObjectObservation, imageWidth: CGFloat, imageHeight: CGFloat) -> DetectedFace? {
        let bb = obs.boundingBox
        let bodyBox = CGRect(
            x: bb.origin.x * imageWidth,
            y: bb.origin.y * imageHeight,
            width: bb.width * imageWidth,
            height: bb.height * imageHeight
        )

        // Estimate head region as the upper portion of the body box
        // In CIImage coords (bottom-left origin), "upper" means higher Y
        let headH = bodyBox.height * 0.45
        let headBox = CGRect(
            x: bodyBox.origin.x,
            y: bodyBox.origin.y + bodyBox.height - headH,
            width: bodyBox.width,
            height: headH
        )

        let w = headBox.width
        let h = headBox.height
        let center = CGPoint(x: headBox.midX, y: headBox.midY)

        let eyeY = headBox.origin.y + h * 0.55
        let eyeSpread = w * 0.17
        let leftPupil = CGPoint(x: center.x - eyeSpread, y: eyeY)
        let rightPupil = CGPoint(x: center.x + eyeSpread, y: eyeY)
        let eyeWidth = w * 0.12

        let browOffsetY = h * 0.08
        let leftBrow = [
            CGPoint(x: leftPupil.x - eyeWidth, y: leftPupil.y + browOffsetY),
            CGPoint(x: leftPupil.x, y: leftPupil.y + browOffsetY + h * 0.02),
            CGPoint(x: leftPupil.x + eyeWidth, y: leftPupil.y + browOffsetY)
        ]
        let rightBrow = [
            CGPoint(x: rightPupil.x - eyeWidth, y: rightPupil.y + browOffsetY),
            CGPoint(x: rightPupil.x, y: rightPupil.y + browOffsetY + h * 0.02),
            CGPoint(x: rightPupil.x + eyeWidth, y: rightPupil.y + browOffsetY)
        ]

        let contour = [
            CGPoint(x: headBox.minX, y: center.y),
            CGPoint(x: headBox.minX + w * 0.15, y: headBox.minY),
            CGPoint(x: center.x, y: headBox.minY),
            CGPoint(x: headBox.maxX - w * 0.15, y: headBox.minY),
            CGPoint(x: headBox.maxX, y: center.y)
        ]

        // Use the head box for the overlay, not the full body
        let normalizedHeadBB = CGRect(
            x: headBox.origin.x / imageWidth,
            y: headBox.origin.y / imageHeight,
            width: w / imageWidth,
            height: h / imageHeight
        )

        return DetectedFace(
            boundingBox: headBox, faceCenter: center,
            faceWidth: w, faceHeight: h,
            leftPupilCenter: leftPupil, rightPupilCenter: rightPupil,
            leftEyeWidth: eyeWidth, rightEyeWidth: eyeWidth,
            leftEyebrowPoints: leftBrow, rightEyebrowPoints: rightBrow,
            faceContourPoints: contour, normalizedBoundingBox: normalizedHeadBB
        )
    }

    /// Build a DetectedFace from an animal body pose observation.
    /// Accepts partial landmark data: works with both eyes, one eye + nose,
    /// or even just nose + ears. Estimates missing positions from available ones.
    private func buildAnimalFace(from obs: VNAnimalBodyPoseObservation, imageWidth: CGFloat, imageHeight: CGFloat) -> DetectedFace? {
        let minConf: Float = 0.15

        func pt(_ name: VNAnimalBodyPoseObservation.JointName) -> CGPoint? {
            guard let p = try? obs.recognizedPoint(name), p.confidence > minConf else { return nil }
            return CGPoint(x: p.location.x * imageWidth, y: p.location.y * imageHeight)
        }

        let leftEyeRaw = pt(.leftEye)
        let rightEyeRaw = pt(.rightEye)
        let nose = pt(.nose)
        let leftEarTop = pt(.leftEarTop)
        let rightEarTop = pt(.rightEarTop)
        let leftEarBottom = pt(.leftEarBottom)
        let rightEarBottom = pt(.rightEarBottom)

        // Need at least two head points to position a face
        let allHeadPts = [leftEyeRaw, rightEyeRaw, nose, leftEarTop, rightEarTop, leftEarBottom, rightEarBottom].compactMap { $0 }
        guard allHeadPts.count >= 2 else { return nil }

        // Derive eye positions: use detected eyes, or estimate from other landmarks
        let leftEye: CGPoint
        let rightEye: CGPoint

        if let le = leftEyeRaw, let re = rightEyeRaw {
            leftEye = le
            rightEye = re
        } else if let le = leftEyeRaw, let n = nose {
            leftEye = le
            let dx = le.x - n.x
            let dy = le.y - n.y
            rightEye = CGPoint(x: n.x - dx, y: n.y - dy)
        } else if let re = rightEyeRaw, let n = nose {
            rightEye = re
            let dx = re.x - n.x
            let dy = re.y - n.y
            leftEye = CGPoint(x: n.x - dx, y: n.y - dy)
        } else if let n = nose {
            let earSpan: CGFloat
            if let le = leftEarBottom, let re = rightEarBottom {
                earSpan = abs(re.x - le.x) * 0.35
            } else if let le = leftEarTop, let re = rightEarTop {
                earSpan = abs(re.x - le.x) * 0.35
            } else {
                earSpan = imageWidth * 0.04
            }
            leftEye = CGPoint(x: n.x - earSpan, y: n.y + earSpan * 0.8)
            rightEye = CGPoint(x: n.x + earSpan, y: n.y + earSpan * 0.8)
        } else if let le = leftEarBottom ?? leftEarTop, let re = rightEarBottom ?? rightEarTop {
            let midX = (le.x + re.x) / 2
            let midY = (le.y + re.y) / 2
            let span = abs(re.x - le.x) * 0.3
            leftEye = CGPoint(x: midX - span, y: midY - span * 0.5)
            rightEye = CGPoint(x: midX + span, y: midY - span * 0.5)
        } else {
            return nil
        }

        // Bounding box from all head points + derived eyes
        let boxPts = allHeadPts + [leftEye, rightEye]
        let xs = boxPts.map(\.x)
        let ys = boxPts.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }

        let rawW = max(maxX - minX, 1)
        let rawH = max(maxY - minY, 1)
        let padX = rawW * 0.25
        let padY = rawH * 0.25
        let boundingBox = CGRect(
            x: max(0, minX - padX),
            y: max(0, minY - padY),
            width: min(imageWidth - max(0, minX - padX), rawW + padX * 2),
            height: min(imageHeight - max(0, minY - padY), rawH + padY * 2)
        )
        let center = CGPoint(x: boundingBox.midX, y: boundingBox.midY)

        let interEyeDistance = max(hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y), 1)
        let eyeWidth = interEyeDistance * 0.25

        let browOffsetY = boundingBox.height * 0.08
        let leftBrow = [
            CGPoint(x: leftEye.x - eyeWidth, y: leftEye.y + browOffsetY),
            CGPoint(x: leftEye.x, y: leftEye.y + browOffsetY + boundingBox.height * 0.02),
            CGPoint(x: leftEye.x + eyeWidth, y: leftEye.y + browOffsetY)
        ]
        let rightBrow = [
            CGPoint(x: rightEye.x - eyeWidth, y: rightEye.y + browOffsetY),
            CGPoint(x: rightEye.x, y: rightEye.y + browOffsetY + boundingBox.height * 0.02),
            CGPoint(x: rightEye.x + eyeWidth, y: rightEye.y + browOffsetY)
        ]

        let contour = [
            CGPoint(x: boundingBox.minX, y: center.y),
            CGPoint(x: boundingBox.minX + boundingBox.width * 0.15, y: boundingBox.minY),
            CGPoint(x: center.x, y: boundingBox.minY),
            CGPoint(x: boundingBox.maxX - boundingBox.width * 0.15, y: boundingBox.minY),
            CGPoint(x: boundingBox.maxX, y: center.y)
        ]

        let normalizedBB = CGRect(
            x: boundingBox.origin.x / imageWidth,
            y: boundingBox.origin.y / imageHeight,
            width: boundingBox.width / imageWidth,
            height: boundingBox.height / imageHeight
        )

        return DetectedFace(
            boundingBox: boundingBox, faceCenter: center,
            faceWidth: boundingBox.width, faceHeight: boundingBox.height,
            leftPupilCenter: leftEye, rightPupilCenter: rightEye,
            leftEyeWidth: eyeWidth, rightEyeWidth: eyeWidth,
            leftEyebrowPoints: leftBrow, rightEyebrowPoints: rightBrow,
            faceContourPoints: contour, normalizedBoundingBox: normalizedBB
        )
    }

    /// Creates a new UIImage with `.up` orientation by redrawing pixels.
    private func fixOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let result = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return result
    }

    /// Build a DetectedFace from CIFaceFeature. CIDetector gives us face bounds,
    /// eye centers, and mouth center -- all in CIImage coordinates (bottom-left origin).
    /// We estimate brow and contour positions from these known points.
    private func buildFaceFromCIFeature(_ feature: CIFaceFeature, imageWidth: CGFloat, imageHeight: CGFloat) -> DetectedFace {
        let bounds = feature.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let w = bounds.width
        let h = bounds.height

        let leftPupil: CGPoint?
        if feature.hasLeftEyePosition {
            leftPupil = feature.leftEyePosition
        } else {
            leftPupil = CGPoint(x: center.x - w * 0.18, y: center.y + h * 0.12)
        }

        let rightPupil: CGPoint?
        if feature.hasRightEyePosition {
            rightPupil = feature.rightEyePosition
        } else {
            rightPupil = CGPoint(x: center.x + w * 0.18, y: center.y + h * 0.12)
        }

        let eyeWidth = w * 0.16

        let browOffsetY = h * 0.1
        let leftBrowCenter = leftPupil ?? CGPoint(x: center.x - w * 0.18, y: center.y + h * 0.12)
        let rightBrowCenter = rightPupil ?? CGPoint(x: center.x + w * 0.18, y: center.y + h * 0.12)

        let leftBrow = [
            CGPoint(x: leftBrowCenter.x - w * 0.1, y: leftBrowCenter.y + browOffsetY),
            CGPoint(x: leftBrowCenter.x, y: leftBrowCenter.y + browOffsetY + h * 0.02),
            CGPoint(x: leftBrowCenter.x + w * 0.1, y: leftBrowCenter.y + browOffsetY)
        ]
        let rightBrow = [
            CGPoint(x: rightBrowCenter.x - w * 0.1, y: rightBrowCenter.y + browOffsetY),
            CGPoint(x: rightBrowCenter.x, y: rightBrowCenter.y + browOffsetY + h * 0.02),
            CGPoint(x: rightBrowCenter.x + w * 0.1, y: rightBrowCenter.y + browOffsetY)
        ]

        let chinY = bounds.origin.y
        let contour = [
            CGPoint(x: center.x - w * 0.4, y: center.y),
            CGPoint(x: center.x - w * 0.35, y: chinY + h * 0.15),
            CGPoint(x: center.x, y: chinY),
            CGPoint(x: center.x + w * 0.35, y: chinY + h * 0.15),
            CGPoint(x: center.x + w * 0.4, y: center.y)
        ]

        let normalizedBB = CGRect(
            x: bounds.origin.x / imageWidth,
            y: bounds.origin.y / imageHeight,
            width: w / imageWidth,
            height: h / imageHeight
        )

        return DetectedFace(
            boundingBox: bounds, faceCenter: center,
            faceWidth: w, faceHeight: h,
            leftPupilCenter: leftPupil, rightPupilCenter: rightPupil,
            leftEyeWidth: eyeWidth, rightEyeWidth: eyeWidth,
            leftEyebrowPoints: leftBrow, rightEyebrowPoints: rightBrow,
            faceContourPoints: contour, normalizedBoundingBox: normalizedBB
        )
    }

    /// Force re-detection by clearing cache first, then running detection.
    func redetect(in image: UIImage) async -> [DetectedFace] {
        clearCache()
        return await detectFaces(in: image)
    }

    func clearCache() {
        cachedImageHash = nil
        cachedFaces = []
    }

    // MARK: - Private

    private func buildDetectedFace(from obs: VNFaceObservation, imageWidth: CGFloat, imageHeight: CGFloat) -> DetectedFace? {
        let bb = obs.boundingBox
        let boxInImage = CGRect(
            x: bb.origin.x * imageWidth,
            y: bb.origin.y * imageHeight,
            width: bb.width * imageWidth,
            height: bb.height * imageHeight
        )
        let center = CGPoint(x: boxInImage.midX, y: boxInImage.midY)

        guard let landmarks = obs.landmarks else {
            return DetectedFace(
                boundingBox: boxInImage, faceCenter: center,
                faceWidth: boxInImage.width, faceHeight: boxInImage.height,
                leftPupilCenter: nil, rightPupilCenter: nil,
                leftEyeWidth: 0, rightEyeWidth: 0,
                leftEyebrowPoints: [], rightEyebrowPoints: [],
                faceContourPoints: [], normalizedBoundingBox: bb
            )
        }

        let leftPupil = centroid(of: landmarks.leftPupil, bb: bb, imgW: imageWidth, imgH: imageHeight)
        let rightPupil = centroid(of: landmarks.rightPupil, bb: bb, imgW: imageWidth, imgH: imageHeight)

        let leftEyeW = regionWidth(of: landmarks.leftEye, bb: bb, imgW: imageWidth)
        let rightEyeW = regionWidth(of: landmarks.rightEye, bb: bb, imgW: imageWidth)

        let leftBrow = convertPoints(landmarks.leftEyebrow, bb: bb, imgW: imageWidth, imgH: imageHeight)
        let rightBrow = convertPoints(landmarks.rightEyebrow, bb: bb, imgW: imageWidth, imgH: imageHeight)
        let contour = convertPoints(landmarks.faceContour, bb: bb, imgW: imageWidth, imgH: imageHeight)

        // Full region outlines for whole-feature effects. Vision returns these already;
        // the flat fields above only keep a centre or width. Any of these may be nil for
        // a partially-detected face, so each resolves to an empty array independently.
        let regions = FaceRegions(
            leftEye: convertPoints(landmarks.leftEye, bb: bb, imgW: imageWidth, imgH: imageHeight),
            rightEye: convertPoints(landmarks.rightEye, bb: bb, imgW: imageWidth, imgH: imageHeight),
            outerLips: convertPoints(landmarks.outerLips, bb: bb, imgW: imageWidth, imgH: imageHeight),
            innerLips: convertPoints(landmarks.innerLips, bb: bb, imgW: imageWidth, imgH: imageHeight),
            nose: convertPoints(landmarks.nose, bb: bb, imgW: imageWidth, imgH: imageHeight)
        )

        return DetectedFace(
            boundingBox: boxInImage, faceCenter: center,
            faceWidth: boxInImage.width, faceHeight: boxInImage.height,
            leftPupilCenter: leftPupil, rightPupilCenter: rightPupil,
            leftEyeWidth: leftEyeW, rightEyeWidth: rightEyeW,
            leftEyebrowPoints: leftBrow, rightEyebrowPoints: rightBrow,
            faceContourPoints: contour, normalizedBoundingBox: bb,
            regions: regions, landmarkQuality: .precise,
            roll: obs.roll?.doubleValue ?? 0,
            yaw: obs.yaw?.doubleValue ?? 0,
            pitch: obs.pitch?.doubleValue ?? 0
        )
    }

    /// Convert a landmark region's points to image coordinates.
    private func convertPoints(_ region: VNFaceLandmarkRegion2D?, bb: CGRect, imgW: CGFloat, imgH: CGFloat) -> [CGPoint] {
        guard let region else { return [] }
        return region.normalizedPoints.map { pt in
            CGPoint(x: (bb.origin.x + pt.x * bb.width) * imgW,
                    y: (bb.origin.y + pt.y * bb.height) * imgH)
        }
    }

    /// Get the centroid of a landmark region in image coordinates.
    private func centroid(of region: VNFaceLandmarkRegion2D?, bb: CGRect, imgW: CGFloat, imgH: CGFloat) -> CGPoint? {
        guard let region, region.pointCount > 0 else { return nil }
        let points = convertPoints(region, bb: bb, imgW: imgW, imgH: imgH)
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        return CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))
    }

    /// Width of a landmark region in image pixels.
    private func regionWidth(of region: VNFaceLandmarkRegion2D?, bb: CGRect, imgW: CGFloat) -> CGFloat {
        guard let region, region.pointCount > 1 else { return 0 }
        let xs = region.normalizedPoints.map { (bb.origin.x + $0.x * bb.width) * imgW }
        return (xs.max() ?? 0) - (xs.min() ?? 0)
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
