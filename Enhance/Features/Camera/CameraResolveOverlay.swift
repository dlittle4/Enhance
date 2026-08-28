import SwiftUI

/// The camera feed's arrival, drawn as the ENHANCE treatment: the live frames held coarsely
/// pixelated and swept to sharp as the viewfinder settles.
///
/// An overlay over the real preview for the reason `PixelBuildOverlay` spells out — the feed
/// is an `AVCaptureVideoPreviewLayer` inside a `UIViewRepresentable`, and SwiftUI's Metal
/// renderer cannot sample UIKit-backed content. So the frames come in as `CGImage`s from the
/// service's video tap, are drawn as a plain SwiftUI `Image` this shader *can* sample, and
/// the parent removes the overlay to hand off to the live layer beneath.
///
/// Clock-driven like `CanvasBuildInView`, so the `Pixellate` modifier stays non-`Animatable`
/// per the rule in `PixelBuildOverlay`: `Animatable` when a transaction drives the uniform,
/// plain when the clock does. The parent owns the ending — its own timer fades and unmounts
/// this view — because a `TimelineView` only draws, it cannot promise to finish.
struct CameraResolveOverlay: View {

    /// The latest live frame. `nil` — before the first frame lands — renders opaque black,
    /// which is exactly what the card shows behind a not-yet-running feed today.
    let frame: CGImage?

    /// Block edge in points at the start of the sweep.
    let cellSize: Double

    /// Seconds from fully coarse to sharp.
    let duration: Double

    /// False holds the coarse end (and pauses the timeline); flipping true starts the sweep.
    let running: Bool

    @State private var startDate: Date?

    var body: some View {
        TimelineView(.animation(paused: !running)) { timeline in
            GeometryReader { geo in
                ZStack {
                    Color.black
                    if let frame {
                        Image(decorative: frame, scale: 1)
                            .resizable()
                            // Matches the preview layer's `.resizeAspectFill`, so the sharp
                            // end of the sweep frames the scene the way the live layer does.
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .modifier(Pixellate(cellSize: resolvedCell(at: timeline.date)))
                    }
                }
            }
        }
        .onChange(of: running) { _, isRunning in
            if isRunning, startDate == nil { startDate = Date() }
        }
        .allowsHitTesting(false)
    }

    /// Same shape as `PixelResolveOverlay.resolvedCell`: the coarse end — where each step is
    /// a visible change — gets most of the time, and the visually indistinguishable last
    /// steps go by quickly.
    private func resolvedCell(at date: Date) -> Double {
        guard let startDate else { return cellSize }
        let progress = min(1, max(0, date.timeIntervalSince(startDate) / max(0.05, duration)))
        return max(1, cellSize * (1 - pow(progress, 0.45)))
    }
}
