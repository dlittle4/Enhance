import CoreImage

/// Everything an effect may want to know about the frames around the one it is drawing:
/// earlier frames, a subject mask per frame, and how the subject and the camera moved. The
/// foundation of FEATURE-MOTION-EFFECTS.md — `nil` for a still, so every existing effect is
/// untouched.
///
/// **Frames and masks are in the burst's own pixel space, not the frame's.** The generator
/// applies effects after the zoom, on a 600px output; the preview applies them on a 650px
/// copy. Rather than pre-scaling every image for every path, an effect places what it needs
/// through `place(_:in:geometry:)`, which is the same source→frame mapping
/// `SubjectMaskCompositor.maskInFrameSpace` uses for the still's mask. The geometry the
/// generator already hands every effect carries the mapping; the preview passes one whose
/// content rect is its own extent.
public struct MotionContext {
    /// Index of the frame being drawn, within the burst.
    public let index: Int
    /// Every burst frame, as lazy `CIImage`s over the decoded frames.
    public let frames: [CIImage]
    /// A subject mask per frame — white subject on black — or `nil` where segmentation found
    /// nothing or has not finished yet. Same count as `frames`.
    public let masks: [CIImage?]
    /// The subject's motion this frame, normalized frame units per frame.
    public let subjectVelocity: CGVector
    /// The camera's motion this frame, normalized frame units per frame.
    public let cameraVelocity: CGVector

    public init(index: Int, frames: [CIImage], masks: [CIImage?], subjectVelocity: CGVector, cameraVelocity: CGVector) {
        self.index = index
        self.frames = frames
        self.masks = masks
        self.subjectVelocity = subjectVelocity
        self.cameraVelocity = cameraVelocity
    }

    public var frameCount: Int { frames.count }

    /// Whichever of the two velocities is worth reading: the subject's when a face was
    /// tracked, else the camera's, so a burst of a cat still gets motion from what moved.
    public var velocity: CGVector {
        subjectVelocity.motionMagnitude > 0 ? subjectVelocity : cameraVelocity
    }

    /// The frame `offset` frames back (1 = the one before). Nil past the start.
    public func frame(back offset: Int) -> CIImage? {
        let i = index - offset
        guard offset >= 0, frames.indices.contains(i) else { return nil }
        return frames[i]
    }

    /// The mask `offset` frames back. Nil past the start, or where there is no mask.
    public func mask(back offset: Int) -> CIImage? {
        let i = index - offset
        guard offset >= 0, masks.indices.contains(i) else { return nil }
        return masks[i]
    }

    /// The current frame's mask.
    public var mask: CIImage? { mask(back: 0) }

    /// Places a burst-space image (a frame or a mask) into the frame being drawn. Clamped so
    /// its edges extend to the frame's corners, as the compositor does for masks, and nil for
    /// a degenerate geometry rather than a wrongly scaled composite.
    public func place(_ image: CIImage, in frame: CIImage, geometry: FrameGeometry) -> CIImage? {
        let rect = geometry.contentRect
        guard image.extent.width >= 1, image.extent.height >= 1, image.extent.hasFiniteComponents,
              rect.isNull || (rect.hasFiniteComponents && rect.width > 0 && rect.height > 0)
        else { return nil }
        let placed = image.transformed(by: geometry.sourceToFrame(sourceExtent: image.extent))
        guard placed.extent.hasFiniteComponents else { return nil }
        return placed.clampedToExtent().cropped(to: frame.extent)
    }

    /// The subject `offset` frames back, cut out of its own frame and placed into this one,
    /// background transparent. Nil without a frame or a mask there.
    public func subjectCutout(back offset: Int, in frame: CIImage, geometry: FrameGeometry) -> CIImage? {
        guard let source = self.frame(back: offset), let mask = mask(back: offset),
              let placedFrame = place(source, in: frame, geometry: geometry),
              let placedMask = place(mask, in: frame, geometry: geometry)
        else { return nil }
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: frame.extent)
        return placedFrame
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: clear,
                kCIInputMaskImageKey: placedMask
            ])
            .cropped(to: frame.extent)
    }
}
