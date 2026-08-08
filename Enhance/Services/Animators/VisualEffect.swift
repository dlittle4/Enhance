import CoreImage

/// A visual effect applied per-frame after the zoom/motion rendering pass.
/// Each effect transforms a CIImage → CIImage, building a lazy filter graph.
/// GIFGenerator chains all active effects then renders once per frame via CIContext.
///
/// `viewportCenter` allows the preview to pass the viewport center in image coordinates
/// so spatially-centered effects (fisheye, halftone) track the visible area.
/// In the GIF pipeline this is nil and effects default to the image center.
///
/// `frameScale` is the zoom factor baked into the frame the effect is handed, and it
/// exists because the preview and the GIF work in different spaces. The GIF pipeline
/// applies effects *after* the zoom transform, so a pattern measured in output pixels
/// stays a fixed size while the image scales beneath it — it reads as a static overlay
/// pasted on top. The preview applies effects to the un-zoomed source and lets the
/// scroll view magnify the result, so there the same pattern is locked to the image.
/// Effects with their own spatial frequency (dither cells, halftone screens) multiply
/// it by `frameScale` so both paths agree. Non-spatial effects can ignore it.
public protocol VisualEffect {
    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage
    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage
    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, frameScale: CGFloat) -> CIImage
}

extension VisualEffect {
    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex)
    }

    /// Defaults to ignoring the frame scale, so only effects whose output has a
    /// spatial frequency need to opt in.
    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, frameScale: CGFloat) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: viewportCenter)
    }
}
