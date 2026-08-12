import CoreImage
import UIKit

/// Radial rainbow rings that pulse outward from the center of the image.
/// Intensity controls overlay opacity.
///
/// - `speed` is how fast the rings travel outward. The *face* variant of this effect has
///   always had a speed control; the image variant did not, which was a plain parity gap.
public struct RainbowGradientEffect: VisualEffect {
    private let maxOpacity: CGFloat
    private let speedScale: CGFloat

    public init(intensity: Double = 0.5, speed: Double = 0.5) {
        self.maxOpacity = max(0.1, 0.5 * CGFloat(intensity))
        // 0.5 leaves the rate exactly as it shipped.
        self.speedScale = 0.25 + 1.5 * CGFloat(max(0, min(1, speed)))
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil)
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        let opacity = maxOpacity * min(1.0, progress * 2.5)
        guard opacity > 0.01 else { return image }

        let center = viewportCenter ?? CGPoint(x: extent.midX, y: extent.midY)

        guard let gradientCG = renderRadialRainbow(
            width: Int(extent.width),
            height: Int(extent.height),
            center: CGPoint(x: center.x - extent.origin.x, y: extent.height - (center.y - extent.origin.y)),
            frameIndex: frameIndex,
            speedScale: speedScale
        ) else { return image }

        var gradient = CIImage(cgImage: gradientCG)
            .transformed(by: CGAffineTransform(
                translationX: extent.origin.x,
                y: extent.origin.y
            ))

        gradient = gradient.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])

        return gradient.composited(over: image).cropped(to: extent)
    }

    private func renderRadialRainbow(width: Int, height: Int, center: CGPoint, frameIndex: Int, speedScale: CGFloat) -> CGImage? {
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

        let reps = 3
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
        let pulseSpeed: CGFloat = cycleRadius / 20.0 * speedScale
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
}
