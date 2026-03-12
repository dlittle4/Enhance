import CoreImage

/// Pinches the center of the face inward, creating a Photo Booth-style
/// "squeeze" distortion isolated to the face region only. Uses CIPinchDistortion
/// blended through a radial mask so the background stays undistorted.
struct SqueezeEffect: FaceEffect {
    private let maxPinch: CGFloat

    init(intensity: Double = 0.5) {
        self.maxPinch = CGFloat(max(0.1, min(1.0, intensity)))
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let pinch = maxPinch * CGFloat(progress * progress)

        let center = CIVector(x: face.faceCenter.x, y: face.faceCenter.y)
        let radius = max(face.faceWidth, face.faceHeight) * 1.2

        let clamped = image.clamped(to: image.extent)
        let distorted = clamped.applyingFilter("CIPinchDistortion", parameters: [
            kCIInputCenterKey: center,
            kCIInputRadiusKey: radius,
            kCIInputScaleKey: pinch
        ]).cropped(to: image.extent)

        // Radial mask: white over the face, fading to transparent at the edges.
        // Blend distorted face with original background so only the face is affected.
        let innerR = radius * 0.6
        let outerR = radius
        let mask = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": center,
            "inputRadius0": innerR,
            "inputRadius1": outerR,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ])!.outputImage!.cropped(to: image.extent)

        return distorted.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: mask
        ]).cropped(to: image.extent)
    }
}
