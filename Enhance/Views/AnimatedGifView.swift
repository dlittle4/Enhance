import SwiftUI
import UIKit
import CoreGraphics
import ImageIO

// UIViewRepresentable for displaying animated GIFs
struct AnimatedGifView: UIViewRepresentable {
    let url: URL
    var contentMode: UIView.ContentMode = .scaleAspectFit
    
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
        
        // Start loading the GIF
        loadGIF(from: url, into: imageView)
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let imageView = uiView.subviews.first as? UIImageView {
            // Update content mode if it changed
            imageView.contentMode = contentMode
        }
    }
    
    private func loadGIF(from url: URL, into imageView: UIImageView) {
        DispatchQueue.global().async {
            if let data = try? Data(contentsOf: url),
               let source = CGImageSourceCreateWithData(data as CFData, nil) {
                
                let count = CGImageSourceGetCount(source)
                var images: [UIImage] = []
                var totalDuration: TimeInterval = 0
                
                for i in 0..<count {
                    if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                        // Get frame duration
                        let frameDuration = Self.frameDurationAtIndex(i, source: source)
                        totalDuration += frameDuration
                        
                        let image = UIImage(cgImage: cgImage)
                        images.append(image)
                    }
                }
                
                DispatchQueue.main.async {
                    if images.count == 1, let firstImage = images.first {
                        // Static image
                        imageView.image = firstImage
                    } else if !images.isEmpty {
                        // Animated image
                        imageView.animationImages = images
                        imageView.animationDuration = totalDuration
                        imageView.animationRepeatCount = 0 // 0 = infinite loop
                        imageView.startAnimating()
                    }
                }
            }
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
        var currentURL: URL?
    }
} 