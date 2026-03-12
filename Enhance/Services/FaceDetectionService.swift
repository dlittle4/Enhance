import Vision
import UIKit
import CoreImage

/// Detects faces and landmarks in a still image.
/// Uses a three-tier detection strategy:
/// 1. Vision landmarks (best quality, requires Neural Engine)
/// 2. Vision rectangles (simpler, still needs Vision inference)
/// 3. CIDetector (Core Image, works everywhere including "Designed for iPad" on Mac)
/// Results are cached per image to avoid redundant detection.
final class FaceDetectionService {
    private var cachedImageHash: Int?
    private var cachedFaces: [DetectedFace] = []
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Detect faces in the given image. Returns cached results if the image hasn't changed.
    func detectFaces(in image: UIImage) async -> [DetectedFace] {
        let hash = image.hashValue
        if hash == cachedImageHash { return cachedFaces }

        guard let cgImage = image.cgImage else { return [] }
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let orientation = visionOrientation(from: image)

        var faces = detectWithLandmarks(cgImage: cgImage, orientation: orientation, imageWidth: imageWidth, imageHeight: imageHeight)

        if faces == nil {
            faces = detectWithRectanglesOnly(cgImage: cgImage, orientation: orientation, imageWidth: imageWidth, imageHeight: imageHeight)
        }

        if faces == nil {
            faces = detectWithCIDetector(image: image)
        }

        let result = faces ?? []
        #if DEBUG
        print("FaceDetectionService: detected \(result.count) face(s)")
        #endif
        cachedImageHash = hash
        cachedFaces = result
        return result
    }

    /// Primary path: full landmark detection.
    private func detectWithLandmarks(cgImage: CGImage, orientation: CGImagePropertyOrientation, imageWidth: CGFloat, imageHeight: CGFloat) -> [DetectedFace]? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
        } catch {
            #if DEBUG
            print("FaceDetectionService: landmarks failed, will try rectangles fallback — \(error.localizedDescription)")
            #endif
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else { return nil }

        return observations.compactMap { obs in
            buildDetectedFace(from: obs, imageWidth: imageWidth, imageHeight: imageHeight)
        }
    }

    /// Fallback path: bounding-box only detection with estimated landmark positions.
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

        return DetectedFace(
            boundingBox: boxInImage, faceCenter: center,
            faceWidth: boxInImage.width, faceHeight: boxInImage.height,
            leftPupilCenter: leftPupil, rightPupilCenter: rightPupil,
            leftEyeWidth: leftEyeW, rightEyeWidth: rightEyeW,
            leftEyebrowPoints: leftBrow, rightEyebrowPoints: rightBrow,
            faceContourPoints: contour, normalizedBoundingBox: bb
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
