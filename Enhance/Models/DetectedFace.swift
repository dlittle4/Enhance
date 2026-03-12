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
}
