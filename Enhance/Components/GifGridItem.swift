import SwiftUI

// Grid item for GIFs
struct GifGridItem: View {
    let url: URL
    let index: Int
    let namespace: Namespace.ID
    let onTap: () -> Void
    var isSelected: Bool = false
    var autoPlay: Bool = true
    var onLongPress: (() -> Void)? = nil
    @State private var isVisible: Bool = false
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            AnimatedGifViewWithLoading(url: url, contentMode: .scaleAspectFill, lowQuality: true, isVisible: isVisible && autoPlay)
                 .opacity(isVisible && autoPlay ? 1 : 0)
                 .matchedGeometryEffect(id: "gif\(index)", in: namespace)
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(hex: 0x60FFA8), lineWidth: 4)
                .opacity(isSelected ? 1 : 0)
        )
        .shadow(color: Color(white: 0.12, opacity: 0.15), radius: 22, x: 0, y: 22)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture {
            onLongPress?()
        }
        .onAppear {
            isVisible = true
            loadThumbnail() // Load thumbnail when appearing
        }
        .onDisappear {
            isVisible = false
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
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary) else {
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
