import SwiftUI

/// Press-state style that scales down and dims the grid item on tap.
private struct GifGridItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// Grid item for GIFs
struct GifGridItem: View {
    let url: URL
    let index: Int
    let namespace: Namespace.ID
    let onTap: () -> Void
    var isSelected: Bool = false
    var autoPlay: Bool = true
    var lowQuality: Bool = true
    var onLongPress: (() -> Void)? = nil

    /// Set on the one cell that has just been saved, to play its arrival. `nil` on every other
    /// cell and at every other time.
    var reveal: RevealMotion? = nil

    /// Called when the reveal finishes, so the gallery can clear the pending identifier.
    var onRevealComplete: (() -> Void)? = nil

    /// False while the editor is showing this same GIF.
    ///
    /// The editor is an overlay, so the gallery stays in the hierarchy underneath it — and two
    /// live views claiming one `matchedGeometryEffect` id makes SwiftUI warn about multiple
    /// matching views and pick one arbitrarily, which breaks the zoom. Handing the source over to
    /// the editor for the duration is what keeps exactly one owner.
    var isMatchedGeometrySource: Bool = true

    /// What the pixel-dissolve needs to know.
    struct RevealMotion: Equatable {
        var cellSize: Double
        var duration: Double
        /// Seconds the empty placeholder box holds before the pixels start filling in — the
        /// beat that separates "a cell arrived" from "this is what's in it".
        var delay: Double = 0
    }

    @State private var isVisible: Bool = false
    @State private var thumbnail: UIImage? = nil
    @State private var longPressTriggered: Bool = false

    /// 0 while the cell is still building in, 1 once it has arrived.
    @State private var revealProgress: Double = 1

    /// True from the moment the reveal starts until its completion callback — the gate on the
    /// animated layer and the shader.
    ///
    /// **Deliberately not derived from `revealProgress`.** `withAnimation { revealProgress = 1 }`
    /// sets the *model* value to 1 instantly — only the presentation interpolates — so a
    /// `revealProgress < 1` check turns false the moment the animation is scheduled. Gated on
    /// that, the GIF layer's opacity flipped inside the same `withAnimation` and *faded in over
    /// the whole reveal*, covering the block build underneath. A plain Bool flipped at start and
    /// at completion is immune to the model-vs-presentation distinction.
    @State private var revealActive = false

    /// Stable per-cell scatter, so a re-render mid-reveal does not reshuffle which cells have
    /// already landed.
    @State private var revealSeed: Double = Double.random(in: 0..<1000)

    private var isRevealing: Bool { revealActive }

