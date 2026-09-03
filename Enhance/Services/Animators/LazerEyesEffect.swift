import CoreImage

/// Overlays bright glowing eyes at the detected pupil positions, with either a full-width
/// horizontal lens flare (the classic look, `aim == nil`) or — once the user has aimed —
/// a beam from each eye to the target and a scorch mark where they land. Uses additive
/// compositing for realistic light bloom. Intensity controls glow radius and brightness.
///
/// **Two looks, one switch.** The unaimed render is byte-for-byte the effect that shipped:
/// every thumbnail, every existing GIF and every test that never mentions a target sees
/// exactly what it saw before. The aimed render only replaces the *flare* — the eye glow
/// itself is shared, so the two cannot drift in colour or brightness.
struct LazerEyesEffect: FaceEffect {
    private let intensityScale: CGFloat
    private let sizeScale: CGFloat
    private let colorR: CGFloat
    private let colorG: CGFloat
    private let colorB: CGFloat
    /// Where the beams point, or `nil` for the classic edge-to-edge flare.
    private let aim: LaserAim?
    /// How deeply the pulses cut into the beam: 0 is a steady beam, 1 goes fully dark between
    /// crests.
    private let pulseDepth: CGFloat
    /// Cycles the pulse pattern advances per frame — how fast the energy travels.
    private let pulseRate: CGFloat

