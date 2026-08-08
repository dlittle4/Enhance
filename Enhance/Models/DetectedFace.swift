import Vision
import CoreGraphics

/// Pre-computed face landmark positions in image coordinates (CIImage coordinate space).
/// Created by `FaceDetectionService` from a `VNFaceObservation`.
struct DetectedFace: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let faceCenter: CGPoint
    let faceWidth: CGFloat
    let faceHeight: CGFloat
    let leftPupilCenter: CGPoint?
    let rightPupilCenter: CGPoint?
    let leftEyeWidth: CGFloat
    let rightEyeWidth: CGFloat
    let leftEyebrowPoints: [CGPoint]
    let rightEyebrowPoints: [CGPoint]
    let faceContourPoints: [CGPoint]

    /// Normalized bounding box (0-1 range, bottom-left origin) for overlay positioning in SwiftUI.
    let normalizedBoundingBox: CGRect

    /// Landmark coordinates scaled to a differently-sized copy of the same image.
    ///
    /// Detection runs against the full-size source, but effects are applied to
    /// downscaled copies — the 650px live preview and the face-card thumbnails — so every
    /// consumer needs the same conversion. It lives here rather than being re-derived at
    /// each call site; three copies of this arithmetic is three chances to miss a field.
    ///
    /// `normalizedBoundingBox` is deliberately carried through unscaled: it is already
    /// resolution-independent, so scaling it would break the face overlays.
    func scaled(x scaleX: CGFloat, y scaleY: CGFloat) -> DetectedFace {
        DetectedFace(
            boundingBox: CGRect(
                x: boundingBox.origin.x * scaleX,
                y: boundingBox.origin.y * scaleY,
                width: boundingBox.width * scaleX,
                height: boundingBox.height * scaleY
            ),
            faceCenter: CGPoint(x: faceCenter.x * scaleX, y: faceCenter.y * scaleY),
            faceWidth: faceWidth * scaleX,
            faceHeight: faceHeight * scaleY,
            leftPupilCenter: leftPupilCenter.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) },
            rightPupilCenter: rightPupilCenter.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) },
            leftEyeWidth: leftEyeWidth * scaleX,
            rightEyeWidth: rightEyeWidth * scaleX,
            leftEyebrowPoints: leftEyebrowPoints.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) },
            rightEyebrowPoints: rightEyebrowPoints.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) },
            faceContourPoints: faceContourPoints.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) },
            normalizedBoundingBox: normalizedBoundingBox
        )
    }
}
