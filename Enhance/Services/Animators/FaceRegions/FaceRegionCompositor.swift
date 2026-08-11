import CoreImage

/// A single copied-feature placement: which region to sample, where to put it, and how it
/// is scaled, rotated, and faded. All geometry is in image coordinates (CIImage space).
struct FaceRegionPlacement {
    var region: FaceRegion
    var destinationCenter: CGPoint
    var scale: CGFloat
    var rotation: CGFloat = 0
    var opacity: CGFloat = 1
}

/// Copies a face region from a source image and composites it back at a new location with a
/// soft mask. The strategic payload of Feature Scrambler: a reusable, landmark-aware Core
/// Image compositor with no custom kernel.
///
/// It never creates a `CIContext` or calls `createCGImage`; the returned graph stays lazy
/// until the caller's shared context evaluates it. On any missing region or non-finite
/// extent it returns the background unchanged rather than producing a seam or a crash.
struct FaceRegionCompositor {

    /// Composite one placement.
    ///
    /// - Parameters:
    ///   - source: the image to *sample the feature from* — always the original input, so
    ///     stacked placements never sample an earlier composite.
    ///   - background: the image to composite *onto*. For a single placement this is the
    ///     original; for multiple, the running result.
    ///   - padding: extra source area around the landmark bounds, as a fraction of the
    ///     bounds size, so eyelashes / lip edges survive and the feather has room.
    ///   - feather: mask edge softness in `0...1` (see `FaceRegionMaskBuilder`).
    func composite(
        _ placement: FaceRegionPlacement,
        source: CIImage,
        over background: CIImage,
        face: DetectedFace,
        padding: CGFloat,
        feather: CGFloat
    ) -> CIImage {
        guard let rawBounds = placement.region.sourceBounds(in: face) else { return background }

        let padX = rawBounds.width * padding
        let padY = rawBounds.height * padding
        let padded = rawBounds.insetBy(dx: -padX, dy: -padY)

        guard padded.hasFiniteComponents, padded.width >= 1, padded.height >= 1,
              placement.scale.isFinite, placement.scale > 0,
              placement.destinationCenter.x.isFinite, placement.destinationCenter.y.isFinite,
              let mask = FaceRegionMaskBuilder.ellipticalMask(bounds: padded, feather: feather)
        else { return background }

        // Clamp before cropping so a feature near the image edge extends its border pixels
        // instead of sampling transparency — otherwise the copy shows a black or clear seam.
        let sampled = source.clampedToExtent().cropped(to: padded)

        // Scale and rotate about the region centre, then move to the destination. Source and
        // mask get the identical matrix so their edges stay locked together.
        let center = CGPoint(x: padded.midX, y: padded.midY)
        let transform = CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(scaleX: placement.scale, y: placement.scale)
                .rotated(by: placement.rotation))
            .concatenating(CGAffineTransform(translationX: placement.destinationCenter.x,
                                             y: placement.destinationCenter.y))

        var movedSource = sampled.transformed(by: transform)
        let movedMask = mask.transformed(by: transform)

        guard movedSource.extent.hasFiniteComponents, movedMask.extent.hasFiniteComponents else { return background }

        // Opacity folds into the mask so a partly-transparent placement still feathers.
        let opacity = max(0, min(1, placement.opacity))
        let effectiveMask: CIImage
        if opacity < 0.999 {
            effectiveMask = movedMask.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)
            ])
        } else {
            effectiveMask = movedMask
        }

        movedSource = movedSource.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: effectiveMask
        ])

        return movedSource.cropped(to: background.extent)
    }

    /// Cover a region's *original* feature with a fill (typically sampled skin), feathered
    /// into the surrounding face. Run before compositing a moved feature onto the same spot
    /// so the copy reads as a replacement — the old eye/mouth is gone, not showing through.
    ///
    /// - Parameters:
    ///   - fill: an image to paint over the region — pass an infinite (clamped) solid colour
    ///     for flat skin. Sampled at the region, so a textured fill would follow the feature.
    ///   - opacity: how strongly to cover, so the heal can fade in with the reveal.
    func fillRegion(
        _ region: FaceRegion,
        in face: DetectedFace,
        with fill: CIImage,
        over background: CIImage,
        padding: CGFloat,
        feather: CGFloat,
        opacity: CGFloat
    ) -> CIImage {
        guard let rawBounds = region.sourceBounds(in: face) else { return background }
        let padded = rawBounds.insetBy(dx: -rawBounds.width * padding, dy: -rawBounds.height * padding)
        let op = max(0, min(1, opacity))
        guard op > 0.001, padded.hasFiniteComponents, padded.width >= 1, padded.height >= 1,
              let mask = FaceRegionMaskBuilder.ellipticalMask(bounds: padded, feather: feather)
        else { return background }

        let effectiveMask = op < 0.999
            ? mask.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: op)])
            : mask

        return fill.cropped(to: padded)
            .applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: background,
                kCIInputMaskImageKey: effectiveMask
            ])
            .cropped(to: background.extent)
    }

    /// Screen a soft radial glow of light onto the image, brightest at `center` and fading to
    /// nothing by `radius`. Lazy (a radial gradient + a screen blend), so no `CIContext`.
    /// Screen lightens without blowing past white, which reads as light radiating outward.
    func radialGlow(
        at center: CGPoint,
        radius: CGFloat,
        color: CIColor,
        over background: CIImage
    ) -> CIImage {
        guard radius > 1, center.x.isFinite, center.y.isFinite, color.alpha > 0.001,
              let gradient = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: center.x, y: center.y),
                "inputRadius0": 0,
                "inputRadius1": radius,
                "inputColor0": color,
                "inputColor1": CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
              ])?.outputImage
        else { return background }

        return gradient.cropped(to: background.extent)
            .applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: background])
            .cropped(to: background.extent)
    }
}
