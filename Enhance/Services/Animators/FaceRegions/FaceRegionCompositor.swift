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
    ///   - tint: optional colour applied to the sampled feature (a coloured third eye), as a
    ///     luminance-preserving monochrome so the pupil stays dark and the iris takes the hue.
    func composite(
        _ placement: FaceRegionPlacement,
        source: CIImage,
        over background: CIImage,
        face: DetectedFace,
        padding: CGFloat,
        feather: CGFloat,
        tint: CIColor? = nil
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
        var sampled = source.clampedToExtent().cropped(to: padded)
        if let tint {
            sampled = sampled.applyingFilter("CIColorMonochrome", parameters: [
                "inputColor": tint, "inputIntensity": 0.7
            ])
        }

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

    /// Screen a burst of light radiating outward from `center` onto the image — distinct
    /// warm beams fanning out from the eye plus a bright core, like an all-seeing eye.
    ///
    /// The beams come from streaking *angular variation* radially: a smooth core zoom-blurs
    /// to a smooth glow (no rays), so this seeds coarse, contrasty noise and smears it with
    /// `CIZoomBlur` (the LENS effect's mechanism) into rays, shaped by a radial falloff so
    /// they emanate from the eye and fade out. Deterministic — `CIRandomGenerator` is a fixed
    /// pattern — and lazy (no `CIContext`). Two screen passes accumulate the light.
    ///
    /// - Parameters:
    ///   - coreRadius: radius of the bright central glow.
    ///   - rayAmount: `CIZoomBlur` amount — how far the beams reach.
    ///   - rayDensity: `0…1`, how many beams — finer noise (more beams) at 1, coarser at 0.
    ///   - rayAngle: rotation of the beam pattern about `center`, in radians, so the rays can
    ///     spin around the eye across frames.
    func radialLight(
        at center: CGPoint,
        coreRadius: CGFloat,
        rayAmount: CGFloat,
        rayDensity: CGFloat,
        rayAngle: CGFloat,
        color: CIColor,
        over background: CIImage
    ) -> CIImage {
        guard coreRadius > 1, center.x.isFinite, center.y.isFinite, color.alpha > 0.001 else { return background }
        let c = CIVector(x: center.x, y: center.y)
        let extent = background.extent

        // Warm tint at the requested overall strength (folded into every light layer).
        let a = color.alpha
        func warm(_ image: CIImage) -> CIImage {
            image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: color.red * a, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: color.green * a, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: color.blue * a, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        }
        func screen(_ light: CIImage, over bg: CIImage) -> CIImage {
            warm(light).cropped(to: extent)
                .applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: bg])
                .cropped(to: extent)
        }

        // 1. Bright central glow (opaque black → warm centre so screen only lightens).
        var result = background
        if let core = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": c, "inputRadius0": coreRadius * 0.15, "inputRadius1": coreRadius * 1.3,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        ])?.outputImage {
            result = screen(core, over: result)
        }

        // 2. Radial beams: coarse contrasty noise, rotated about the eye (so the beams can
        // spin), coarsened by density (finer = more beams), streaked out, and faded by a
        // radial falloff. Rotating the noise rotates the resulting rays.
        let density = max(0, min(1, rayDensity))
        let blockScale = max(3, coreRadius * (0.30 - 0.24 * density))  // more density → finer → more rays
        let spin = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: rayAngle)
            .translatedBy(x: -center.x, y: -center.y)
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .transformed(by: spin)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0, kCIInputContrastKey: 2.6, kCIInputBrightnessKey: -0.28
            ])
            .applyingFilter("CIPixellate", parameters: [
                "inputCenter": c, "inputScale": blockScale
            ])
            .applyingFilter("CIZoomBlur", parameters: ["inputCenter": c, "inputAmount": max(1, rayAmount)])

        if let falloff = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": c, "inputRadius0": coreRadius * 0.2, "inputRadius1": coreRadius * 3.2,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        ])?.outputImage {
            let beams = noise.applyingFilter("CIMultiplyBlendMode", parameters: [
                kCIInputBackgroundImageKey: falloff
            ])
            result = screen(beams, over: result)
        }

        return result
    }
}
