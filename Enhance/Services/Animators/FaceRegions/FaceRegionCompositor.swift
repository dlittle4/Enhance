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

    /// Composite a burst of light radiating from `center` — a bright core, a soft bloom, and
    /// distinct shafts fanning outward, like an all-seeing eye.
    ///
    /// **Built from discrete analytic shapes, deliberately — the same construction as
    /// `LazerEyesEffect`.** An earlier version streaked `CIRandomGenerator` noise with
    /// `CIZoomBlur`; smeared noise is inherently mushy, because the blur averages neighbouring
    /// values into a continuous wash and no amount of contrast fully separates it back into
    /// shafts. Each beam here is its own radial gradient squashed into a thin shaft and
    /// rotated into place, so its edges stay clean at any length. Additive compositing (again
    /// as LAZER EYES does) keeps the light punchy rather than milky.
    ///
    /// Lazy — no `CIContext`, no `createCGImage`.
    ///
    /// - Parameters:
    ///   - coreRadius: radius of the bright central glow.
    ///   - rayLength: how far the shafts reach from the centre.
    ///   - rayDensity: `0…1`, mapped to the number of shafts.
    ///   - rayAngle: rotation of the whole fan about `center`, in radians, so it can spin.
    func radialLight(
        at center: CGPoint,
        coreRadius: CGFloat,
        rayLength: CGFloat,
        rayDensity: CGFloat,
        rayAngle: CGFloat,
        color: CIColor,
        over background: CIImage
    ) -> CIImage {
        guard coreRadius > 1, center.x.isFinite, center.y.isFinite, color.alpha > 0.001,
              rayLength.isFinite, rayLength > 1 else { return background }
        let extent = background.extent
        let a = max(0, min(1, color.alpha))
        let (r, g, b) = (color.red, color.green, color.blue)
        let density = max(0, min(1, rayDensity))

        var layers: [CIImage] = []

        // Soft bloom, then a tighter core — a small bright centre inside a gentle halo reads
        // as a lit eye, where one wide gradient reads as haze.
        if let bloom = radialSprite(center: center, innerRadius: coreRadius * 0.10,
                                    outerRadius: coreRadius * 1.5,
                                    color: CIColor(red: r, green: g, blue: b, alpha: a * 0.16)) {
            layers.append(bloom)
        }
        if let core = radialSprite(center: center, innerRadius: coreRadius * 0.12,
                                   outerRadius: coreRadius * 0.60,
                                   color: CIColor(red: min(1, r * 0.5 + 0.5),
                                                  green: min(1, g * 0.5 + 0.5),
                                                  blue: min(1, b * 0.5 + 0.5), alpha: a * 0.42)) {
            layers.append(core)
        }

        // Shafts. Each spoke is one gradient through the centre, so it renders as two opposite
        // rays — 4…11 spokes gives 8…22 visible shafts across the INTENSITY range.
        let spokes = 4 + Int((density * 7).rounded())
        let shaftAlpha = a * (0.20 + 0.16 * density)
        for i in 0..<spokes {
            let theta = rayAngle + CGFloat(i) * .pi / CGFloat(spokes)
            if let beam = beamSprite(center: center, length: rayLength * 2,
                                     thickness: max(2, coreRadius * 0.26), angle: theta,
                                     color: CIColor(red: r, green: g, blue: b, alpha: shaftAlpha)) {
                layers.append(beam)
            }
        }

        var result = background
        for layer in layers {
            result = layer.cropped(to: extent)
                .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: result])
        }
        return result.cropped(to: extent)
    }

    /// A finite round glow sprite centred on `center`, fading to transparent at `outerRadius`.
    private func radialSprite(center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, color: CIColor) -> CIImage? {
        let diameter = outerRadius * 2 + 4
        guard diameter.isFinite, diameter > 2 else { return nil }
        guard let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            kCIInputCenterKey: CIVector(x: diameter / 2, y: diameter / 2),
            "inputRadius0": max(0, innerRadius),
            "inputRadius1": max(1, outerRadius),
            "inputColor0": color,
            "inputColor1": CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        ])?.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: diameter, height: diameter)) else { return nil }

        return gradient.transformed(by: CGAffineTransform(
            translationX: center.x - diameter / 2, y: center.y - diameter / 2))
    }

    /// One light shaft: a round gradient squashed into a thin bar, rotated to `angle`, and
    /// centred on `center`. Squashing an analytic gradient keeps the shaft's falloff smooth
    /// along its length while its edges stay defined — which is exactly what smeared noise
    /// could not do.
    private func beamSprite(center: CGPoint, length: CGFloat, thickness: CGFloat, angle: CGFloat, color: CIColor) -> CIImage? {
        let canvas = length
        guard canvas.isFinite, canvas > 2, thickness.isFinite, thickness > 0 else { return nil }
        guard let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            kCIInputCenterKey: CIVector(x: canvas / 2, y: canvas / 2),
            "inputRadius0": canvas * 0.01,
            "inputRadius1": canvas / 2,
            "inputColor0": color,
            "inputColor1": CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        ])?.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: canvas, height: canvas)) else { return nil }

        // Origin to the sprite's centre, squash, rotate, then out to the destination.
        let transform = CGAffineTransform(translationX: -canvas / 2, y: -canvas / 2)
            .concatenating(CGAffineTransform(scaleX: 1, y: max(0.0005, thickness / canvas)))
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
        return gradient.transformed(by: transform)
    }
}
