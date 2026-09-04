import CoreImage

/// FRAME ECHO — earlier frames' subject cut-outs composited behind the current one at falling
/// opacity: the sports-photo sequence look, from a burst (FEATURE-MOTION-EFFECTS.md §2).
///
/// The first motion effect, and the one that exercises every part of the foundation: it reads
/// previous frames, their masks and the current mask from `MotionContext`, and places them
/// through the frame's geometry. **Without a context it returns the frame untouched** — the
/// card is burst-only in the carousel, and a thumbnail (rendered from one still) shows the
/// plain photo, which is honest.
///
/// Order matters: the current frame, then the echoes oldest-first so nearer ones sit on top,
/// then the current subject re-drawn over everything so an echo never covers the person.
struct FrameEchoEffect: VisualEffect {
    /// Opacity ratio between consecutive echoes: echo `k` draws at `fade^k`.
    private let fade: CGFloat
    /// How many earlier frames to draw.
    private let echoes: Int
    /// Frames between echoes.
    private let spacing: Int
    /// 0 keeps the echoes' own colours; 1 paints them fully in `tint`.
    private let tintStrength: CGFloat
    private let tint: CIColor

    static let maximumEchoes = 6
    static let maximumSpacing = 4

    /// - Parameters:
    ///   - intensity: the FADE slider — how much each echo keeps of the last (0.3…0.95).
    ///   - echoes: 0…1, mapped to 1…6 echoes.
    ///   - spacing: 0…1, mapped to 1…4 frames apart.
    ///   - tintStrength: 0…1.
    init(intensity: Double = 0.5, echoes: Double = 0.5, spacing: Double = 0, tintStrength: Double = 0, color: LaserColor = .red) {
        self.fade = 0.3 + 0.65 * CGFloat(max(0, min(1, intensity)))
        self.echoes = 1 + Int((CGFloat(max(0, min(1, echoes))) * CGFloat(Self.maximumEchoes - 1)).rounded())
        self.spacing = 1 + Int((CGFloat(max(0, min(1, spacing))) * CGFloat(Self.maximumSpacing - 1)).rounded())
        self.tintStrength = CGFloat(max(0, min(1, tintStrength)))
        let (r, g, b) = color.rgb
        self.tint = CIColor(red: r, green: g, blue: b)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage { image }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, geometry: FrameGeometry, motion: MotionContext?) -> CIImage {
        guard let motion else { return image }
        var result = image

        // Oldest first, so the nearest echo lands on top of the farther ones.
        for k in stride(from: echoes, through: 1, by: -1) {
            guard let cutout = motion.subjectCutout(back: k * spacing, in: image, geometry: geometry) else { continue }
            let opacity = pow(fade, CGFloat(k))
            result = tinted(cutout)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)
                ])
                .applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: result])
        }

        // The person as they are now, back on top of their own echoes.
        if let current = motion.subjectCutout(back: 0, in: image, geometry: geometry) {
            result = current.applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: result])
        }
        return result.cropped(to: image.extent)
    }

    /// Blends the cut-out toward a flat tint by `tintStrength`, keeping its alpha.
    private func tinted(_ cutout: CIImage) -> CIImage {
        guard tintStrength > 0.001 else { return cutout }
        let flat = CIImage(color: CIColor(red: tint.red, green: tint.green, blue: tint.blue, alpha: 1))
            .cropped(to: cutout.extent)
        // Multiply the flat colour by the cut-out's alpha so it keeps the silhouette, then mix.
        let silhouette = flat.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: cutout.extent),
            kCIInputMaskImageKey: cutout
        ])
        return cutout.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: silhouette,
            kCIInputTimeKey: tintStrength
        ]).cropped(to: cutout.extent)
    }
}
