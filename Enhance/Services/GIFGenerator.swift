import UIKit
import ImageIO
import CoreImage
import UniformTypeIdentifiers

public class GIFGenerator: GIFGenerating {
    
    private let outputDimension: CGFloat = 600.0
    private let targetFrameDelay: Double = 0.04
    private let animationDuration: Double = 1.0
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    public struct AnimationParameters {
        public let scale: CGFloat
        public let centerX: CGFloat
        public let centerY: CGFloat
    }

    public struct DrawingContext {
        let normalizedImage: UIImage
        let outputSize: CGSize
        let drawRect: CGRect
        let fullViewParams: AnimationParameters
        let userZoomParams: AnimationParameters
        let frameCount: Int
        let frameDelay: Double
        let pauseFrameCount: Int
        let pauseFrameDelay: Double
    }
    
    func generateGIF(from image: UIImage, currentScale: CGFloat, visibleRect: CGRect, animator: Animator, speed: Double = 1.0, pauseDuration: Double = 1.0, visualEffects: [VisualEffect] = [], faceEffect: FaceEffect? = nil, detectedFaces: [DetectedFace] = []) -> Data? {
        guard let context = prepareDrawingContext(from: image, currentScale: currentScale, visibleRect: visibleRect, speed: speed, pauseDuration: pauseDuration) else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = setupGIFDestination(data: data, totalFrames: context.frameCount + context.pauseFrameCount) else {
            return nil
        }

        addAnimatedFrames(to: destination, context: context, animator: animator, visualEffects: visualEffects, faceEffect: faceEffect, detectedFaces: detectedFaces)
        addPauseFrames(to: destination, context: context, animator: animator, visualEffects: visualEffects, faceEffect: faceEffect, detectedFaces: detectedFaces)

        if CGImageDestinationFinalize(destination) {
            return data as Data
        } else {
            return nil
        }
    }
    
    public func saveTempGIF(_ gifData: Data) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "share_\(UUID().uuidString).gif"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try gifData.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - Private Helpers

    private func prepareDrawingContext(from image: UIImage, currentScale: CGFloat, visibleRect: CGRect, speed: Double = 1.0, pauseDuration: Double = 1.0) -> DrawingContext? {
        let effectiveScale = max(1.0, currentScale)
        let normalizedImage = fixImageOrientation(image)
        let outputSize = CGSize(width: outputDimension, height: outputDimension)
        let drawRect = calculateDrawRect(imageSize: normalizedImage.size, outputSize: outputSize)
        let (fullViewParams, userZoomParams) = calculateAnimationParameters(
            drawRect: drawRect, visibleRect: visibleRect, currentScale: effectiveScale
        )

        let clampedSpeed = max(0.25, min(4.0, speed))
        let duration = animationDuration / clampedSpeed
        let computedFrameCount = max(12, Int(duration / targetFrameDelay))
        let computedDelay = duration / Double(computedFrameCount)

        let clampedPause = max(0.0, min(5.0, pauseDuration))
        let computedPauseFrames = max(1, Int(clampedPause / targetFrameDelay))
        
        return DrawingContext(
            normalizedImage: normalizedImage, outputSize: outputSize, drawRect: drawRect,
            fullViewParams: fullViewParams, userZoomParams: userZoomParams,
            frameCount: computedFrameCount, frameDelay: computedDelay,
            pauseFrameCount: computedPauseFrames, pauseFrameDelay: targetFrameDelay
        )
    }

