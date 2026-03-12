import CoreImage

/// Applies a strong CIBumpDistortion centered on the face to create a
/// bobblehead caricature -- enlarged head on a smaller-looking body.
/// Intensity controls the bulge strength. Uses CIAffineClamp to prevent
/// black border artifacts at image edges.
struct BobbleHeadEffect: FaceEffect {
    private let maxScale: CGFloat

    init(intensity: Double = 0.5) {
        self.maxScale = max(0.15, 0.8 * CGFloat(intensity))
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let scale = maxScale * (progress * progress)
        guard scale > 0.02 else { return image }

        let center = CIVector(x: face.faceCenter.x, y: face.faceCenter.y)
        let radius = face.faceHeight * 1.5

        let clamped = image.clamped(to: image.extent)
        let distorted = clamped.applyingFilter("CIBumpDistortion", parameters: [
            kCIInputCenterKey: center,
            kCIInputRadiusKey: radius,
            kCIInputScaleKey: scale
        ])
        return distorted.cropped(to: image.extent)
    }
}
