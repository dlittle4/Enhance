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

    /// Everything the face-effect pass needs, resolved once before the frame loop.
    ///
    /// Exists because the face effect is the only part of the generator that re-renders a
    /// *whole image* per frame, and it was doing so at full source resolution — see
    /// `prepareFaceEffectPass`.
    private struct FaceEffectPass {
        let effect: FaceEffect
        /// Downscaled to the largest size the zoom can actually reveal.
        let source: CGImage
        /// Faces converted into `source`'s coordinate space.
        let faces: [DetectedFace]
    }

    /// The prepared text overlay, resolved once before the frame loop.
    ///
    /// Pairs the master raster with the overlay it was built from: the compositor needs the
    /// overlay for placement (`center`, `angle`, `color`) and the animation type, while the
    /// raster carries the cut tiles. Non-nil only when there is active text to draw, so the
    /// frame loops branch on its presence and the no-text path stays byte-identical.
    private struct TextPass {
        let raster: RasterizedText
        let overlay: TextOverlay
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
    
    func generateGIF(from image: UIImage, currentScale: CGFloat, visibleRect: CGRect, animator: Animator, speed: Double = 1.0, pauseDuration: Double = 1.0, visualEffects: [VisualEffect] = [], faceEffect: FaceEffect? = nil, detectedFaces: [DetectedFace] = [], textOverlay: TextOverlay? = nil) -> Data? {
        guard let context = prepareDrawingContext(from: image, currentScale: currentScale, visibleRect: visibleRect, speed: speed, pauseDuration: pauseDuration) else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = setupGIFDestination(data: data, totalFrames: context.frameCount + context.pauseFrameCount) else {
            return nil
        }

        let facePass = prepareFaceEffectPass(context: context, effect: faceEffect, faces: detectedFaces)

        // Stage 4 of the pipeline: text is composited after the face → zoom → visual-effect passes,
        // in the output frame's own coordinates, so it stays crisp and frame-anchored rather than
        // riding the zoom. Prepared exactly once — one Core Text layout and one master raster for
        // the whole GIF, cut into tiles the frame loop only blits. `prepare` returns nil for a nil
        // or whitespace-only overlay, and `nil` means the frame loops run untouched, so the
        // no-text path is byte-identical to before this existed. See FEATURE-TEXT-EFFECTS.md §7.7.
        let textPass = textOverlay.flatMap { overlay in
            TextRasterizer.prepare(overlay: overlay, pixelSide: context.outputSize.width)
                .map { TextPass(raster: $0, overlay: overlay) }
        }

        addAnimatedFrames(to: destination, context: context, animator: animator, visualEffects: visualEffects, facePass: facePass, textPass: textPass)
        addPauseFrames(to: destination, context: context, animator: animator, visualEffects: visualEffects, facePass: facePass, textPass: textPass)

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

    private func addAnimatedFrames(to destination: CGImageDestination, context: DrawingContext, animator: Animator, visualEffects: [VisualEffect], facePass: FaceEffectPass?, textPass: TextPass?) {
        for i in 0..<context.frameCount {
            autoreleasepool {
                let frameProgress = CGFloat(i) / CGFloat(context.frameCount - 1)
                let frameParams = animator.animationParameters(for: frameProgress, in: context)

                let transform = calculateTransformForFrame(
                    params: frameParams, drawRect: context.drawRect,
                    outputSize: context.outputSize
                )

                let sourceForFrame = faceEffectedSource(pass: facePass, progress: frameProgress, frameIndex: i)
                if let frameImage = createFrameImage(transform: transform, context: context, sourceOverride: sourceForFrame) {
                    let geometry = frameGeometry(params: frameParams, transform: transform, context: context)
                    let effected = applyVisualEffects(frameImage, effects: visualEffects, progress: frameProgress, frameIndex: i, geometry: geometry)
                    // The text entrance consumes the same `frameProgress` the zoom does, so the two
                    // are choreographed by construction. `frameProgress` runs 0…1 across the moving
                    // frames, which is exactly the normalized progress the presets expect.
                    let outputImage = composited(effected, textPass: textPass, progress: frameProgress)
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

    private func addPauseFrames(to destination: CGImageDestination, context: DrawingContext, animator: Animator, visualEffects: [VisualEffect], facePass: FaceEffectPass?, textPass: TextPass?) {
        let finalParams = animator.animationParameters(for: 1.0, in: context)
        let finalTransform = calculateTransformForFrame(
            params: finalParams, drawRect: context.drawRect, outputSize: context.outputSize
        )

        let sourceForFrame = faceEffectedSource(pass: facePass, progress: 1.0, frameIndex: context.frameCount)
        if let finalFrameImage = createFrameImage(transform: finalTransform, context: context, sourceOverride: sourceForFrame) {
            let geometry = frameGeometry(params: finalParams, transform: finalTransform, context: context)
            let effected = applyVisualEffects(finalFrameImage, effects: visualEffects, progress: 1.0, frameIndex: context.frameCount, geometry: geometry)
            // Composited once at progress 1: the text is at its settled state and identical across
            // every replicated pause frame, so the message holds still and adds no entropy.
            let outputImage = composited(effected, textPass: textPass, progress: 1.0)
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

    /// Largest scale the face-effect source is worth keeping.
    ///
    /// `fillScale × maxZoom` is the greatest magnification any source pixel undergoes. Below 1
    /// the generator is downsampling, so pre-shrinking by that factor discards only detail the
    /// output could never show. Clamped to 1 so a small source is never upscaled — that would
    /// cost more and add nothing.
    static func faceEffectSourceScale(fillScale: CGFloat, maxZoom: CGFloat) -> CGFloat {
        guard fillScale > 0, maxZoom > 0 else { return 1 }
        return min(1.0, fillScale * maxZoom)
    }

    /// Resolves the source and face coordinates for the face-effect pass, once.
    ///
    /// **This is the hot path in the whole generator.** The face effect has to be baked into
    /// the image *before* the zoom transform so it stays fixed on the face, which means one
    /// whole-image render per frame — and it used to render the full camera-resolution source
    /// every time, for a 600×600 output. A 12MP photo is ~28× more pixels than the zoom can
    /// ever reveal, paid once per frame, and continuous speed pushed the frame count as high
    /// as 100.
    ///
    /// So the source is pre-scaled to the largest size the animation can actually magnify it
    /// to. A source pixel's greatest magnification is `fillScale × maxZoom`: below 1 the
    /// generator is downsampling anyway, so shrinking the source by that factor first is free
    /// of visible cost. Above 1 it is already upsampling and the source is left alone.
    private func prepareFaceEffectPass(context: DrawingContext, effect: FaceEffect?, faces: [DetectedFace]) -> FaceEffectPass? {
        guard let effect, !faces.isEmpty, let cgImage = context.normalizedImage.cgImage else { return nil }

        let sourceWidth = context.normalizedImage.size.width
        guard sourceWidth > 0 else { return nil }
        // drawRect is the source laid into the output at zoom 1, so this is fillScale.
        let fillScale = context.drawRect.width / sourceWidth
        let scale = Self.faceEffectSourceScale(fillScale: fillScale, maxZoom: context.userZoomParams.scale)

        guard scale < 0.999,
              CGFloat(cgImage.width) * scale >= 1, CGFloat(cgImage.height) * scale >= 1 else {
            return FaceEffectPass(effect: effect, source: cgImage, faces: faces)
        }

        let shrunk = CIImage(cgImage: cgImage)
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale])
        guard let scaledCG = ciContext.createCGImage(shrunk, from: shrunk.extent) else {
            return FaceEffectPass(effect: effect, source: cgImage, faces: faces)
        }

        // Landmarks are in full-source pixels; every consumer of a downscaled copy has to
        // convert them, which is what `DetectedFace.scaled` exists for.
        return FaceEffectPass(
            effect: effect,
            source: scaledCG,
            faces: faces.map { $0.scaled(x: scale, y: scale) }
        )
    }

    /// Applies the face effect for one frame. Drawn into the same `drawRect` regardless of
    /// the source's pixel size, so nothing downstream needs to know it was scaled.
    private func faceEffectedSource(pass: FaceEffectPass?, progress: CGFloat, frameIndex: Int) -> UIImage? {
        guard let pass else { return nil }
        var result = CIImage(cgImage: pass.source)
        for face in pass.faces {
            result = pass.effect.apply(to: result, face: face, progress: progress, frameIndex: frameIndex)
        }
        guard let outputCG = ciContext.createCGImage(result, from: result.extent) else { return nil }
        return UIImage(cgImage: outputCG)
    }

    /// - Parameter geometry: how this frame relates to the source image. Effects are
    ///   applied *after* the zoom transform, so anything with its own spatial grid needs
    ///   both the scale and the content offset to stay locked to the subject rather than
    ///   to the output frame.
    private func applyVisualEffects(_ cgImage: CGImage, effects: [VisualEffect], progress: CGFloat, frameIndex: Int, geometry: FrameGeometry) -> CGImage {
        guard !effects.isEmpty else { return cgImage }
        var ciImage = CIImage(cgImage: cgImage)
        for effect in effects {
            ciImage = effect.apply(
                to: ciImage, progress: progress, frameIndex: frameIndex,
                viewportCenter: nil, geometry: geometry
            )
        }
        return ciContext.createCGImage(ciImage, from: ciImage.extent) ?? cgImage
    }

    /// Draws the prepared text over one finished frame, or returns the frame untouched when
    /// there is no text pass. The compositor takes a `CGImage` and returns one, so this is a
    /// pure stage-4 insertion that touches neither the `VisualEffect` protocol nor the zoom
    /// transform. Tuning is left at its default here; Stage F threads the panel's control.
    private func composited(_ frame: CGImage, textPass: TextPass?, progress: CGFloat) -> CGImage {
        guard let textPass else { return frame }
        return TextTileCompositor.composite(
            textPass.raster, overlay: textPass.overlay, progress: progress, over: frame
        )
    }

    /// Where the image content sits in the rendered frame, for effects with a spatial
    /// grid. The frame is drawn through UIGraphics (top-left origin) and then read back
    /// as a CIImage (bottom-left origin), so the y axis is flipped to match — see
    /// LEARNINGS 2026-03-10 for the bug this caused when it was missed before.
    private func frameGeometry(params: AnimationParameters, transform: CGAffineTransform, context: DrawingContext) -> FrameGeometry {
        let originInFrame = context.drawRect.origin.applying(transform)
        // The aspect-fill factor applied before any zoom — see `FrameGeometry.contentScale`.
        // Taken from the drawn width rather than recomputed so it cannot drift from
        // `calculateDrawRect`.
        let sourceWidth = context.normalizedImage.size.width * context.normalizedImage.scale
        let contentScale = sourceWidth > 0 ? context.drawRect.width / sourceWidth : 1
        return FrameGeometry(
            scale: params.scale,
            contentOrigin: CGPoint(
                x: originInFrame.x,
                y: context.outputSize.height - originInFrame.y
            ),
            contentScale: contentScale
        )
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
