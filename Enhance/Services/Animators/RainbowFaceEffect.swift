import CoreImage
import UIKit

/// Radial rainbow rings that pulse outward from the detected face,
/// with the face itself kept clear via a feathered elliptical mask.
struct RainbowFaceEffect: FaceEffect {
    private let maxOpacity: CGFloat
    private let pulseSpeedMultiplier: CGFloat
    private let overlayCache = OverlayCache()

    private class OverlayCache {
        var faceMask: CIImage?
        var key: String?
    }

    init(intensity: Double = 0.5, pulses: Double = 0.5) {
        self.maxOpacity = max(0.15, 0.85 * CGFloat(intensity))
        self.pulseSpeedMultiplier = 0.15 + CGFloat(pulses) * 0.6
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        let opacity = maxOpacity * min(1.0, progress * 2.5)
        guard opacity > 0.01 else { return image }

        let faceRadius = max(face.faceWidth, face.faceHeight) * 0.7

        let cacheKey = "\(Int(extent.width)),\(Int(extent.height)),\(Int(face.faceCenter.x)),\(Int(face.faceCenter.y)),\(Int(faceRadius))"

        let faceMask: CIImage
        if overlayCache.key == cacheKey, let cached = overlayCache.faceMask {
            faceMask = cached
        } else {
            guard let rendered = renderFaceMask(
                imageWidth: Int(extent.width),
                imageHeight: Int(extent.height),
                center: face.faceCenter,
                faceRadiusX: face.faceWidth * 0.6,
                faceRadiusY: face.faceHeight * 0.7,
                featherRadius: faceRadius * 0.2,
                originX: extent.origin.x,
                originY: extent.origin.y
            ) else { return image }
            overlayCache.faceMask = rendered
            overlayCache.key = cacheKey
            faceMask = rendered
        }

        let drawCenter = CGPoint(
            x: face.faceCenter.x - extent.origin.x,
            y: CGFloat(Int(extent.height)) - (face.faceCenter.y - extent.origin.y)
        )

        guard let gradientCG = renderRadialRainbow(
            width: Int(extent.width),
            height: Int(extent.height),
            center: drawCenter,
            frameIndex: frameIndex
        ) else { return image }

        var gradient = CIImage(cgImage: gradientCG)
            .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))

        gradient = gradient.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])

        let maskedGradient = gradient.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: faceMask
        ]).cropped(to: extent)

        return maskedGradient.composited(over: image).cropped(to: extent)
    }

    // MARK: - Rendering

    private func renderRadialRainbow(width: Int, height: Int, center: CGPoint, frameIndex: Int) -> CGImage? {
        let size = CGSize(width: width, height: height)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }

        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let baseColors: [CGColor] = [
            UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1).cgColor,
            UIColor(red: 1.0, green: 0.6, blue: 0.1, alpha: 1).cgColor,
            UIColor(red: 1.0, green: 0.95, blue: 0.2, alpha: 1).cgColor,
            UIColor(red: 0.2, green: 0.9, blue: 0.3, alpha: 1).cgColor,
            UIColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1).cgColor,
            UIColor(red: 0.4, green: 0.3, blue: 1.0, alpha: 1).cgColor,
            UIColor(red: 0.8, green: 0.2, blue: 0.9, alpha: 1).cgColor,
            UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1).cgColor
        ]
        let baseLocs: [CGFloat] = [0.0, 0.14, 0.28, 0.42, 0.57, 0.71, 0.85, 1.0]

        let reps = 4
        var allColors: [CGColor] = []
        var allLocs: [CGFloat] = []
        for rep in 0..<reps {
            for (i, color) in baseColors.enumerated() {
                allColors.append(color)
                allLocs.append((CGFloat(rep) + baseLocs[i]) / CGFloat(reps))
            }
        }

        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: allColors as CFArray,
            locations: allLocs
        ) else {
            UIGraphicsEndImageContext()
            return nil
        }

        let maxRadius = sqrt(pow(CGFloat(width), 2) + pow(CGFloat(height), 2)) / 2
        let cycleRadius = maxRadius / CGFloat(reps)
        let pulseSpeed: CGFloat = (maxRadius / 8.0) * pulseSpeedMultiplier
        let phase = (CGFloat(frameIndex) * pulseSpeed).truncatingRemainder(dividingBy: cycleRadius)
        let totalGradientRadius = maxRadius * CGFloat(reps)

        ctx.drawRadialGradient(
            gradient,
            startCenter: center, startRadius: phase,
            endCenter: center, endRadius: phase + totalGradientRadius,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )

        let uiImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return uiImage?.cgImage
    }

    /// Feathered elliptical mask — black at face (hide rainbow), white outside (show rainbow).
    private func renderFaceMask(
        imageWidth: Int, imageHeight: Int,
        center: CGPoint,
        faceRadiusX: CGFloat, faceRadiusY: CGFloat,
        featherRadius: CGFloat,
        originX: CGFloat, originY: CGFloat
    ) -> CIImage? {
        let size = CGSize(width: imageWidth, height: imageHeight)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }

        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        let drawCenter = CGPoint(
            x: center.x - originX,
            y: CGFloat(imageHeight) - (center.y - originY)
        )

        let ellipseRect = CGRect(
            x: drawCenter.x - faceRadiusX,
            y: drawCenter.y - faceRadiusY,
            width: faceRadiusX * 2,
            height: faceRadiusY * 2
        )
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fillEllipse(in: ellipseRect)

        let uiImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = uiImage?.cgImage else { return nil }
        let ciMask = CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(translationX: originX, y: originY))

        return ciMask.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: featherRadius
        ]).cropped(to: CGRect(x: originX, y: originY, width: CGFloat(imageWidth), height: CGFloat(imageHeight)))
    }
}
