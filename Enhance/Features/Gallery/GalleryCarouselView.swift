import SwiftUI

struct GalleryCarouselView: View {
    let gifURLs: [URL]
    let namespace: Namespace.ID
    let onTap: (Int) -> Void
    
    private let cardSize: CGFloat = 345
    private let cardSpacing: CGFloat = 16
    
    var body: some View {
        GeometryReader { outerGeo in
            let screenCenter = outerGeo.size.height / 2
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: cardSpacing) {
                    ForEach(0..<gifURLs.count, id: \.self) { index in
                        GeometryReader { cardGeo in
                            let cardCenter = cardGeo.frame(in: .global).midY
                            let distanceFromCenter = abs(cardCenter - screenCenter)
                            let maxDistance: CGFloat = outerGeo.size.height / 2
                            let normalizedDistance = min(distanceFromCenter / maxDistance, 1.0)
                            
                            let scale = 1.0 - (normalizedDistance * 0.13)
                            let opacity = 1.0 - (normalizedDistance * 0.3)
                            
                            CarouselCard(
                                url: gifURLs[index],
                                index: index,
                                namespace: namespace,
                                onTap: { onTap(index) }
                            )
                            .scaleEffect(scale)
                            .opacity(opacity)
                            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.86), value: normalizedDistance)
                        }
                        .frame(width: cardSize, height: cardSize)
                        .id(index)
                    }
                }
                .padding(.vertical, 56)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Carousel Card

private struct CarouselCard: View {
    let url: URL
    let index: Int
    let namespace: Namespace.ID
    let onTap: () -> Void
    
    @State private var isVisible = false
    @State private var thumbnail: UIImage?
    
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
            
            AnimatedGifViewWithLoading(
                url: url,
                contentMode: .scaleAspectFill,
                lowQuality: true,
                isVisible: isVisible
            )
            .opacity(isVisible ? 1 : 0)
            .matchedGeometryEffect(id: "gif\(index)", in: namespace)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: Color(white: 0.12, opacity: 0.15), radius: 22, x: 0, y: 22)
        .onTapGesture { onTap() }
        .onAppear {
            isVisible = true
            loadThumbnail()
        }
        .onDisappear { isVisible = false }
    }
    
    private func loadThumbnail() {
        if let cached = ThumbnailCache.shared.get(for: url) {
            thumbnail = cached
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = try? Data(contentsOf: url),
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }

            let scale = UIScreen.main.scale
            let maxPixel = 345 * scale
            let thumbOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary) else { return }

            let resized = UIImage(cgImage: cgImage)
            ThumbnailCache.shared.set(resized, for: url)
            
            DispatchQueue.main.async {
                if isVisible { thumbnail = resized }
            }
        }
    }
}
