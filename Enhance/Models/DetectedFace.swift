import Vision
import CoreGraphics

/// Full landmark-region polygons in image coordinates (CIImage space, same as the rest
/// of `DetectedFace`). Vision already returns these; the flat pupil/brow/contour fields
/// on `DetectedFace` discard most of them. Effects that copy a whole feature — Feature
/// Scrambler and its follow-ons — need the region outline, not just a centre point.
///
/// Empty arrays mean "not available for this face" (e.g. a rectangle-only or CIDetector
/// detection), which is why every consumer must tolerate an empty region.
struct FaceRegions: Hashable {
    var leftEye: [CGPoint] = []
    var rightEye: [CGPoint] = []
    var outerLips: [CGPoint] = []
    var innerLips: [CGPoint] = []
    var nose: [CGPoint] = []

    /// Scale every stored point. Mirrors `DetectedFace.scaled` — detection runs on the
    /// full-size source but effects run on downscaled copies.
    func scaled(x scaleX: CGFloat, y scaleY: CGFloat) -> FaceRegions {
        func s(_ pts: [CGPoint]) -> [CGPoint] {
            pts.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) }
        }
        return FaceRegions(
            leftEye: s(leftEye), rightEye: s(rightEye),
            outerLips: s(outerLips), innerLips: s(innerLips), nose: s(nose)
        )
    }
}

/// How trustworthy a face's landmark regions are. Precise regions come from Vision's
/// landmark request; everything else (rectangle fallback, CIDetector, animals) is a
/// proportional estimate and must not be treated as a real facial outline.
enum LandmarkQuality: Hashable {
    case precise
    case estimated
}

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

    /// Full landmark-region polygons for effects that copy a whole feature. Defaulted so
    /// the synthesized memberwise init stays source-compatible with the many existing call
    /// sites — only the precise Vision path populates it. Kept alongside the legacy pupil/
    /// brow/contour fields so current effects need not migrate at the same time.
    var regions: FaceRegions = FaceRegions()

    /// Whether `regions` are real Vision landmarks or a proportional estimate. Defaults to
    /// `.estimated`, the honest answer for every path that does not set it.
    var landmarkQuality: LandmarkQuality = .estimated

    /// Head pose in radians, from `VNFaceObservation` — 0 when the detector provides none
    /// (animals, CIDetector, estimated paths). Angles are scale-invariant, so `scaled()`
    /// carries them through untouched; dropping them there would silently disable pose-following
    /// in the preview, whose faces are always scaled copies.
    var roll: Double = 0
    var yaw: Double = 0
    var pitch: Double = 0

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
            normalizedBoundingBox: normalizedBoundingBox,
            regions: regions.scaled(x: scaleX, y: scaleY),
            landmarkQuality: landmarkQuality,
            roll: roll, yaw: yaw, pitch: pitch
        )
    }
}
