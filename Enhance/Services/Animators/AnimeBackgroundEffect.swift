import CoreImage
import UIKit

/// Manga/comic impact-burst effect: white background with dark triangular
/// spikes radiating inward toward the face, with the subject visible through
/// a cutout. Spikes rotate per frame for animation.
/// Intensity controls spike density and opacity.
///
/// **This is ROADMAP §2f's "animated background, stationary subject"** — the inverse of
/// FACE CUTOUT, with the subject held while the background animates.
///
/// The cutout takes `subjectMask` when segmentation found one and falls back to a feathered
/// ellipse around the face otherwise. The ellipse is what this effect shipped with, and the
/// difference is the whole point of the upgrade: a burst punched through an oval reads as a
/// vignette, while one punched through a real silhouette reads as the subject standing in
/// front of it. The fallback is kept rather than the effect being disabled, because §1g found
/// 1 in 8 photos has no subject and the editor's rule is to leave the card live.
///
/// Face effects run on the *un-zoomed source* (`GIFGenerator.faceEffectedSource`), so the mask
/// arrives already in the right space and needs no `FrameGeometry` mapping — unlike the visual
/// effect path, where getting that wrong shipped a broken export once already.
struct AnimeBackgroundEffect: FaceEffect {
    private let intensityScale: CGFloat
    private let spikeCount: Int
    private let subjectMask: CIImage?
    private let overlayCache = OverlayCache()

    private class OverlayCache {
        var spikesOnWhite: CIImage?
        var faceMask: CIImage?
        var key: String?
    }

