import SwiftUI
import UIKit
import CoreGraphics
import ImageIO

// Simple GIF cache to avoid reloading the same GIFs
class GIFCache {
    static let shared = GIFCache()
    private var cache: NSCache<NSURL, NSArray> = {
        let c = NSCache<NSURL, NSArray>()
        c.countLimit = 50
        c.totalCostLimit = 100 * 1024 * 1024 // 100 MB
        return c
    }()
    
    func getImages(for url: URL) -> [UIImage]? {
        return cache.object(forKey: url as NSURL) as? [UIImage]
    }
    
    func setImages(_ images: [UIImage], for url: URL) {
        let perFrame = images.first.map { Int($0.size.width * $0.size.height * 4) } ?? 0
        let cost = perFrame * images.count
        cache.setObject(images as NSArray, forKey: url as NSURL, cost: cost)
    }
    
    func clear() {
        cache.removeAllObjects()
    }
}

// UIViewRepresentable for displaying animated GIFs with loading state
struct AnimatedGifView: UIViewRepresentable {
    let url: URL
    var contentMode: UIView.ContentMode = .scaleAspectFit
    var lowQuality: Bool = false
    var isVisible: Bool = true
    var playbackSpeed: Double = 1.0
    
    @State private var isLoading = true
    
    // UIViewRepresentable implementation
    func makeUIView(context: Context) -> UIView {
        // Create a simple container view
        let containerView = UIView()
        containerView.backgroundColor = .clear
        
        // Create a centered image view that takes the full size
        let imageView = UIImageView()
        imageView.contentMode = contentMode
        imageView.clipsToBounds = true
        
        // Add the image view to the container
        imageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(imageView)
        
        // Simple constraints to make the image view fill the container
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        context.coordinator.currentURL = url
        loadGIF(from: url, into: imageView, context: context)
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let imageView = uiView.subviews.first as? UIImageView {
            imageView.contentMode = contentMode
            
            if context.coordinator.currentURL != url {
                context.coordinator.currentURL = url
                imageView.stopAnimating()
                imageView.animationImages = nil
                imageView.image = nil
                loadGIF(from: url, into: imageView, context: context)
                return
            }
            
            if let baseDuration = context.coordinator.baseDuration {
                imageView.animationDuration = baseDuration
            }
            
            if isVisible && !imageView.isAnimating && imageView.animationImages != nil {
                imageView.startAnimating()
            } else if !isVisible && imageView.isAnimating {
                imageView.stopAnimating()
            }
        }
    }
    
    private func loadGIF(from url: URL, into imageView: UIImageView, context: Context) {
        // Set loading state to true
        DispatchQueue.main.async {
            context.coordinator.isLoading = true
        }
        
        if let cachedImages = GIFCache.shared.getImages(for: url) {
            let baseDuration = Double(cachedImages.count) * 0.1
            context.coordinator.baseDuration = baseDuration
            context.coordinator.isLoading = false

            imageView.animationImages = cachedImages
            imageView.animationDuration = baseDuration
            imageView.animationRepeatCount = 0
            imageView.startAnimating()
            return
        }
        
        DispatchQueue.global().async {
            do {
                let data = try Data(contentsOf: url)
                
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                    print("Error: Could not create image source from data for URL: \(url.lastPathComponent)")
                    setPlaceholder(for: imageView)
                    return
                }
                
                let count = CGImageSourceGetCount(source)
                
                if count == 0 {
                    print("Error: No frames found in GIF at URL: \(url.lastPathComponent)")
                    setPlaceholder(for: imageView)
                    return
                }
                
                var images: [UIImage] = []
                var totalDuration: TimeInterval = 0
                
                // Create downsampling options for lower quality if needed
                let options: [CFString: Any]? = lowQuality ? [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 200, // Smaller thumbnail size
                    kCGImageSourceShouldCacheImmediately: false // Don't cache immediately to reduce memory
                ] : nil
                
                // For low quality mode, we'll also skip frames to improve performance
                let frameSkip = lowQuality ? max(1, count / 15) : 1 // Skip frames for performance in gallery view
                
                for i in stride(from: 0, to: count, by: frameSkip) {
                    // Use the downsampling options if in low quality mode
                    let cgImage: CGImage?
                    if lowQuality {
                        cgImage = CGImageSourceCreateThumbnailAtIndex(source, i, options as CFDictionary?)
                    } else {
                        cgImage = CGImageSourceCreateImageAtIndex(source, i, nil)
                    }
                    
                    if let cgImage = cgImage {
                        // Get frame duration
                        let frameDuration = Self.frameDurationAtIndex(i, source: source) * Double(frameSkip)
                        totalDuration += frameDuration
                        
                        let image = UIImage(cgImage: cgImage)
                        images.append(image)
                    }
                }
                
                DispatchQueue.main.async {
                    if images.count == 1, let firstImage = images.first {
                        imageView.image = firstImage
                    } else if !images.isEmpty {
                        GIFCache.shared.setImages(images, for: url)
                        
                        context.coordinator.baseDuration = totalDuration
                        
                        imageView.animationImages = images
                        imageView.animationDuration = totalDuration
                        imageView.animationRepeatCount = 0
                        imageView.startAnimating()
                    } else {
                        setPlaceholder(for: imageView)
                    }
                    
                    context.coordinator.isLoading = false
                }
            } catch {
                print("Error loading GIF data for \(url.lastPathComponent): \(error.localizedDescription)")
                setPlaceholder(for: imageView)
            }
        }
    }
    
    private func setPlaceholder(for imageView: UIImageView) {
        DispatchQueue.main.async {
            // Set a placeholder for failed GIFs
            imageView.image = UIImage(systemName: "photo")
            imageView.tintColor = .gray
        }
    }
    
    static func frameDurationAtIndex(_ index: Int, source: CGImageSource) -> TimeInterval {
        var frameDuration: TimeInterval = 0.1 // Default duration
        
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
           let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
            
            // Get the unclamped delay time
            if let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime as String] as? TimeInterval,
               unclampedDelay > 0 {
                frameDuration = unclampedDelay
            } else if let delay = gifProperties[kCGImagePropertyGIFDelayTime as String] as? TimeInterval,
                      delay > 0 {
                frameDuration = delay
            }
        }
        
        // Check for too small duration that would make animation too fast
        if frameDuration < 0.02 {
            frameDuration = 0.1
        }
        
        return frameDuration
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var isLoading = true
        var baseDuration: Double?
        var currentURL: URL?
    }
}

struct AnimatedGifViewWithLoading: View {
    let url: URL
    var contentMode: UIView.ContentMode = .scaleAspectFit
    var lowQuality: Bool = false
    var isVisible: Bool = true
    var playbackSpeed: Double = 1.0
    
    var body: some View {
        AnimatedGifView(url: url, contentMode: contentMode, lowQuality: lowQuality, isVisible: isVisible, playbackSpeed: playbackSpeed)
    }
}

// Preview for AnimatedGifView
struct AnimatedGifView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Text("AnimatedGifView Preview")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.bottom, 10)
            
            // Note: This will show a placeholder in previews
            // since URL cannot be loaded in preview context
            AnimatedGifViewWithLoading(
                url: URL(string: "placeholder.gif")!, 
                contentMode: .scaleAspectFit
            )
            .frame(width: 300, height: 300)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
            
            Text("Note: Actual GIFs will only display in simulator or device")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.top, 10)
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
} 