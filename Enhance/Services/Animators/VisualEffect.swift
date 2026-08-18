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

    /// How the source photo's *pixels* were scaled to fill the output frame, before any
    /// zoom. The GIF pipeline aspect-fills a photo of arbitrary size into a 600×600 frame,
    /// so this is that fill factor; `scale` is the zoom applied on top of it.
    ///
    /// Grid effects do not need this — a dither cell is defined in frame space and only has
    /// to track the zoom. It exists for effects carrying data computed in *source* space,
    /// where the full mapping matters: a subject mask from `SubjectSegmentationService` is
    /// the size of the photo, and placing it on the frame needs `scale * contentScale` for
    /// size and `contentOrigin` for position. Getting only the zoom right leaves the cutout
    /// drifting off the subject as the frame pans — the same class of bug `contentOrigin`
    /// was added to prevent for grids.
    ///
    /// Defaults to 1, which is correct for the preview: it applies effects to the un-zoomed
    /// source, so source space and frame space are already the same.
    public var contentScale: CGFloat

    public init(scale: CGFloat = 1.0, contentOrigin: CGPoint = .zero, contentScale: CGFloat = 1.0) {
        self.scale = scale
        self.contentOrigin = contentOrigin
        self.contentScale = contentScale
    }

    /// The full source-pixel → frame-pixel transform. Source is in CIImage coordinates
    /// (bottom-left origin), matching `contentOrigin`.
    public var sourceToFrame: CGAffineTransform {
        let total = scale * contentScale
        return CGAffineTransform(scaleX: total, y: total)
            .concatenating(CGAffineTransform(translationX: contentOrigin.x, y: contentOrigin.y))
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
}
