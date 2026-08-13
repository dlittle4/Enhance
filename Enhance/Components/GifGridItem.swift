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
    @State private var isVisible: Bool = false
    @State private var thumbnail: UIImage? = nil
    @State private var longPressTriggered: Bool = false

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
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                AnimatedGifViewWithLoading(url: url, contentMode: .scaleAspectFill, lowQuality: lowQuality, isVisible: isVisible && autoPlay)
                     .opacity(isVisible && autoPlay ? 1 : 0)
                     .matchedGeometryEffect(id: "gif\(index)", in: namespace)
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
        }
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
