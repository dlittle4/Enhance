import SwiftUI

/// The photo drawn as pixel blocks, over black — the canvas-sized sibling of the gallery's
/// save reveal.
///
/// **An overlay rather than an effect on the canvas, and that is forced.** `ImageCanvasView` is a
/// `UIViewRepresentable` around a `UIScrollView`, and SwiftUI's Metal renderer cannot sample
/// UIKit-backed content — a `layerEffect` applied there compiles, runs, and does nothing, exactly
/// as `GifGridItem` records for `AnimatedGifViewWithLoading`. So the effect is applied to a plain
/// SwiftUI `Image` of the same photo, laid over the canvas and removed when it finishes.
///
/// Opaque, so the sharp canvas underneath cannot show through the gaps between landed blocks —
/// without the black backdrop the "unbuilt" areas would show the finished photo and there would be
/// nothing to build.
struct PixelBuildOverlay: View {

    /// What to build. `nil` renders nothing, so a caller with no photo yet — an existing GIF
    /// whose source is still being extracted — costs nothing and shows no empty black square.
    let image: UIImage?

    /// 0 is empty, 1 is every block landed.
    let progress: Double

    /// Block edge in points.
    let cellSize: Double

    /// Which scatter the blocks land in. Re-rolled per pass by the looping styles.
    let seed: Double

    let side: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        if let image {
            ZStack {
                Color.black
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipped()
                    .modifier(PixelReveal(progress: progress, cellSize: cellSize, seed: seed))
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)
        }
    }
}

/// The photo held at a coarse block size that sharpens as `progress` rises — the app's own name
/// as a loading state.
///
/// Shares `Pixellate.metal` with the PIXELATE visual effect rather than adding a second
/// mosaic kernel. Same overlay reasoning as `PixelBuildOverlay`: the canvas cannot be sampled,
/// so this draws its own copy of the photo.
struct PixelResolveOverlay: View {
    let image: UIImage?

    /// 0 is fully coarse, 1 is a single-pixel cell — i.e. the sharp photo.
    let progress: Double

    /// The block edge at progress 0, in points.
    let cellSize: Double

    let side: CGFloat
    let cornerRadius: CGFloat

    /// Eased so the coarse end — where each step is a visible change — gets most of the time,
    /// and the last, visually indistinguishable steps go by quickly.
    private var resolvedCell: Double {
        let eased = pow(max(0, min(1, progress)), 0.45)
        return max(1, cellSize * (1 - eased))
    }

    var body: some View {
        if let image {
            ZStack {
                Color.black
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipped()
                    .modifier(Pixellate(cellSize: resolvedCell))
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Shader modifiers

/// `PixelReveal.metal` as a modifier.
///
/// **Deliberately not `Animatable`, unlike `GifGridItem`'s copy of this** — and the two are right
/// for opposite reasons. That one is driven by `withAnimation`, so it needs `animatableData` or
/// SwiftUI hands the shader the final value and draws no intermediate frame. These are driven by
/// `TimelineView`, which supplies a fresh value every frame; conforming here puts the animation
/// system in the path of a value that is already per-frame, and it settles on the final value
/// instead — measured as a build that renders complete and never moves.
///
/// The rule: `Animatable` when a *transaction* drives the uniform, plain when the *clock* does.
struct PixelReveal: ViewModifier {
    var progress: Double
    var cellSize: Double
    var seed: Double

    func body(content: Content) -> some View {
        content.layerEffect(
            ShaderLibrary.pixelReveal(
                .float(progress),
                .float(cellSize),
                .float(seed),
                .boundingRect
            ),
            // The shader reads each cell's centre, up to a cell away from the pixel being
            // shaded; `.zero` would let Metal clamp those reads and smear the edges.
            maxSampleOffset: CGSize(width: cellSize, height: cellSize)
        )
    }
}

/// `Pixellate.metal` as a modifier, so the cell size can be swept. Plain rather than `Animatable`
/// for the reason `PixelReveal` above spells out — the clock drives this, not a transaction.
struct Pixellate: ViewModifier {
    var cellSize: Double

    func body(content: Content) -> some View {
        GeometryReader { geo in
            content.layerEffect(
                ShaderLibrary.pixellate(
                    .float(max(1, cellSize)),
                    .float2(geo.size.width, geo.size.height)
                ),
                maxSampleOffset: CGSize(width: cellSize, height: cellSize)
            )
        }
    }
}
