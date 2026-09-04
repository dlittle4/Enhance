import CoreImage

/// SPEED LINES — comic streaks trailing the subject, opposite to the way it is moving, from a
/// burst's motion context (FEATURE-MOTION-EFFECTS.md §3). Stock filters only: the current
/// mask is smeared along the motion and shifted back to make a wedge behind the body, the
/// body itself is cut out of that wedge, and a stripe pattern rotated to run along the motion
/// is drawn through it, under the subject.
///
/// Without a context, a mask, or any motion it returns the frame untouched.
struct SpeedLinesEffect: VisualEffect {
    /// How far the lines reach, as a fraction of the frame.
    private let length: CGFloat
    /// Stripe pitch: 0 is sparse, 1 is dense.
    private let density: CGFloat
    private let color: CIColor

    /// Below this, in normalized units per frame, the subject reads as still and no lines draw.
    static let minimumSpeed: CGFloat = 0.004

    /// - Parameters:
    ///   - intensity: LENGTH, 0…1.
    ///   - density: 0…1.
    ///   - color: the lines' colour; nil is white.
    init(intensity: Double = 0.5, density: Double = 0.5, color: LaserColor? = nil) {
        self.length = CGFloat(max(0, min(1, intensity)))
        self.density = CGFloat(max(0, min(1, density)))
        if let color {
            let (r, g, b) = color.rgb
            self.color = CIColor(red: r, green: g, blue: b, alpha: 1)
        } else {
            self.color = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage { image }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, geometry: FrameGeometry, motion: MotionContext?) -> CIImage {
        guard let motion, let rawMask = motion.mask, length > 0.01 else { return image }
        let velocity = motion.velocity
        guard velocity.motionMagnitude >= Self.minimumSpeed,
              let mask = motion.place(rawMask, in: image, geometry: geometry)
        else { return image }

        let extent = image.extent
        let reach = length * 0.45 * min(extent.width, extent.height)
        let angle = velocity.motionAngle
        let back = CGVector(dx: -cos(angle), dy: -sin(angle))

        // The wedge: the silhouette smeared along the motion and pushed back so it lies
        // behind the body, minus the body, so the lines start at the trailing edge.
        let smeared = mask
            .clampedToExtent()
            .applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: reach, kCIInputAngleKey: angle])
            .transformed(by: CGAffineTransform(translationX: back.dx * reach * 0.6, y: back.dy * reach * 0.6))
            .cropped(to: extent)
        let bodyCleared = mask.applyingFilter("CIColorInvert")
        let wedge = smeared
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: bodyCleared])
            .applyingFilter("CIColorMatrix", parameters: [
                // Lift the smear's soft falloff into a firmer wedge.
                "inputRVector": CIVector(x: 1.8, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.8, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1.8, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
            .cropped(to: extent)

        // Stripes running along the motion: the generator's bands vary along x, so rotate by
        // the motion angle plus a quarter turn.
        let pitch = 4 + (1 - density) * 14
        let stripes = CIFilter(name: "CIStripesGenerator", parameters: [
            kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY),
            "inputColor0": color,
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
            kCIInputWidthKey: pitch,
            kCIInputSharpnessKey: 0.9
        ])?.outputImage?
            .transformed(by: CGAffineTransform(translationX: -extent.midX, y: -extent.midY)
                .concatenating(CGAffineTransform(rotationAngle: angle + .pi / 2))
                .concatenating(CGAffineTransform(translationX: extent.midX, y: extent.midY)))
            .cropped(to: extent)
        guard let stripes else { return image }

        let lines = stripes.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent),
            kCIInputMaskImageKey: wedge
        ])
        var result = lines.applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: image])
        // The subject back on top, so lines never cross the body.
        if let subject = motion.subjectCutout(back: 0, in: image, geometry: geometry) {
            result = subject.applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: result])
        }
        return result.cropped(to: extent)
    }
}