    private func setupGIFDestination(data: CFMutableData, totalFrames: Int) -> CGImageDestination? {
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.gif.identifier as CFString, totalFrames, nil
        ) else {
            return nil
        }

        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0,
                kCGImagePropertyGIFHasGlobalColorMap as String: true,
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)
        return destination
    }

    private func addAnimatedFrames(to destination: CGImageDestination, context: DrawingContext, animator: Animator, visualEffects: [VisualEffect], faceEffect: FaceEffect? = nil, detectedFaces: [DetectedFace] = []) {
        for i in 0..<context.frameCount {
            autoreleasepool {
                let frameProgress = CGFloat(i) / CGFloat(context.frameCount - 1)
                let frameParams = animator.animationParameters(for: frameProgress, in: context)

                let transform = calculateTransformForFrame(
                    params: frameParams, drawRect: context.drawRect,
                    outputSize: context.outputSize
                )

                let sourceForFrame = faceEffectedSource(context: context, effect: faceEffect, faces: detectedFaces, progress: frameProgress, frameIndex: i)
                if let frameImage = createFrameImage(transform: transform, context: context, sourceOverride: sourceForFrame) {
                    let outputImage = applyVisualEffects(frameImage, effects: visualEffects, progress: frameProgress, frameIndex: i, frameScale: frameParams.scale)
                    let frameProperties: [String: Any] = [
                        kCGImagePropertyGIFDictionary as String: [
                            kCGImagePropertyGIFDelayTime as String: context.frameDelay,
                            kCGImagePropertyGIFHasGlobalColorMap as String: true
                        ]
                    ]
                    CGImageDestinationAddImage(destination, outputImage, frameProperties as CFDictionary)
                }
            }
        }
    }

    private func addPauseFrames(to destination: CGImageDestination, context: DrawingContext, animator: Animator, visualEffects: [VisualEffect], faceEffect: FaceEffect? = nil, detectedFaces: [DetectedFace] = []) {
        let finalParams = animator.animationParameters(for: 1.0, in: context)
        let finalTransform = calculateTransformForFrame(
            params: finalParams, drawRect: context.drawRect, outputSize: context.outputSize
        )

        let sourceForFrame = faceEffectedSource(context: context, effect: faceEffect, faces: detectedFaces, progress: 1.0, frameIndex: context.frameCount)
        if let finalFrameImage = createFrameImage(transform: finalTransform, context: context, sourceOverride: sourceForFrame) {
            let outputImage = applyVisualEffects(finalFrameImage, effects: visualEffects, progress: 1.0, frameIndex: context.frameCount, frameScale: finalParams.scale)
            for _ in 0..<context.pauseFrameCount {
                let frameProperties: [String: Any] = [
                    kCGImagePropertyGIFDictionary as String: [
                        kCGImagePropertyGIFDelayTime as String: context.pauseFrameDelay,
                        kCGImagePropertyGIFHasGlobalColorMap as String: true
                    ]
                ]
                CGImageDestinationAddImage(destination, outputImage, frameProperties as CFDictionary)
            }
        }
    }

    /// Apply face effect to every target face on the full source image so effects
    /// are baked in before the zoom/crop transform, keeping them fixed on each face.
    private func faceEffectedSource(context: DrawingContext, effect: FaceEffect?, faces: [DetectedFace], progress: CGFloat, frameIndex: Int) -> UIImage? {
        guard let effect, !faces.isEmpty, let cgImage = context.normalizedImage.cgImage else { return nil }
        var result = CIImage(cgImage: cgImage)
        for face in faces {
            result = effect.apply(to: result, face: face, progress: progress, frameIndex: frameIndex)
        }
        guard let outputCG = ciContext.createCGImage(result, from: result.extent) else { return nil }
        return UIImage(cgImage: outputCG)
    }

    /// - Parameter frameScale: the zoom baked into this frame. Effects are applied
    ///   *after* the zoom transform, so anything with its own spatial frequency needs
    ///   this to stay locked to image content instead of to the output frame.
    private func applyVisualEffects(_ cgImage: CGImage, effects: [VisualEffect], progress: CGFloat, frameIndex: Int, frameScale: CGFloat) -> CGImage {
        guard !effects.isEmpty else { return cgImage }
        var ciImage = CIImage(cgImage: cgImage)
        for effect in effects {
            ciImage = effect.apply(
                to: ciImage, progress: progress, frameIndex: frameIndex,
                viewportCenter: nil, frameScale: frameScale
            )
        }
        return ciContext.createCGImage(ciImage, from: ciImage.extent) ?? cgImage
    }

    private func createFrameImage(transform: CGAffineTransform, context: DrawingContext, sourceOverride: UIImage? = nil) -> CGImage? {
        UIGraphicsBeginImageContextWithOptions(context.outputSize, false, 1.0)
        guard let gfx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }

        gfx.setFillColor(UIColor.black.cgColor)
        gfx.fill(CGRect(origin: .zero, size: context.outputSize))
        gfx.clip(to: CGRect(origin: .zero, size: context.outputSize))
        gfx.concatenate(transform)
        let imageToDraw = sourceOverride ?? context.normalizedImage
        imageToDraw.draw(in: context.drawRect)

        let frameUIImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return frameUIImage?.cgImage
    }

    // MARK: - Calculations

    private func calculateDrawRect(imageSize: CGSize, outputSize: CGSize) -> CGRect {
        let fillScale = max(outputSize.width / imageSize.width, outputSize.height / imageSize.height)
        let drawWidth = imageSize.width * fillScale
        let drawHeight = imageSize.height * fillScale
        let offsetX = (outputSize.width - drawWidth) / 2
        let offsetY = (outputSize.height - drawHeight) / 2
        return CGRect(x: offsetX, y: offsetY, width: drawWidth, height: drawHeight)
    }

    private func calculateAnimationParameters(drawRect: CGRect, visibleRect: CGRect, currentScale: CGFloat) -> (fullView: AnimationParameters, userZoom: AnimationParameters) {
        let fullViewParams = AnimationParameters(scale: 1.0, centerX: drawRect.midX, centerY: drawRect.midY)

        let maxZoomScale = AppConstants.Zoom.maxScale
        let userZoomScale = min(currentScale, maxZoomScale)
        let zoomedCenterX = drawRect.origin.x + (visibleRect.origin.x + visibleRect.width / 2) * drawRect.width
        let zoomedCenterY = drawRect.origin.y + (visibleRect.origin.y + visibleRect.height / 2) * drawRect.height
        let userZoomParams = AnimationParameters(scale: userZoomScale, centerX: zoomedCenterX, centerY: zoomedCenterY)

        return (fullViewParams, userZoomParams)
    }

    private func calculateTransformForFrame(params: AnimationParameters, drawRect: CGRect, outputSize: CGSize) -> CGAffineTransform {
        let outputCenterX = outputSize.width / 2
        let outputCenterY = outputSize.height / 2

        let t1 = CGAffineTransform(translationX: -params.centerX, y: -params.centerY)
        let s = CGAffineTransform(scaleX: params.scale, y: params.scale)
        let t2 = CGAffineTransform(translationX: outputCenterX, y: outputCenterY)
        let finalTransform = t1.concatenating(s).concatenating(t2)

        return finalTransform
    }

    private func fixImageOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return normalizedImage
    }
}
