import SwiftUI

struct GIFPreviewView: View {
    let url: URL
    var isPlaying: Bool = true
    var playbackSpeed: Double = 1.0

    var body: some View {
        AnimatedGifViewWithLoading(
            url: url,
            contentMode: .scaleAspectFit,
            isVisible: isPlaying,
            playbackSpeed: playbackSpeed
        )
        .background(Color.black.opacity(0.03))
    }
}
