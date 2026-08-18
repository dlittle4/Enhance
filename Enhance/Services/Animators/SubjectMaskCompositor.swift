import CoreImage

/// Splits a frame into subject and background using a segmentation mask, and reassembles the
/// two halves. The shared half of the §2f subject-mask effects: EFFECTS.md specifies them as
/// "one mask, five composites", and this is the one mask — the five differ only in what they
/// put on each side.
///
/// Mirrors `FaceRegionCompositor`'s contract: a struct that never creates a `CIContext` or
/// calls `createCGImage`, so the returned graph stays lazy until the caller's shared context
/// evaluates it, and any degenerate input returns the frame unchanged rather than producing a
/// seam or a crash.
///
/// **The mask arrives in source space and has to be placed into frame space.** The GIF
/// pipeline applies effects *after* the zoom/pan transform, while
/// `SubjectSegmentationService` produces a mask the size of the original photo. Mapping one to
/// the other needs the aspect-fill factor and the zoom together, which is what
/// `FrameGeometry.sourceToFrame` carries. Skip it and the cutout drifts off the subject as the
/// animation pans — the identical failure `contentOrigin` was introduced to prevent for grid
/// effects, and it would look like a segmentation bug rather than a geometry one.
///
/// **A `nil` mask always returns the frame untouched.** Per ROADMAP §1g the editor keeps the
/// cards live on a photo with no subject, following the face precedent, so every one of these
/// effects has to degrade to identity rather than render something broken.
struct SubjectMaskCompositor {

    /// Place a source-space mask onto the frame. Returns `nil` if the geometry is degenerate.
    ///
    /// Clamped before transforming so the mask's edge pixels extend to the frame's corners
    /// rather than sampling transparency: the photo is aspect-filled, so at zoom 1 the mask
    /// covers the frame exactly, but a zoom that pans toward an edge would otherwise expose
    /// unmasked border — which reads as the background effect abruptly stopping.
    func maskInFrameSpace(_ mask: CIImage, frame: CIImage, geometry: FrameGeometry) -> CIImage? {
        let transform = geometry.sourceToFrame
        guard mask.extent.width >= 1, mask.extent.height >= 1,
              geometry.scale.isFinite, geometry.scale > 0,
              geometry.contentScale.isFinite, geometry.contentScale > 0,
              geometry.contentOrigin.x.isFinite, geometry.contentOrigin.y.isFinite
        else { return nil }

        let placed = mask.transformed(by: transform)
        guard placed.extent.hasFiniteComponents else { return nil }

        return placed.clampedToExtent().cropped(to: frame.extent)
    }

    /// Hold the subject flat while `background` replaces everything behind it.
    ///
    /// The general form of four of the five §2f effects — the caller decides what
    /// `background` is: the same frame with a visual effect on it (face cutout), a procedural
    /// animation (animated background), the frame plus a text raster (text behind subject), or
    /// tiled copies of the cutout (repeated pattern).
    func subject(
        of frame: CIImage,
        over background: CIImage,
        mask: CIImage?,
        geometry: FrameGeometry
    ) -> CIImage {
        guard let mask,
              let placed = maskInFrameSpace(mask, frame: frame, geometry: geometry)
        else { return frame }

        return frame
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: background,
                kCIInputMaskImageKey: placed
            ])
            .cropped(to: frame.extent)
    }

    /// Run `effect` on the background only, holding the subject untouched.
    ///
    /// The highest-leverage member of §2f, because it is a *multiplier* on the fifteen visual
    /// effects that already ship rather than a new effect. Note the effect runs on the whole
    /// frame and the mask then chooses per pixel — it is not applied to a cut-out background
    /// in isolation. That matters for effects that sample their neighbourhood: a blur pulling
    /// from a hole where the subject was would darken the halo around it.
    ///
    /// It is also why the §1g spike found fine hair and whiskers survive despite the mask not
    /// resolving them — an unresolved strand is not cut off, it simply receives the
    /// background's treatment.
    func applyingToBackground(
        _ effect: VisualEffect,
        of frame: CIImage,
        mask: CIImage?,
        progress: CGFloat,
        frameIndex: Int,
        viewportCenter: CGPoint? = nil,
        geometry: FrameGeometry = .identity
    ) -> CIImage {
        guard mask != nil else { return frame }

        let treated = effect.apply(
            to: frame,
            progress: progress,
            frameIndex: frameIndex,
            viewportCenter: viewportCenter,
            geometry: geometry
        )
        return subject(of: frame, over: treated, mask: mask, geometry: geometry)
    }

    /// The subject alone, background transparent — for effects that move or repeat it
    /// (parallax, subject bounce, repeated pattern).
    ///
    /// Returns `nil` rather than an empty image when there is no mask, so a caller cannot
    /// silently composite nothing and wonder where the subject went.
    func cutout(of frame: CIImage, mask: CIImage?, geometry: FrameGeometry) -> CIImage? {
        guard let mask,
              let placed = maskInFrameSpace(mask, frame: frame, geometry: geometry)
        else { return nil }

        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: frame.extent)

        return frame
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: clear,
                kCIInputMaskImageKey: placed
            ])
            .cropped(to: frame.extent)
    }
}
