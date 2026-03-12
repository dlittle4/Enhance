import CoreImage

/// Overlays bright red glowing eyes with full-width horizontal lens flare beams
/// at the detected pupil positions. Uses additive compositing for realistic
/// light bloom. The flare extends edge-to-edge across the entire image.
/// Intensity controls glow radius and brightness.
struct LazerEyesEffect: FaceEffect {
    private let intensityScale: CGFloat
    private let sizeScale: CGFloat

    init(intensity: Double = 0.5, size: Double = 0.5) {
        self.intensityScale = max(0.1, CGFloat(intensity))
        self.sizeScale = 0.3 + 1.7 * CGFloat(max(0, min(1, size)))
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        guard progress > 0.3 else { return image }

        let ramp = (progress - 0.3) / 0.7
        let fade = ramp * ramp
        let imageWidth = image.extent.width
        var result = image

        if let leftPupil = face.leftPupilCenter {
            let eyeRadius = max(face.leftEyeWidth, face.faceWidth * 0.06)
            result = compositeEyeGlow(over: result, center: leftPupil, eyeRadius: eyeRadius, imageWidth: imageWidth, opacity: fade, frameIndex: frameIndex, seed: 0)
        }

        if let rightPupil = face.rightPupilCenter {
            let eyeRadius = max(face.rightEyeWidth, face.faceWidth * 0.06)
            result = compositeEyeGlow(over: result, center: rightPupil, eyeRadius: eyeRadius, imageWidth: imageWidth, opacity: fade, frameIndex: frameIndex, seed: 7)
        }

        return result.cropped(to: image.extent)
    }

    // MARK: - Eye Glow Compositing

    private func compositeEyeGlow(over image: CIImage, center: CGPoint, eyeRadius: CGFloat, imageWidth: CGFloat, opacity: CGFloat, frameIndex: Int, seed: Int) -> CIImage {
        let coreRadius = eyeRadius * 0.5 * intensityScale * sizeScale
        let glowRadius = eyeRadius * 1.8 * intensityScale * sizeScale
        let bloomRadius = eyeRadius * 4.0 * intensityScale * sizeScale

        let flicker = flickerMultiplier(frameIndex: frameIndex, seed: seed)
        let alpha = opacity * flicker

        // Bright white-hot core at each pupil
        let core = makeRadialGlow(
            center: center,
            innerRadius: max(1, coreRadius * 0.5),
            outerRadius: coreRadius,
            color: CIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: alpha)
        )

        // Orange-red inner glow
        let innerGlow = makeRadialGlow(
            center: center,
            innerRadius: max(1, glowRadius * 0.15),
            outerRadius: glowRadius,
            color: CIColor(red: 1.0, green: 0.15, blue: 0.05, alpha: alpha * 0.95)
        )

        // Wide soft red bloom
        let bloom = makeRadialGlow(
            center: center,
            innerRadius: max(1, bloomRadius * 0.08),
            outerRadius: bloomRadius,
            color: CIColor(red: 0.9, green: 0.03, blue: 0.0, alpha: alpha * 0.5)
        )

        let flareWidth = imageWidth * sizeScale
        // Narrow bright beam
        let narrowFlare = makeHorizontalFlare(
            center: center,
            width: flareWidth,
            height: eyeRadius * 0.4 * intensityScale * sizeScale,
            color: CIColor(red: 1.0, green: 0.25, blue: 0.1, alpha: alpha * 0.85)
        )

        // Wide soft atmospheric glow beam
        let wideFlare = makeHorizontalFlare(
            center: center,
            width: flareWidth,
            height: eyeRadius * 2.0 * intensityScale * sizeScale,
            color: CIColor(red: 0.8, green: 0.04, blue: 0.0, alpha: alpha * 0.35)
        )

        guard let addFilter = CIFilter(name: "CIAdditionCompositing") else { return image }

        var result = image
        for layer in [wideFlare, bloom, narrowFlare, innerGlow, core] {
            guard let layer = layer else { continue }
            addFilter.setValue(layer, forKey: kCIInputImageKey)
            addFilter.setValue(result, forKey: kCIInputBackgroundImageKey)
            if let out = addFilter.outputImage {
                result = out
            }
        }

        return result
    }

    // MARK: - Glow Layers

    private func makeRadialGlow(center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, color: CIColor) -> CIImage? {
        let diameter = outerRadius * 2 + 4
        let localCenter = CIVector(x: diameter / 2, y: diameter / 2)

        guard let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            kCIInputCenterKey: localCenter,
            "inputRadius0": innerRadius,
            "inputRadius1": outerRadius,
            "inputColor0": color,
            "inputColor1": CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        ])?.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: diameter, height: diameter)) else {
            return nil
        }

        return gradient.transformed(by: CGAffineTransform(
            translationX: center.x - diameter / 2,
            y: center.y - diameter / 2
        ))
    }

    /// Full-width horizontal lens flare beam using a vertically-squashed radial gradient.
    private func makeHorizontalFlare(center: CGPoint, width: CGFloat, height: CGFloat, color: CIColor) -> CIImage? {
        let canvasW = width + 4
        let canvasH = canvasW
        let localCenter = CIVector(x: canvasW / 2, y: canvasH / 2)
        let radius = canvasW / 2

        guard let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            kCIInputCenterKey: localCenter,
            "inputRadius0": radius * 0.01,
            "inputRadius1": radius,
            "inputColor0": color,
            "inputColor1": CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        ])?.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: canvasW, height: canvasH)) else {
            return nil
        }

        let scaleY = height / canvasH
        let transform = CGAffineTransform(translationX: 0, y: canvasH / 2)
            .scaledBy(x: 1.0, y: scaleY)
            .translatedBy(x: 0, y: -canvasH / 2)

        let squashed = gradient.transformed(by: transform)

        return squashed.transformed(by: CGAffineTransform(
            translationX: center.x - canvasW / 2,
            y: center.y - canvasH * scaleY / 2
        ))
    }

    /// Subtle per-frame brightness variation to simulate energy flicker.
    private func flickerMultiplier(frameIndex: Int, seed: Int) -> CGFloat {
        var x = UInt64(frameIndex * 137 + seed * 31 + 53)
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        let norm = CGFloat(x % 1000) / 1000.0
        return 0.88 + norm * 0.12
    }
}
