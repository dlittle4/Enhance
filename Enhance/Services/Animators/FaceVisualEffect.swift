import CoreImage

/// Adapter that wraps any VisualEffect into a FaceEffect by centering it
/// on the detected face and masking the result to the face region only.
struct FaceVisualEffect: FaceEffect {
    private let wrappedEffect: VisualEffect
    private let maskScale: CGFloat
    private let skipDelay: Bool
    private let passRawProgress: Bool

    /// - Parameters:
    ///   - effect: The visual effect to apply.
    ///   - maskScale: How large the face mask is relative to face size (default 1.0).
    ///   - skipDelay: If true, starts the effect from progress=0 instead of delaying to 0.3.
    ///   - passRawProgress: If true, passes progress directly to the effect without
    ///     the quadratic ramp (useful for effects like Pixelate that have their own curve).
    init(effect: VisualEffect, maskScale: CGFloat = 1.0, skipDelay: Bool = false, passRawProgress: Bool = false) {
        self.wrappedEffect = effect
        self.maskScale = maskScale
        self.skipDelay = skipDelay
        self.passRawProgress = passRawProgress
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let effectProgress: CGFloat
        if skipDelay {
            effectProgress = passRawProgress ? progress : progress * progress
        } else {
            guard progress > 0.3 else { return image }
            let ramp = (progress - 0.3) / 0.7
            effectProgress = passRawProgress ? ramp : ramp * ramp
        }

        let faceCenter = CGPoint(x: face.faceCenter.x, y: face.faceCenter.y)
        let distorted = wrappedEffect.apply(
            to: image, progress: effectProgress, frameIndex: frameIndex,
            viewportCenter: faceCenter
        )

        let radius = max(face.faceWidth, face.faceHeight) * 0.8 * maskScale
        let center = CIVector(x: faceCenter.x, y: faceCenter.y)
        let mask = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": center,
            "inputRadius0": radius * 0.65,
            "inputRadius1": radius,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ])!.outputImage!.cropped(to: image.extent)

        return distorted.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: mask
        ]).cropped(to: image.extent)
    }
}