    /// The ring kernel in `Shaders/CI/LaserPulse.ci.metal`. Nil if the metallib is missing, in
    /// which case the beams simply do not pulse — the effect never fails outright over a
    /// decoration.
    private static let pulseKernel: CIColorKernel? = {
        guard let url = Bundle.main.url(forResource: "LaserPulse.ci", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CIColorKernel(functionName: "laserPulse", fromMetalLibraryData: data)
    }()

    static var pulseKernelIsAvailable: Bool { pulseKernel != nil }

    /// - Parameters:
    ///   - pulse: pulse depth, 0…1. Zero (the default here) is the steady beam every thumbnail
    ///     shows; the editor's PULSE row defaults to the midpoint.
    ///   - pulseSpeed: 0…1, mapped to roughly 3 to 30 frames per pulse at 25fps.
    init(intensity: Double = 0.5, size: Double = 0.5, laserColor: LaserColor = .red, aim: LaserAim? = nil,
         pulse: Double = 0, pulseSpeed: Double = 0.5) {
        self.intensityScale = max(0.1, CGFloat(intensity))
        self.sizeScale = 0.3 + 1.7 * CGFloat(max(0, min(1, size)))
        let (r, g, b) = laserColor.rgb
        self.colorR = r
        self.colorG = g
        self.colorB = b
        self.aim = aim
        self.pulseDepth = CGFloat(max(0, min(1, pulse)))
        // 0.033…0.33 cycles per frame: a slow throb at the bottom, a rapid strobe at the top.
        self.pulseRate = 0.033 + 0.3 * CGFloat(max(0, min(1, pulseSpeed)))
    }

    /// The beam's animation, as fractions of the GIF's progress.
    ///
    /// The eyes start glowing at 0.3 (unchanged). The beams then *travel* from the eye to the
    /// target over the next stretch and the scorch blooms once they arrive — so the GIF reads
    /// as "charge, fire, burn" rather than a beam that is simply there. The preview renders at
    /// progress 1.0 and shows the finished state.
    static let beamStart: CGFloat = 0.3
    static let beamArrival: CGFloat = 0.6
    static let scorchSettled: CGFloat = 0.8

    /// How far along its path the beam has reached at `progress`, 0…1, eased so it accelerates
    /// out of the eye rather than crawling.
    static func beamReach(at progress: CGFloat) -> CGFloat {
        let t = max(0, min(1, (progress - beamStart) / (beamArrival - beamStart)))
        return t * t * (3 - 2 * t)
    }

    /// How fully the scorch has bloomed at `progress`, 0…1. Zero until the beam arrives.
    static func scorchBloom(at progress: CGFloat) -> CGFloat {
        let t = max(0, min(1, (progress - beamArrival) / (scorchSettled - beamArrival)))
        return t * t * (3 - 2 * t)
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        guard progress > Self.beamStart else { return image }
        var result = applyEyes(to: image, face: face, progress: progress, frameIndex: frameIndex)
        if let aim {
            result = applyScorch(to: result, at: aim.point(in: image.extent), face: face, progress: progress, frameIndex: frameIndex)
        }
        return result.cropped(to: image.extent)
    }

    /// Every face fires at the same target, so the scorch is drawn **once** after all the
    /// beams rather than once per face — two faces aiming at one spot should not burn it
    /// twice as dark. The classic look has no shared element and takes the default loop.
    func apply(to image: CIImage, faces: [DetectedFace], progress: CGFloat, frameIndex: Int) -> CIImage {
        guard let aim else {
            var result = image
            for face in faces {
                result = apply(to: result, face: face, progress: progress, frameIndex: frameIndex)
            }
            return result
        }
        guard progress > Self.beamStart, let reference = faces.first else { return image }

        var result = image
        for face in faces {
            result = applyEyes(to: result, face: face, progress: progress, frameIndex: frameIndex)
        }
        // Sized from the largest face, so a distant second face cannot shrink the burn.
        let largest = faces.max(by: { $0.faceWidth < $1.faceWidth }) ?? reference
        result = applyScorch(to: result, at: aim.point(in: image.extent), face: largest, progress: progress, frameIndex: frameIndex)
        return result.cropped(to: image.extent)
    }

    // MARK: - Per-face pass

    private func applyEyes(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let ramp = (progress - Self.beamStart) / (1 - Self.beamStart)
        let fade = ramp * ramp
        let imageWidth = image.extent.width
        let target = aim?.point(in: image.extent)
        var result = image

        if let leftPupil = face.leftPupilCenter {
            let eyeRadius = max(face.leftEyeWidth, face.faceWidth * 0.06)
            result = compositeEyeGlow(over: result, center: leftPupil, eyeRadius: eyeRadius, imageWidth: imageWidth, opacity: fade, target: target, progress: progress, frameIndex: frameIndex, seed: 0)
        }

        if let rightPupil = face.rightPupilCenter {
            let eyeRadius = max(face.rightEyeWidth, face.faceWidth * 0.06)
            result = compositeEyeGlow(over: result, center: rightPupil, eyeRadius: eyeRadius, imageWidth: imageWidth, opacity: fade, target: target, progress: progress, frameIndex: frameIndex, seed: 7)
        }

        return result
    }

    // MARK: - Eye Glow Compositing

    private func compositeEyeGlow(over image: CIImage, center: CGPoint, eyeRadius: CGFloat, imageWidth: CGFloat, opacity: CGFloat, target: CGPoint?, progress: CGFloat, frameIndex: Int, seed: Int) -> CIImage {
        let coreRadius = eyeRadius * 0.5 * intensityScale * sizeScale
        let glowRadius = eyeRadius * 1.8 * intensityScale * sizeScale
        let bloomRadius = eyeRadius * 4.0 * intensityScale * sizeScale

        let flicker = flickerMultiplier(frameIndex: frameIndex, seed: seed)
        let alpha = opacity * flicker

        let coreR = 0.5 + colorR * 0.5
        let coreG = 0.5 + colorG * 0.5
        let coreB = 0.5 + colorB * 0.5

        let core = makeRadialGlow(
            center: center,
            innerRadius: max(1, coreRadius * 0.5),
            outerRadius: coreRadius,
            color: CIColor(red: coreR, green: coreG, blue: coreB, alpha: alpha)
        )

        let innerGlow = makeRadialGlow(
            center: center,
            innerRadius: max(1, glowRadius * 0.15),
            outerRadius: glowRadius,
            color: CIColor(red: colorR, green: colorG, blue: colorB, alpha: alpha * 0.95)
        )

        let deepR = colorR * 0.8
        let deepG = colorG * 0.8
        let deepB = colorB * 0.8
        let bloom = makeRadialGlow(
            center: center,
            innerRadius: max(1, bloomRadius * 0.08),
            outerRadius: bloomRadius,
            color: CIColor(red: deepR, green: deepG, blue: deepB, alpha: alpha * 0.5)
        )

        let narrowHeight = eyeRadius * 0.4 * intensityScale * sizeScale
        let wideHeight = eyeRadius * 2.0 * intensityScale * sizeScale
        let narrowColor = CIColor(red: colorR, green: colorG, blue: colorB, alpha: alpha * 0.85)
        let wideColor = CIColor(red: colorR * 0.7, green: colorG * 0.7, blue: colorB * 0.7, alpha: alpha * 0.35)

        var narrowFlare: CIImage?
        var wideFlare: CIImage?
        if let target {
            // Aimed: a beam from the eye that travels to the target. The wide layer is the
            // beam's halo, so it lags the bright core slightly and never overshoots it.
            let reach = Self.beamReach(at: progress)
            narrowFlare = makeBeam(from: center, to: target, reach: reach, height: narrowHeight, color: narrowColor)
            wideFlare = makeBeam(from: center, to: target, reach: reach * 0.96, height: wideHeight, color: wideColor)
        } else {
            let flareWidth = imageWidth * sizeScale
            narrowFlare = makeHorizontalFlare(center: center, width: flareWidth, height: narrowHeight, color: narrowColor)
            wideFlare = makeHorizontalFlare(center: center, width: flareWidth, height: wideHeight, color: wideColor)
        }

        // Pulses ride on the flares and on the wide bloom — the rings visibly leave the eye and
        // carry on along the beam. The core and inner glow stay steady, which is what makes it
        // read as energy *leaving* the eye rather than the eye blinking. The bloom matters more
        // than it looks: profiled on a 200px face, it supplies most of the light within ~40px of
        // the pupil and the flare is nearly gone beyond that, so a flare-only pulse was invisible.
        narrowFlare = pulsed(narrowFlare, from: center, eyeRadius: eyeRadius, frameIndex: frameIndex)
        wideFlare = pulsed(wideFlare, from: center, eyeRadius: eyeRadius, frameIndex: frameIndex)
        let bloomPulsed = pulsed(bloom, from: center, eyeRadius: eyeRadius, frameIndex: frameIndex)

        guard let addFilter = CIFilter(name: "CIAdditionCompositing") else { return image }

        var result = image
        for layer in [wideFlare, bloomPulsed, narrowFlare, innerGlow, core] {
            guard let layer = layer else { continue }
            addFilter.setValue(layer, forKey: kCIInputImageKey)
            addFilter.setValue(result, forKey: kCIInputBackgroundImageKey)
            if let out = addFilter.outputImage {
                result = out
            }
        }

        return result
    }

    // MARK: - Pulse

    /// Rings of light expanding from the pupil, applied to one flare layer.
    ///
    /// The wavelength follows the eye so the pulses scale with the face, and the phase follows
    /// `frameIndex` rather than `progress` so the rate is a speed in the finished GIF rather than
    /// a count of pulses stretched over whatever duration the speed slider produced.
    private func pulsed(_ layer: CIImage?, from center: CGPoint, eyeRadius: CGFloat, frameIndex: Int) -> CIImage? {
        guard let layer, pulseDepth > 0.001, let kernel = Self.pulseKernel else { return layer }
        let wavelength = max(6, eyeRadius * 2.5 * sizeScale)
        let phase = CGFloat(frameIndex) * pulseRate
        // Deeper pulses are also sharper, so the top of the slider is distinct packets of energy
        // rather than the same sine at a larger amplitude.
        let sharpness = 1.0 + 5.0 * pulseDepth
        return kernel.apply(
            extent: layer.extent,
            arguments: [layer, CIVector(x: center.x, y: center.y), wavelength, phase, pulseDepth, sharpness]
        ) ?? layer
    }

    // MARK: - Scorch

    /// The burn where the beams land: a dark charred disc laid *over* the photo, ringed by an
    /// additive ember glow in the laser's colour warmed toward orange, with a hot white pit at
    /// the centre. Blooms from a point as the beam arrives, and the ember flickers with the eyes.
    private func applyScorch(to image: CIImage, at target: CGPoint, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let bloom = Self.scorchBloom(at: progress)
        guard bloom > 0 else { return image }

        let eyeRadius = max(max(face.leftEyeWidth, face.rightEyeWidth), face.faceWidth * 0.06)
        let radius = eyeRadius * 1.6 * sizeScale * (0.5 + 0.5 * intensityScale) * (0.55 + 0.45 * bloom)
        let flicker = flickerMultiplier(frameIndex: frameIndex, seed: 13)

        var result = image

        // Char: source-over, because a burn *removes* light rather than adding it.
        if let char = makeRadialGlow(
            center: target,
            innerRadius: max(1, radius * 0.35),
            outerRadius: radius,
            color: CIColor(red: 0.02, green: 0.01, blue: 0.0, alpha: 0.92 * bloom)
        ), let over = CIFilter(name: "CISourceOverCompositing") {
            over.setValue(char, forKey: kCIInputImageKey)
            over.setValue(result, forKey: kCIInputBackgroundImageKey)
            if let out = over.outputImage { result = out }
        }

        // Ember ring and hot pit: additive, like the eyes.
        let emberR = min(1, colorR * 0.6 + 0.5)
        let emberG = min(1, colorG * 0.6 + 0.25)
        let emberB = colorB * 0.4
        let ember = makeRadialGlow(
            center: target,
            innerRadius: max(1, radius * 0.6),
            outerRadius: radius * 1.5,
            color: CIColor(red: emberR, green: emberG, blue: emberB, alpha: 0.75 * bloom * flicker)
        )
        let pit = makeRadialGlow(
            center: target,
            innerRadius: 1,
            outerRadius: max(2, radius * 0.3),
            color: CIColor(red: 1, green: 0.9, blue: 0.7, alpha: 0.9 * bloom * flicker)
        )

        guard let addFilter = CIFilter(name: "CIAdditionCompositing") else { return result }
        for layer in [ember, pit] {
            guard let layer else { continue }
            addFilter.setValue(layer, forKey: kCIInputImageKey)
            addFilter.setValue(result, forKey: kCIInputBackgroundImageKey)
            if let out = addFilter.outputImage { result = out }
        }
        return result
    }

    // MARK: - Glow Layers

    private func makeRadialGlow(center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, color: CIColor) -> CIImage? {
        let diameter = outerRadius * 2 + 4
        let localCenter = CIVector(x: diameter / 2, y: diameter / 2)

        guard let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            kCIInputCenterKey: localCenter,
            "inputRadius0": innerRadius,
            "inputRadius1": outerRadius,
            "inputColor0": color,
            "inputColor1": CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        ])?.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: diameter, height: diameter)) else {
            return nil
        }

        return gradient.transformed(by: CGAffineTransform(
            translationX: center.x - diameter / 2,
            y: center.y - diameter / 2
        ))
    }

    /// Full-width horizontal lens flare beam using a vertically-squashed radial gradient.
    private func makeHorizontalFlare(center: CGPoint, width: CGFloat, height: CGFloat, color: CIColor) -> CIImage? {
        let canvasW = width + 4
        let canvasH = canvasW
        let localCenter = CIVector(x: canvasW / 2, y: canvasH / 2)
        let radius = canvasW / 2

        guard let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            kCIInputCenterKey: localCenter,
            "inputRadius0": radius * 0.01,
            "inputRadius1": radius,
            "inputColor0": color,
            "inputColor1": CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        ])?.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: canvasW, height: canvasH)) else {
            return nil
        }

        let scaleY = height / canvasH
        let transform = CGAffineTransform(translationX: 0, y: canvasH / 2)
            .scaledBy(x: 1.0, y: scaleY)
            .translatedBy(x: 0, y: -canvasH / 2)

        let squashed = gradient.transformed(by: transform)

        return squashed.transformed(by: CGAffineTransform(
            translationX: center.x - canvasW / 2,
            y: center.y - canvasH * scaleY / 2
        ))
    }

    /// A beam from `origin` toward `target`, covering `reach` (0…1) of the distance.
    ///
    /// The same squashed radial gradient as the flare — so a beam and a flare share one
    /// texture — rotated to lie along the line and centred on the *travelled* segment's
    /// midpoint. The gradient's soft ends are what make it read as light: the beam fades into
    /// the eye and into the scorch rather than butting against either. Slightly over-long so
    /// that at full reach the bright core spans the whole path rather than tapering short of it.
    private func makeBeam(from origin: CGPoint, to target: CGPoint, reach: CGFloat, height: CGFloat, color: CIColor) -> CIImage? {
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let distance = hypot(dx, dy)
        guard reach > 0, distance > 1 else { return nil }

        let travelled = distance * reach
        let length = travelled * 1.15 + height
        let canvas = length + 4
        let localCenter = CIVector(x: canvas / 2, y: canvas / 2)

        guard let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            kCIInputCenterKey: localCenter,
            "inputRadius0": canvas * 0.01,
            "inputRadius1": canvas / 2,
            "inputColor0": color,
            "inputColor1": CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        ])?.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: canvas, height: canvas)) else {
            return nil
        }

        // Squash to the beam's thickness, then move the beam's centre to the origin so the
        // rotation pivots on it, rotate along the line, and carry it out to the midpoint of
        // the travelled segment.
        let scaleY = height / canvas
        let squash = CGAffineTransform(translationX: 0, y: canvas / 2)
            .scaledBy(x: 1.0, y: scaleY)
            .translatedBy(x: 0, y: -canvas / 2)
        let recentre = CGAffineTransform(translationX: -canvas / 2, y: -canvas / 2)

        let angle = atan2(dy, dx)
        let mid = CGPoint(x: origin.x + dx * reach / 2, y: origin.y + dy * reach / 2)
        let place = CGAffineTransform(translationX: mid.x, y: mid.y).rotated(by: angle)

        return gradient
            .transformed(by: squash)
            .transformed(by: recentre)
            .transformed(by: place)
    }

    /// Subtle per-frame brightness variation to simulate energy flicker.
    private func flickerMultiplier(frameIndex: Int, seed: Int) -> CGFloat {
        var x = UInt64(frameIndex * 137 + seed * 31 + 53)
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        let norm = CGFloat(x % 1000) / 1000.0
        return 0.88 + norm * 0.12
    }
}