    var body: some View {
        Button {
            if longPressTriggered {
                longPressTriggered = false
                return
            }
            HapticService.light()
            onTap()
        } label: {
            ZStack {
                if let thumbnail = thumbnail {
                    // **The reveal runs on this still image, not on the animated layer below.**
                    // `AnimatedGifViewWithLoading` is a `UIViewRepresentable` around a
                    // `UIImageView`, and SwiftUI's Metal renderer cannot sample UIKit-backed
                    // content — a `layerEffect` there compiles, runs, and does nothing. Building
                    // in a settled frame and then starting the motion also reads better than
                    // dissolving a moving target.
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .modifier(PixelRevealModifier(
                            progress: revealProgress,
                            cellSize: reveal?.cellSize ?? 0,
                            seed: revealSeed,
                            isActive: isRevealing
                        ))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                AnimatedGifViewWithLoading(url: url, contentMode: .scaleAspectFill, lowQuality: lowQuality, isVisible: isVisible && autoPlay)
                     // Held back until the still image has finished assembling, so the two never
                     // show at once and the GIF appears to start the moment the cell completes.
                     .opacity(isVisible && autoPlay && !isRevealing ? 1 : 0)
                     .matchedGeometryEffect(id: "gif\(index)", in: namespace, isSource: isMatchedGeometrySource)
            }
            .aspectRatio(1, contentMode: .fit)
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous)
                    .strokeBorder(Color.enhanceMint, lineWidth: 4)
                    .opacity(isSelected ? 1 : 0)
            )
            .shadow(color: Color.shadow, radius: 22, x: 0, y: 22)
            .contentShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
        }
        .buttonStyle(GifGridItemButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    longPressTriggered = true
                    HapticService.medium()
                    onLongPress?()
                }
        )
        .onAppear {
            isVisible = true
            loadThumbnail()
            startRevealIfReady()
        }
        // The reveal waits for the thumbnail, which generates asynchronously: a cell that is
        // still a spinner has nothing to build in, and starting anyway would burn the animation
        // on an empty square. Both triggers call the same guarded entry point, so whichever
        // arrives last is the one that starts it.
        .onChange(of: thumbnail == nil) { _, _ in startRevealIfReady() }
        .onChange(of: reveal) { _, _ in startRevealIfReady() }
        .onDisappear {
            isVisible = false
        }
        .onChange(of: url) { _, _ in
            thumbnail = nil
            loadThumbnail()
        }
        // Use visibility detector to potentially trigger thumbnail load
        // if it wasn't loaded on initial appear for some reason,
        // and manage the isVisible state accurately.
        .viewVisibilityDetector { isInView in
            if self.isVisible != isInView {
                self.isVisible = isInView
                // Load thumbnail if becoming visible and it hasn't been loaded yet
                if isInView && self.thumbnail == nil {
                    loadThumbnail()
                }
            }
        }
    }

    /// Plays the arrival, once, and only when there is something to reveal.
    ///
    /// Idempotent by design: it is called from `onAppear` and from both of the things it waits on,
    /// because either can be the last to arrive. `revealActive` is the "already running" marker.
    private func startRevealIfReady() {
        guard let reveal, thumbnail != nil, !revealActive else { return }

        // A reduced-motion user gets the cell, not a dissolve. Cleared immediately so the gallery
        // does not keep waiting for an animation that will never run.
        guard !UIAccessibility.isReduceMotionEnabled else {
            onRevealComplete?()
            return
        }

        revealSeed = Double.random(in: 0..<1000)
        revealActive = true
        revealProgress = 0
        // The delay is the placeholder phase: the box sits empty while it elapses, then the
        // blocks assemble over `duration`.
        withAnimation(.easeOut(duration: reveal.duration).delay(reveal.delay)) {
            revealProgress = 1
        }
        // Ended by the clock rather than left to the animation, so an interruption —
        // backgrounding, entering select mode, a second save — can never strand a cell
        // part-built. Flipping `revealActive` here is also what swaps the finished mosaic for
        // the sharp, playing GIF.
        DispatchQueue.main.asyncAfter(deadline: .now() + reveal.delay + reveal.duration) {
            revealProgress = 1
            revealActive = false
            onRevealComplete?()
        }
    }

    // Function to load or generate the thumbnail
    private func loadThumbnail() {
        // 1. Check cache first
        if let cachedThumbnail = ThumbnailCache.shared.get(for: url) {
            // Ensure update happens on the main thread
            DispatchQueue.main.async {
                self.thumbnail = cachedThumbnail
            }
            return // Found in cache, no need to generate
        }

        // 2. If not in cache, generate it in the background
        generateAndCacheThumbnail()
    }

    private func generateAndCacheThumbnail() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = try? Data(contentsOf: url),
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                print("Error generating thumbnail for \(url)")
                return
            }

            let scale = UIScreen.main.scale
            let maxPixel = 114 * scale
            let thumbOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceShouldCacheImmediately: true
            ]
            let lastFrameIndex = max(CGImageSourceGetCount(source) - 1, 0)
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, lastFrameIndex, thumbOpts as CFDictionary) else {
                print("Error generating thumbnail for \(url)")
                return
            }

            let generatedThumbnail = UIImage(cgImage: cgImage)

            // Cache the generated thumbnail
            ThumbnailCache.shared.set(generatedThumbnail, for: url)

            // Update the state on the main thread
            DispatchQueue.main.async {
                // Check isVisible again to avoid updating if it disappeared quickly
                // Also check thumbnail is still nil in case it loaded concurrently
                if self.isVisible && self.thumbnail == nil {
                    self.thumbnail = generatedThumbnail
                }
            }
        }
    }

}

/// Applies `PixelReveal.metal` while a cell is building in, and gets out of the way once it has.
///
/// A `ViewModifier` with an `isActive` gate rather than a conditional at the call site: a
/// `layerEffect` that comes and goes changes the view's identity and can drop the very animation
/// it is meant to render. This way the modifier is always in the tree and only its contents change.
///
/// **`Animatable` is load-bearing, not decoration.** A shader uniform is not animatable on its
/// own: without `animatableData`, `withAnimation { revealProgress = 1 }` hands the shader 1 on
/// the next render and the whole image pops in at once — the per-cell build never draws a single
/// intermediate frame. Conforming is what makes SwiftUI call this modifier per frame with
/// interpolated progress values for the shader to consume.
private struct PixelRevealModifier: ViewModifier, Animatable {
    var progress: Double
    let cellSize: Double
    let seed: Double
    let isActive: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        if isActive {
            content.layerEffect(
                ShaderLibrary.pixelReveal(
                    .float(progress),
                    .float(cellSize),
                    .float(seed),
                    .boundingRect
                ),
                // The shader samples each cell's *centre*, which can sit up to a cell away from
                // the pixel being shaded. `.zero` would let Metal clamp those reads and smear
                // the edges.
                maxSampleOffset: CGSize(width: cellSize, height: cellSize)
            )
        } else {
            content
        }
    }
}
