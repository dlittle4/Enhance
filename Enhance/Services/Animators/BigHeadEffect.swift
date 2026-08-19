import CoreImage

/// Inflates the head — the cartoon big-head look. ROADMAP §2a.
///
/// One `CIBumpDistortion` centred on the head with a positive scale, which is the same call
/// `HandsomeEffect` already makes to elongate a jaw; only the radius and sign differ. There is
/// no mask: a bump distortion falls off to nothing at its radius, so the surrounding image is
/// untouched without one, and masking it would cut the head off at the mask's edge instead of
/// letting it swell past its original outline — which is the entire effect.
///
/// **It animates with `progress`.** A permanently big head is a still photo of a big head; the
/// joke is the inflation arriving as the zoom lands. The curve is quadratic like
/// `HandsomeEffect`'s, so most of the growth happens late rather than the head being large for
/// the whole loop.
///
/// **On estimated landmarks it distorts *less*, rather than not at all.** Per EFFECTS.md a face
/// found by bounding box alone still gives a usable centre and width — what it lacks is
/// precision — so backing off keeps the effect working on the animal and CIDetector paths
/// instead of making the card do nothing on photos where face detection fell back.
struct BigHeadEffect: FaceEffect {
    private let maxStrength: CGFloat
    private let reach: CGFloat

    /// - Parameters:
    ///   - intensity: how much the head swells.
    ///   - size: how much of the head the bump covers, as a multiple of face width. Below about
    ///     1.2 the distortion stops short of the skull and reads as a bulging face rather than a
    ///     big head, which is why the range starts there rather than at zero.
    init(intensity: Double = 0.5, size: Double = 0.5) {
        self.maxStrength = max(0.05, CGFloat(max(0, min(1, intensity))))
        self.reach = 1.2 + CGFloat(max(0, min(1, size))) * 0.9
    }

    func apply(to image: CIImage, face: DetectedFace, progress: CGFloat, frameIndex: Int) -> CIImage {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1 else { return image }

        // Estimated landmarks give a centre and a width but not much else, so the bump is
        // gentler there — visible, but not so strong that an imprecise centre drags an ear
        // through the middle of the frame.
        // 0.8, not 0.6. The first render of this effect was invisible at full intensity,
        // because an animal face detects as `.estimated` and this damping then compounded with
        // the output scale below — 0.9 intensity reached the filter as 0.32. Backing off on an
        // imprecise centre is still right; backing off until the card does nothing is not.
        let qualityScale: CGFloat = face.landmarkQuality == .estimated ? 0.8 : 1.0

        let strength = maxStrength * (progress * progress) * qualityScale
        guard strength > 0.01 else { return image }

        // Centred slightly above the face centre: the bump's peak should sit on the skull, not
        // the nose, or the face inflates while the crown stays put and it reads as a lens fault.
        let headCentre = CGPoint(
            x: face.faceCenter.x,
            y: face.faceCenter.y + face.faceHeight * 0.15
        )
        let radius = max(face.faceWidth, face.faceHeight) * reach
        guard radius.isFinite, radius > 1,
              headCentre.x.isFinite, headCentre.y.isFinite else { return image }

        // Clamped first, so a head near the frame edge pulls border pixels outward instead of
        // sampling transparency and tearing a hole at the edge.
        return image
            .clamped(to: extent)
            .applyingFilter("CIBumpDistortion", parameters: [
                kCIInputCenterKey: CIVector(x: headCentre.x, y: headCentre.y),
                kCIInputRadiusKey: radius,
                // 1.2 rather than a fraction: `CIBumpDistortion` reads roughly -1…1, and
                // anything under about 0.5 is not legible as a *big head* on a subject that
                // already fills the frame.
                kCIInputScaleKey: strength * 1.2
            ])
            .cropped(to: extent)
    }
}
