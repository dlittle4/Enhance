import CoreImage

/// A visual effect applied per-frame after the zoom/motion rendering pass.
/// Each effect transforms a CIImage → CIImage, building a lazy filter graph.
/// GIFGenerator chains all active effects then renders once per frame via CIContext.
///
/// `viewportCenter` allows the preview to pass the viewport center in image coordinates
/// so spatially-centered effects (fisheye, halftone) track the visible area.
/// In the GIF pipeline this is nil and effects default to the image center.
public protocol VisualEffect {
    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage
    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage
}

extension VisualEffect {
    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex)
    }
}