    init(intensity: Double = 0.5, lineDensity: Double = 0.5, subjectMask: CIImage? = nil) {
        self.intensityScale = max(0.15, CGFloat(intensity))
        self.spikeCount = 12 + Int(lineDensity * 36)
        self.subjectMask = subjectMask
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        let fade = min(1.0, progress * 1.8)
        guard fade > 0.01 else { return image }

        let faceRadius = max(face.faceWidth, face.faceHeight) * 0.7

        let cacheKey = "\(Int(extent.width)),\(Int(extent.height)),\(Int(face.faceCenter.x)),\(Int(face.faceCenter.y)),\(Int(faceRadius))"

        let spikesOnWhite: CIImage
        let faceMask: CIImage

        if overlayCache.key == cacheKey,
           let cachedSpikes = overlayCache.spikesOnWhite,
           let cachedMask = overlayCache.faceMask {
            spikesOnWhite = cachedSpikes
            faceMask = cachedMask
        } else {
            guard let renderedSpikes = renderSpikeBurst(
                imageWidth: Int(extent.width),
                imageHeight: Int(extent.height),
                center: face.faceCenter,
                faceRadius: faceRadius,
                originX: extent.origin.x,
                originY: extent.origin.y
            ) else { return image }

            // The real silhouette when there is one; the original ellipse when there is not.
            let renderedMask: CIImage
            if let subjectMask {
                renderedMask = scaled(subjectMask, to: extent)
            } else if let ellipse = renderFaceMask(
                imageWidth: Int(extent.width),
                imageHeight: Int(extent.height),
                center: face.faceCenter,
                faceRadiusX: face.faceWidth * 0.65,
                faceRadiusY: face.faceHeight * 0.75,
                featherRadius: faceRadius * 0.15,
                originX: extent.origin.x,
                originY: extent.origin.y
            ) {
                renderedMask = ellipse
            } else {
                return image
            }

            overlayCache.spikesOnWhite = renderedSpikes
            overlayCache.faceMask = renderedMask
            overlayCache.key = cacheKey
            spikesOnWhite = renderedSpikes
            faceMask = renderedMask
        }

        let rotationAngle = CGFloat(frameIndex) * 0.03
        let rotatedSpikes = rotateAround(
            spikesOnWhite,
            center: face.faceCenter,
            angle: rotationAngle,
            extent: extent
        )

        let mixedBackground = image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: rotatedSpikes,
            "inputTime": NSNumber(value: Double(fade))
        ])

        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: mixedBackground,
            kCIInputMaskImageKey: faceMask
        ]).cropped(to: extent)
    }

    /// Fit a source-space mask to the frame it is being composited against.
    ///
    /// Face effects already run in source space, so this is normally a no-op; it exists because
    /// the pipeline can normalise a photo's orientation before drawing, which changes its pixel
    /// dimensions without changing what the mask means.
    private func scaled(_ mask: CIImage, to extent: CGRect) -> CIImage {
        guard mask.extent.width > 0, mask.extent.height > 0,
              mask.extent.size != extent.size else { return mask }
        return mask
            .transformed(by: CGAffineTransform(
                scaleX: extent.width / mask.extent.width,
                y: extent.height / mask.extent.height
            ))
            .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
    }

    // MARK: - Rendering

    /// White background with dark triangular spikes radiating inward.
    /// Spikes are thick at the outer edge and come to sharp points near the face.
    private func renderSpikeBurst(
        imageWidth: Int, imageHeight: Int,
        center: CGPoint, faceRadius: CGFloat,
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

        let diagonal = sqrt(CGFloat(imageWidth * imageWidth + imageHeight * imageHeight))
        let outerRadius = diagonal * 1.5

        let innerRadiusX = faceRadius * 1.2
        let innerRadiusY = faceRadius * 1.4

        let darkGray = UIColor(white: 0.22, alpha: 1.0)

        for i in 0..<spikeCount {
            let baseAngle = CGFloat(i) / CGFloat(spikeCount) * .pi * 2

            let jitter = pseudoRandom(seed: i * 37 + 13)
            let lengthJitter = pseudoRandom(seed: i * 53 + 7)
            let widthJitter = pseudoRandom(seed: i * 71 + 23)

            let halfAngleSpread = 0.035 + widthJitter * 0.04

            let tipReach = 0.4 + lengthJitter * 0.5
            let innerR = sqrt(
                pow(innerRadiusX * cos(baseAngle), 2) +
                pow(innerRadiusY * sin(baseAngle), 2)
            ) * tipReach + jitter * faceRadius * 0.15

            let leftAngle = baseAngle - halfAngleSpread
            let rightAngle = baseAngle + halfAngleSpread

            let tip = CGPoint(
                x: drawCenter.x + cos(baseAngle) * innerR,
                y: drawCenter.y + sin(baseAngle) * innerR
            )
            let outerLeft = CGPoint(
                x: drawCenter.x + cos(leftAngle) * outerRadius,
                y: drawCenter.y + sin(leftAngle) * outerRadius
            )
            let outerRight = CGPoint(
                x: drawCenter.x + cos(rightAngle) * outerRadius,
                y: drawCenter.y + sin(rightAngle) * outerRadius
            )

            let spike = UIBezierPath()
            spike.move(to: tip)
            spike.addLine(to: outerLeft)
            spike.addLine(to: outerRight)
            spike.close()

            ctx.setFillColor(darkGray.cgColor)
            ctx.addPath(spike.cgPath)
            ctx.fillPath()

            ctx.setStrokeColor(UIColor(white: 0.15, alpha: 1.0).cgColor)
            ctx.setLineWidth(1.5)
            ctx.addPath(spike.cgPath)
            ctx.strokePath()
        }

        let uiImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = uiImage?.cgImage else { return nil }
        return CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(translationX: originX, y: originY))
    }

    /// Feathered elliptical mask — white at face center (show original), black at edges (show spikes).
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

        ctx.setFillColor(UIColor.black.cgColor)
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
        ctx.setFillColor(UIColor.white.cgColor)
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

    private func rotateAround(
        _ image: CIImage,
        center: CGPoint,
        angle: CGFloat,
        extent: CGRect
    ) -> CIImage {
        let toOrigin = CGAffineTransform(translationX: -center.x, y: -center.y)
        let rotate = CGAffineTransform(rotationAngle: angle)
        let back = CGAffineTransform(translationX: center.x, y: center.y)
        let combined = toOrigin.concatenating(rotate).concatenating(back)
        return image.transformed(by: combined).cropped(to: extent)
    }

    private func pseudoRandom(seed: Int) -> CGFloat {
        var x = UInt64(abs(seed) + 1)
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        return CGFloat(x % 1000) / 1000.0
    }
}
