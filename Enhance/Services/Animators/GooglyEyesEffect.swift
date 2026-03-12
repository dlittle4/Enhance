import CoreImage

/// Overlays procedurally-generated googly eyes at the detected pupil positions.
/// Each eye is a white circle with a smaller black pupil that spins per frame.
/// Eyes scale up from zero with a spring bounce at the end rather than fading in.
/// `size` scales the eye relative to detected eye width.
/// `speed` controls how fast the pupil orbits (angular velocity per frame).
struct GooglyEyesEffect: FaceEffect {
    private let sizeMultiplier: CGFloat
    private let angularSpeed: CGFloat

    init(size: Double = 0.5, speed: Double = 0.5) {
        self.sizeMultiplier = 1.0 + 1.5 * CGFloat(max(0, min(1, size)))
        self.angularSpeed = 0.15 + 1.85 * CGFloat(max(0, min(1, speed)))
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        guard progress > 0.3 else { return image }

        let ramp = (progress - 0.3) / 0.7
        let scaleUp = springScale(ramp)
        var result = image

        if let leftPupil = face.leftPupilCenter {
            let baseRadius = max(face.leftEyeWidth, face.faceWidth * 0.06) * sizeMultiplier * 0.5
            result = compositeGooglyEye(over: result, center: leftPupil, radius: baseRadius * scaleUp, frameIndex: frameIndex, seed: 0)
        }

        if let rightPupil = face.rightPupilCenter {
            let baseRadius = max(face.rightEyeWidth, face.faceWidth * 0.06) * sizeMultiplier * 0.5
            result = compositeGooglyEye(over: result, center: rightPupil, radius: baseRadius * scaleUp, frameIndex: frameIndex, seed: 7)
        }

        return result.cropped(to: image.extent)
    }

    /// Quick growth to full size, then a pronounced damped spring bounce
    /// with 2-3 visible oscillations (peaks at ~1.5x, dips to ~0.8x, settles at 1.0).
    private func springScale(_ t: CGFloat) -> CGFloat {
        if t < 0.35 {
            return t / 0.35
        }
        let bounceT = (t - 0.35) / 0.65
        return 1.0 + 0.5 * exp(-3.5 * bounceT) * sin(bounceT * 3.5 * .pi)
    }

    private func compositeGooglyEye(over image: CIImage, center: CGPoint, radius: CGFloat, frameIndex: Int, seed: Int) -> CIImage {
        guard radius > 0.5 else { return image }
        let diameter = radius * 2
        let pupilRadius = radius * 0.45

        let white = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        guard let whiteCircle = CIFilter(name: "CIRadialGradient", parameters: [
            kCIInputCenterKey: CIVector(x: radius, y: radius),
            "inputRadius0": radius - 1,
            "inputRadius1": radius,
            "inputColor0": white,
            "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 0)
        ])?.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: diameter, height: diameter)) else {
            return image
        }

        let angle = CGFloat(frameIndex) * angularSpeed + CGFloat(seed)
        let wobbleDistance = (radius - pupilRadius) * 0.6
        let pupilOffsetX = cos(angle) * wobbleDistance
        let pupilOffsetY = sin(angle) * wobbleDistance

        let black = CIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        guard let pupilCircle = CIFilter(name: "CIRadialGradient", parameters: [
            kCIInputCenterKey: CIVector(x: radius + pupilOffsetX, y: radius + pupilOffsetY),
            "inputRadius0": pupilRadius - 1,
            "inputRadius1": pupilRadius,
            "inputColor0": black,
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ])?.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: diameter, height: diameter)) else {
            return image
        }

        let eye = pupilCircle.composited(over: whiteCircle)
        let positioned = eye.transformed(by: CGAffineTransform(
            translationX: center.x - radius,
            y: center.y - radius
        ))

        return positioned.composited(over: image)
    }
}
