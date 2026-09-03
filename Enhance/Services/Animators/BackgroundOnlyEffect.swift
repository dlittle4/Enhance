import CoreImage

/// Wraps any `VisualEffect` so it applies to the background only, holding the segmented
/// subject flat — the FACE CUTOUT idea from ROADMAP §2f.
///
/// An adapter rather than a new effect, and that is the whole point: it is a *multiplier* on
/// the fifteen effects that already ship, so it gains a new look per existing effect rather
/// than adding a sixteenth. Same shape as `FaceVisualEffect`, which adapts a `VisualEffect`
/// into a `FaceEffect` by masking it to a face.
///
/// **A `nil` mask degrades to the plain effect, not to nothing.** Per §1g the editor keeps the
/// cards live on a photo with no subject (following the face precedent), so the toggle being
/// on with no subject found has to mean "just run the effect" — the alternative is a card that
/// silently renders an unmodified photo and looks broken.
struct BackgroundOnlyEffect: VisualEffect {
    let wrapped: VisualEffect
    let mask: CIImage?

    private let compositor = SubjectMaskCompositor()

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex,
              viewportCenter: nil, geometry: .identity)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex,
              viewportCenter: viewportCenter, geometry: .identity)
    }

    func apply(
        to image: CIImage,
        progress: CGFloat,
        frameIndex: Int,
        viewportCenter: CGPoint?,
        geometry: FrameGeometry
    ) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex,
              viewportCenter: viewportCenter, geometry: geometry, motion: nil)
    }

    /// The wrapped effect gets the motion too — an adapter must not be the place a burst's
    /// context is silently dropped. The subject is held with the still's mask, or for a burst
    /// with this frame's own when the context has one.
    func apply(
        to image: CIImage,
        progress: CGFloat,
        frameIndex: Int,
        viewportCenter: CGPoint?,
        geometry: FrameGeometry,
        motion: MotionContext?
    ) -> CIImage {
        let frameMask = motion?.mask ?? mask
        let treated = wrapped.apply(
            to: image, progress: progress, frameIndex: frameIndex,
            viewportCenter: viewportCenter, geometry: geometry, motion: motion
        )
        guard frameMask != nil else { return treated }
        return compositor.subject(of: image, over: treated, mask: frameMask, geometry: geometry)
    }
}
