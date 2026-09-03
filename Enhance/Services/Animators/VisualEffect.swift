import CoreImage

/// How the frame an effect is handed relates to the source image.
///
/// The GIF pipeline applies effects *after* the zoom/pan transform, so an effect with
/// its own spatial grid — dither cells, halftone screens — is drawing onto a moving
/// target. Two things have to track that motion or the grid reads as a static overlay
/// the photo slides beneath:
///
/// - `scale` keeps the grid's *size* proportional to the content, so cells stay the
///   same size relative to the subject rather than to the output frame.
/// - `contentOrigin` keeps the grid's *phase* aligned, so cells stay over the same
///   image features as the frame pans. Getting size right but not phase still drifts,
///   because the animation pans as it zooms.
///
/// The preview applies effects to the un-zoomed source and lets the scroll view
/// magnify the result, so it passes `.identity` and gets image-space behaviour for free.
public struct FrameGeometry {
    /// Zoom baked into the frame.
    public var scale: CGFloat

    /// Where the source image's origin sits within the frame, in frame pixels, in
    /// CIImage coordinates (bottom-left origin). Only its value modulo the grid's cell
    /// size matters, so effects can take a remainder rather than worrying about
    /// absolute position.
    public var contentOrigin: CGPoint

    /// Where the source photo actually lands in the frame — its full rect in frame pixels,
    /// CIImage coordinates (bottom-left origin), after both the aspect-fill and the zoom.
    ///
    /// **Distinct from `contentOrigin`, and not redundant with it.** `contentOrigin` is a
    /// *phase* for grid effects, which only ever read it modulo a cell size; it is computed
    /// from the content's top edge, and being a whole content-height out makes no difference
    /// to a remainder. Placing a source-space image needs a real position and a real size, so
    /// it needs this instead. An earlier version of this field was a bare scale factor paired
    /// with `contentOrigin`, which put the subject mask a full frame-height off in the GIF —
    /// the cutout was invisible in the export while working in the preview, because the
    /// preview passes `.identity` and never exercises the mapping.
    ///
    /// `.null` means source space and frame space coincide — the preview's case, where
    /// effects run on the un-zoomed source.
    public var contentRect: CGRect

    public init(scale: CGFloat = 1.0, contentOrigin: CGPoint = .zero, contentRect: CGRect = .null) {
        self.scale = scale
        self.contentOrigin = contentOrigin
        self.contentRect = contentRect
    }

    /// Transform mapping an image in source space onto the frame.
    ///
    /// Derived from the source image's own extent rather than a stored scale, so it stays
    /// correct even when the mask's pixel size differs from the photo the frame was drawn
    /// from — which happens whenever the pipeline normalises orientation before drawing.
    public func sourceToFrame(sourceExtent: CGRect) -> CGAffineTransform {
        guard !contentRect.isNull,
              sourceExtent.width > 0, sourceExtent.height > 0,
              contentRect.width > 0, contentRect.height > 0
        else { return .identity }

        let sx = contentRect.width / sourceExtent.width
        let sy = contentRect.height / sourceExtent.height
        return CGAffineTransform(translationX: -sourceExtent.minX, y: -sourceExtent.minY)
            .concatenating(CGAffineTransform(scaleX: sx, y: sy))
            .concatenating(CGAffineTransform(translationX: contentRect.minX, y: contentRect.minY))
    }

    /// Un-zoomed, un-panned — what the preview path uses.
    public static let identity = FrameGeometry()
}

/// A visual effect applied per-frame after the zoom/motion rendering pass.
/// Each effect transforms a CIImage → CIImage, building a lazy filter graph.
/// GIFGenerator chains all active effects then renders once per frame via CIContext.
///
/// `viewportCenter` allows the preview to pass the viewport center in image coordinates
/// so spatially-centered effects (fisheye, halftone) track the visible area.
/// In the GIF pipeline this is nil and effects default to the image center.
///
/// `geometry` describes the frame's relationship to the source image — see
/// `FrameGeometry`. Effects without a spatial grid can ignore it.
public protocol VisualEffect {
    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage
    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage
    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, geometry: FrameGeometry) -> CIImage
    /// The burst-aware entry point: `motion` carries the frames around this one, a mask per
    /// frame and the measured velocities (FEATURE-MOTION-EFFECTS.md). Nil for a still. Only
    /// effects that read motion implement it; the default drops `motion` and calls the
    /// geometry overload, so the shipped effects are byte-for-byte unchanged.
    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, geometry: FrameGeometry, motion: MotionContext?) -> CIImage
}

extension VisualEffect {
    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex)
    }

    /// Defaults to ignoring the frame geometry, so only effects whose output has a
    /// spatial grid need to opt in.
    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, geometry: FrameGeometry) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: viewportCenter)
    }

    /// Defaults to ignoring the motion, so only effects that read it need to opt in.
    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, geometry: FrameGeometry, motion: MotionContext?) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: viewportCenter, geometry: geometry)
    }
}
