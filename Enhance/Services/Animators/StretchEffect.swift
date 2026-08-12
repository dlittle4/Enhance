import CoreImage
import CoreGraphics

/// STRETCH — pixels smeared along a line. The melted-scanline / pixel-sorting look.
///
/// The kernel is `Shaders/CI/Stretch.ci.metal`. Pixels near the line sample from their projection
/// onto it, so a whole perpendicular column reads one source point and draws a streak. Nothing is
/// blurred — the smear comes from collapsing a coordinate, which is why the streaks stay crisp.
///
/// - `intensity` is how completely pixels snap to the line.
/// - `angle` rotates the line through a half turn; past that it repeats.
/// - `position` slides the line across the frame without rotating it.
/// - `reach` is how far either side of the line the smear extends.
///
/// **Partly a grid effect.** There is no repeating cell, so there is no phase to align, but the
/// line is a feature *of the image* rather than of the frame: `reach` and `position` scale with
/// `FrameGeometry.scale`, and the line is anchored to `contentOrigin` so it stays over the same
/// part of the subject while the animation pans. Without that the streak slides across the photo.
struct StretchEffect: VisualEffect {
    private let strength: CGFloat
    private let angle: CGFloat
    private let position: CGFloat
    private let reach: CGFloat

    private static let kernel: CIKernel? = {
        guard let url = Bundle.main.url(forResource: "Stretch.ci", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CIKernel(functionName: "stretch", fromMetalLibraryData: data)
    }()

    init(intensity: Double = 0.5,
         angle: Double = 0.5,
         position: Double = 0.5,
         reach: Double = 0.5) {
        self.strength = CGFloat(max(0, min(1, intensity)))
        // Half a turn is the whole range: a line at θ and at θ+π are the same line, so mapping the
        // slider to a full turn would waste half of it repeating.
        self.angle = .pi * CGFloat(max(0, min(1, angle)))
        // Signed fraction of the frame's half-extent, so 0.5 sits the line on the centre.
        self.position = CGFloat(max(0, min(1, position))) - 0.5
        self.reach = CGFloat(max(0, min(1, reach)))
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil, geometry: .identity)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: viewportCenter, geometry: .identity)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, geometry: FrameGeometry) -> CIImage {
        // Quadratic ease-in: the smear arrives once the zoom has established the subject, rather
        // than being fully present on the first frame.
        let amount = strength * (progress * progress)
        guard amount > 0.01 else { return image }

        let extent = image.extent
        guard extent.width > 0, extent.height > 0, !extent.isInfinite else { return image }
        guard let kernel = Self.kernel else { return image }

        let zoom = max(1.0, geometry.scale)
        let half = min(extent.width, extent.height) * 0.5

        // A reach of zero would make the smoothstep degenerate and the effect vanish rather than
        // narrow, so the band keeps a floor.
        let reachPixels = max(2.0, half * (0.05 + 0.95 * reach)) * zoom
        let positionPixels = position * half * 2.0 * zoom

        let centre = viewportCenter ?? CGPoint(x: extent.midX, y: extent.midY)

        // Anchor the line to image content rather than to the frame. There is no cell size to take
        // a remainder against here, so this is the whole offset, not a modulus.
        let anchored = CGPoint(x: centre.x - geometry.contentOrigin.x,
                               y: centre.y - geometry.contentOrigin.y)

        let output = kernel.apply(
            extent: extent,
            roiCallback: { _, rect in
                // A pixel can sample from anywhere up to `reach` away along the line's normal, so
                // the region of interest has to widen by that much. Too tight gives black seams at
                // Core Image's tile boundaries — visible only on large images, never in a fixture.
                rect.insetBy(dx: -(reachPixels + 2), dy: -(reachPixels + 2))
            },
            arguments: [image,
                        CIVector(x: anchored.x, y: anchored.y),
                        angle, positionPixels, reachPixels, amount]
        )

        return output?.cropped(to: extent) ?? image
    }
}
