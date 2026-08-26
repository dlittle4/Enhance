import CoreImage

/// A face-aware effect that transforms a CIImage using detected face landmarks.
/// Unlike `VisualEffect` (which operates on the whole image), face effects
/// target a specific `DetectedFace` and apply distortions at landmark coordinates.
protocol FaceEffect {
    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage

    /// Apply the effect to every face in one call.
    ///
    /// **This is a protocol requirement, not just an extension method, and that is
    /// load-bearing.** Both render paths hold the effect as a `FaceEffect` existential; a
    /// method that lived only in an extension would bind statically there, and an effect's
    /// override would silently never run — the same "passes for the wrong reason" shape as the
    /// coordinate trap recorded on §2a. As a requirement, dispatch is dynamic.
    ///
    /// The default (below) loops sequentially, feeding each face the previous result —
    /// byte-identical to what the callers used to do inline, so the other effects need no
    /// changes. An effect whose faces can *interact* — BIG HEAD's enlarged heads overlap —
    /// overrides this to see all faces at once, because a sequential pass re-processes pixels
    /// the previous face already changed (the recorded smear).
    ///
    /// Faces arrive already in `image`'s coordinate space; the callers own that conversion.
    func apply(to image: CIImage, faces: [DetectedFace], progress: CGFloat, frameIndex: Int) -> CIImage
}

extension FaceEffect {
    func apply(to image: CIImage, faces: [DetectedFace], progress: CGFloat, frameIndex: Int) -> CIImage {
        var result = image
        for face in faces {
            result = apply(to: result, face: face, progress: progress, frameIndex: frameIndex)
        }
        return result
    }
}
