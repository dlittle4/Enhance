import CoreImage

/// CIFilter approximation of the "Handsome Squidward" meme aesthetic:
/// elongated jaw, defined cheekbones, and sharpened luminance for a
/// chiseled look. Distortions are masked to the face region so the
/// background stays undistorted.
struct HandsomeEffect: FaceEffect {
    private let maxStrength: CGFloat

    init(intensity: Double = 0.5) {
        self.maxStrength = max(0.1, 2.5 * CGFloat(intensity))
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let strength = maxStrength * (progress * progress)

        let extent = image.extent
        var result = image.clamped(to: extent)

        let chinY = face.boundingBox.origin.y
        let chinCenter = CIVector(x: face.faceCenter.x, y: chinY)
        let jawRadius = face.faceWidth * 0.5
        result = result.applyingFilter("CIBumpDistortion", parameters: [
            kCIInputCenterKey: chinCenter,
            kCIInputRadiusKey: jawRadius,
            kCIInputScaleKey: strength * 0.5
        ])

        let cheekY = face.faceCenter.y
        let cheekOffset = face.faceWidth * 0.35

        let leftCheek = CIVector(x: face.faceCenter.x - cheekOffset, y: cheekY)
        result = result.applyingFilter("CIBumpDistortion", parameters: [
            kCIInputCenterKey: leftCheek,
            kCIInputRadiusKey: face.faceWidth * 0.25,
            kCIInputScaleKey: strength * 0.4
        ])

        let rightCheek = CIVector(x: face.faceCenter.x + cheekOffset, y: cheekY)
        result = result.applyingFilter("CIBumpDistortion", parameters: [
            kCIInputCenterKey: rightCheek,
            kCIInputRadiusKey: face.faceWidth * 0.25,
            kCIInputScaleKey: strength * 0.4
        ])

        result = result.cropped(to: extent)

        let sharpness = min(strength * 2.0, 2.0)
        result = result.applyingFilter("CISharpenLuminance", parameters: [
            kCIInputSharpnessKey: sharpness,
            kCIInputRadiusKey: 2.0
        ]).cropped(to: extent)

        // Radial mask: isolate the effect to the face region only
        let maskRadius = max(face.faceWidth, face.faceHeight) * 0.8
        let center = CIVector(x: face.faceCenter.x, y: face.faceCenter.y)
        let mask = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": center,
            "inputRadius0": maskRadius * 0.7,
            "inputRadius1": maskRadius,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ])!.outputImage!.cropped(to: extent)

        return result.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: mask
        ]).cropped(to: extent)
    }
}
