import SwiftUI

struct GIFPreviewView: View {
    let url: URL
    var isPlaying: Bool = true
    var playbackSpeed: Double = 1.0

    /// SCRUB THE PREVIEW, read here rather than threaded from the editor: this is the only GIF
    /// view that should scrub (gallery tiles must keep playing under a swipe), and the flag and
    /// its knobs republish through `@AppStorage` and the shared store with no plumbing.
    @AppStorage(FeatureFlags.scrubPreviewKey) private var scrubPreview = false
    @ObservedObject private var canvasStore = CanvasTuningStore.shared

    var body: some View {
        AnimatedGifViewWithLoading(
            url: url,
            contentMode: .scaleAspectFit,
            isVisible: isPlaying,
            playbackSpeed: playbackSpeed,
            isScrubInteractive: scrubPreview,
            scrubSpan: canvasStore.tuning.scrubSpan,
            scrubTickEvery: Int(canvasStore.tuning.scrubTickEvery.rounded())
        )
        .background(Color.black.opacity(0.03))
    }
}
