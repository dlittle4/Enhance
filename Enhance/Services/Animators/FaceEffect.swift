import CoreImage

/// A face-aware effect that transforms a CIImage using detected face landmarks.
/// Unlike `VisualEffect` (which operates on the whole image), face effects
/// target a specific `DetectedFace` and apply distortions at landmark coordinates.
protocol FaceEffect {
    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage
}
