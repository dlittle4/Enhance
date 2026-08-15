import SwiftUI

/// What plays over the canvas while a GIF is being generated.
///
/// Driven by `TimelineView(.animation)` rather than a repeating `withAnimation`, because the
/// generation takes as long as it takes: there is no known end time to animate *to*, and a
/// `repeatForever` that has to be cancelled from the outside strands the shader mid-pass. Reading
/// the clock each frame means the loop is a pure function of time — it starts, stops and resumes
/// correctly no matter when generation finishes.
///
/// The uniforms are recomputed per frame here, so unlike the one-shot reveals this path needs no
/// `Animatable` conformance to produce intermediate frames.
struct GeneratingAnimationView: View {
    let image: UIImage?
    let style: GeneratingStyle
    let cellSize: Double
    let cycle: Double
    let side: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        if style.usesPixels, image != nil {
            TimelineView(.animation) { timeline in
                let period = max(0.1, cycle)
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let phase = elapsed.truncatingRemainder(dividingBy: period) / period
                // Wrapped small before it reaches the shader. `elapsed` is seconds since 2001
                // (~8e8), so a raw pass counter lands around 1e10 — and `seed` arrives in Metal
                // as a 32-bit float, where the spacing at that magnitude is larger than the
                // per-cell `dot()` term the hash adds it to. Every cell then hashes identically
                // and the picture flips in as one block instead of scattering. Measured, not
                // theorised: it rendered as a static, fully-built image.
                let pass = (elapsed / period).rounded(.down).truncatingRemainder(dividingBy: 53)

                switch style {
                case .build:
                    // A fresh scatter each pass, so repeated builds do not look like one
                    // looping clip.
                    PixelBuildOverlay(
                        image: image, progress: phase, cellSize: cellSize,
                        seed: pass * 37, side: side, cornerRadius: cornerRadius
                    )

                case .resolve:
                    PixelResolveOverlay(
                        image: image, progress: phase, cellSize: cellSize,
                        side: side, cornerRadius: cornerRadius
                    )

                case .scramble:
                    // Held at a partial reveal with the scatter re-rolled four times a cycle:
                    // the same blocks never land twice, so the image reads as unresolved work
                    // rather than as an arrival that keeps restarting.
                    // Wrapped for the same reason as `pass` above.
                    let segment = (elapsed / (period / 4)).rounded(.down)
                        .truncatingRemainder(dividingBy: 71)
                    PixelBuildOverlay(
                        image: image, progress: 0.6, cellSize: cellSize,
                        seed: segment * 13, side: side, cornerRadius: cornerRadius
                    )

                case .spinner:
                    EmptyView()
                }
            }
        }
    }
}

/// The photo assembling itself out of blocks once, as the editor opens.
///
/// A one-shot sibling of `GeneratingAnimationView`, on the same clock-driven footing and for the
/// same reason — plus it removes itself when it completes, handing the canvas back to the real,
/// interactive `ImageCanvasView` underneath.
struct CanvasBuildInView: View {
    let image: UIImage?
    let cellSize: Double
    let duration: Double
    let side: CGFloat
    let cornerRadius: CGFloat

    @State private var start: Date?
    @State private var finished = false
    @State private var seed = Double.random(in: 0..<1000)

    var body: some View {
        if !finished, image != nil {
            TimelineView(.animation) { timeline in
                let began = start ?? timeline.date
                let progress = min(1, timeline.date.timeIntervalSince(began) / max(0.05, duration))
                PixelBuildOverlay(
                    image: image, progress: progress, cellSize: cellSize,
                    seed: seed, side: side, cornerRadius: cornerRadius
                )
            }
            .onAppear {
                start = Date()
                seed = Double.random(in: 0..<1000)
                // Ended by the clock rather than by the timeline reaching 1, so an interruption
                // cannot strand the canvas behind a half-built overlay.
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, duration)) {
                    finished = true
                }
            }
        }
    }
}
