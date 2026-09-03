import CoreGraphics

/// Where the lazers are pointed.
///
/// A point in **normalized image space with a bottom-left origin** — the same space as
/// `DetectedFace.normalizedBoundingBox` and every `CIImage` the effect draws into. Normalized
/// rather than pixels because the same target has to land on three differently-sized copies of
/// the photo (the 650px preview, the pre-shrunk GIF source, the full-size original), and a
/// fraction of the extent survives all of them without a `scaled` step that each caller would
/// have to remember.
///
/// Stored as its own type rather than a bare `CGPoint?` so the coordinate convention has a name
/// to hang on, and so the canvas→image conversion lives beside the thing it produces.
struct LaserAim: Equatable {
    /// 0…1 across the image, left to right.
    var x: CGFloat
    /// 0…1 up the image, **bottom to top** (Core Image's convention, not UIKit's).
    var y: CGFloat

    init(x: CGFloat, y: CGFloat) {
        self.x = max(0, min(1, x))
        self.y = max(0, min(1, y))
    }

    /// Converts a touch in the canvas image view's own coordinates (UIKit, top-left origin,
    /// `bounds`-sized regardless of zoom) into a target. Pure so the flip is testable without a
    /// touch harness — a y-flip is exactly the kind of bug that renders fine on a centred face
    /// and only shows up when someone aims at the top of the photo.
    static func from(canvasPoint point: CGPoint, in bounds: CGSize) -> LaserAim? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        return LaserAim(x: point.x / bounds.width, y: 1 - point.y / bounds.height)
    }

    /// The target in a particular image's pixel space.
    func point(in extent: CGRect) -> CGPoint {
        CGPoint(x: extent.minX + x * extent.width, y: extent.minY + y * extent.height)
    }
}
