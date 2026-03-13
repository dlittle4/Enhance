import CoreImage
import UIKit

/// Overlays the SVG heart shape on the detected eye positions,
/// scaling up with progress. Intensity controls heart size.
/// Uses the same Heart_XS.svg path as the heart vignette.
struct HeartEyesEffect: FaceEffect {
    private let sizeScale: CGFloat

    init(intensity: Double = 0.5) {
        self.sizeScale = 0.5 + 1.5 * CGFloat(max(0, min(1, intensity)))
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        guard progress > 0.15 else { return image }

        let ramp = min(1.0, (progress - 0.15) / 0.5)
        let scale = ramp * ramp
        guard scale > 0.01 else { return image }

        let extent = image.extent
        var result = image

        let eyeSize = max(face.leftEyeWidth, face.rightEyeWidth, face.faceWidth * 0.12) * sizeScale * 1.8

        if let leftPupil = face.leftPupilCenter {
            if let heart = renderHeartOverlay(
                center: leftPupil, size: eyeSize * scale,
                bounce: bounceScale(frameIndex: frameIndex, seed: 0),
                rotation: -.pi / 12
            ) {
                result = heart.composited(over: result).cropped(to: extent)
            }
        }

        if let rightPupil = face.rightPupilCenter {
            if let heart = renderHeartOverlay(
                center: rightPupil, size: eyeSize * scale,
                bounce: bounceScale(frameIndex: frameIndex, seed: 5),
                rotation: .pi / 12
            ) {
                result = heart.composited(over: result).cropped(to: extent)
            }
        }

        return result
    }

    private func renderHeartOverlay(center: CGPoint, size: CGFloat, bounce: CGFloat, rotation: CGFloat) -> CIImage? {
        let effectiveSize = size * bounce
        let canvasDim = effectiveSize * 1.6
        guard canvasDim > 1 else { return nil }

        let dim = Int(ceil(canvasDim))
        let uiSize = CGSize(width: dim, height: dim)
        UIGraphicsBeginImageContextWithOptions(uiSize, false, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }

        let heartCenter = CGPoint(x: CGFloat(dim) / 2, y: CGFloat(dim) / 2)

        ctx.translateBy(x: heartCenter.x, y: heartCenter.y)
        ctx.rotate(by: rotation)
        ctx.translateBy(x: -heartCenter.x, y: -heartCenter.y)

        let path = SVGHeartPath.path(center: heartCenter, size: effectiveSize)

        ctx.addPath(path.cgPath)
        ctx.setFillColor(UIColor(red: 0.95, green: 0.15, blue: 0.35, alpha: 1.0).cgColor)
        ctx.fillPath()

        let highlightPath = SVGHeartPath.path(
            center: CGPoint(x: heartCenter.x - effectiveSize * 0.08, y: heartCenter.y - effectiveSize * 0.06),
            size: effectiveSize * 0.25
        )
        ctx.addPath(highlightPath.cgPath)
        ctx.setFillColor(UIColor(red: 1.0, green: 0.45, blue: 0.55, alpha: 0.6).cgColor)
        ctx.fillPath()

        let uiImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = uiImage?.cgImage else { return nil }
        return CIImage(cgImage: cgImage).transformed(by: CGAffineTransform(
            translationX: center.x - CGFloat(dim) / 2,
            y: center.y - CGFloat(dim) / 2
        ))
    }

    private func bounceScale(frameIndex: Int, seed: Int) -> CGFloat {
        let phase = Double(frameIndex * 3 + seed) * 0.25
        return 1.0 + 0.06 * CGFloat(sin(phase))
    }
}
