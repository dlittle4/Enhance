import CoreImage
import UIKit

/// Creates a heart-shaped vignette centered on the detected face. The area
/// outside the heart is tinted hot pink/magenta, drawing attention to the
/// subject through the heart-shaped cutout. Intensity controls tint opacity,
/// size controls the heart dimensions.
struct HeartVignetteEffect: FaceEffect {
    private let intensityScale: CGFloat
    private let sizeScale: CGFloat
    private let overlayCache = OverlayCache()

    private class OverlayCache {
        var mask: CIImage?
        var key: String?
    }

    init(intensity: Double = 0.5, size: Double = 0.5) {
        self.intensityScale = max(0.2, CGFloat(intensity))
        self.sizeScale = 1.2 + 2.8 * CGFloat(max(0, min(1, size)))
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        let fade = min(1.0, progress * 1.5)
        guard fade > 0.01 else { return image }

        let heartSize = max(face.faceWidth, face.faceHeight) * sizeScale
        let center = face.faceCenter

        let cacheKey = "\(Int(extent.width)),\(Int(extent.height)),\(Int(center.x)),\(Int(center.y)),\(Int(heartSize))"
        let heartMask: CIImage
        if overlayCache.key == cacheKey, let cached = overlayCache.mask {
            heartMask = cached
        } else {
            guard let rendered = renderHeartMask(
                imageWidth: Int(extent.width),
                imageHeight: Int(extent.height),
                center: center,
                heartSize: heartSize,
                originX: extent.origin.x,
                originY: extent.origin.y
            ) else { return image }
            overlayCache.mask = rendered
            overlayCache.key = cacheKey
            heartMask = rendered
        }

        let tintOpacity = fade * intensityScale * 0.82
        let pinkOverlay = CIImage(color: CIColor(red: 0.92, green: 0.1, blue: 0.55, alpha: tintOpacity))
            .cropped(to: extent)

        let masked = pinkOverlay.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: CIColor.clear).cropped(to: extent),
            kCIInputMaskImageKey: heartMask
        ])

        return masked.composited(over: image).cropped(to: extent)
    }

    private func renderHeartMask(
        imageWidth: Int, imageHeight: Int,
        center: CGPoint, heartSize: CGFloat,
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

        let heartCenter = CGPoint(
            x: center.x - originX,
            y: CGFloat(imageHeight) - (center.y - originY)
        )

        let path = SVGHeartPath.path(center: heartCenter, size: heartSize)
        ctx.addPath(path.cgPath)
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fillPath()

        let uiImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = uiImage?.cgImage else { return nil }

        return CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(translationX: originX, y: originY))
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: heartSize * 0.015])
            .cropped(to: CGRect(x: originX, y: originY, width: CGFloat(imageWidth), height: CGFloat(imageHeight)))
    }
}

/// Shared heart shape derived from the Heart_XS.svg path data.
enum SVGHeartPath {
    static func path(center: CGPoint, size: CGFloat) -> UIBezierPath {
        let scale = size / 44.0
        let offsetX = center.x - 22.0 * scale
        let offsetY = center.y - 22.0 * scale

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scale + offsetX, y: y * scale + offsetY)
        }

        let path = UIBezierPath()
        path.move(to: pt(41.233, 16.6845))
        path.addCurve(to: pt(30.4753, 5.0874), controlPoint1: pt(41.233, 10.2417), controlPoint2: pt(36.3431, 5.0874))
        path.addCurve(to: pt(21.9995, 9.5974), controlPoint1: pt(26.8894, 5.0874), controlPoint2: pt(23.9555, 6.69812))
        path.addCurve(to: pt(13.5238, 5.0874), controlPoint1: pt(20.0436, 7.02026), controlPoint2: pt(16.7837, 5.0874))
        path.addCurve(to: pt(2.7661, 16.6845), controlPoint1: pt(7.65596, 5.0874), controlPoint2: pt(2.7661, 10.2417))
        path.addCurve(to: pt(22.3255, 38.9124), controlPoint1: pt(2.7661, 16.6845), controlPoint2: pt(1.46214, 28.2817))
        path.addCurve(to: pt(41.233, 16.6845), controlPoint1: pt(42.5369, 27.9595), controlPoint2: pt(41.233, 16.6845))
        path.close()
        return path
    }
}
