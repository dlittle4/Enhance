import UIKit

/// Two-tier thumbnail cache: fast in-memory NSCache backed by on-disk JPEG files.
/// Disk thumbnails are stored alongside cached GIF files in Caches/MyGIFs/Thumbs/.
class ThumbnailCache {
    static let shared = ThumbnailCache()
    
    private let memoryCache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 100
        c.totalCostLimit = 50 * 1024 * 1024
        return c
    }()
    
    private let thumbsDir: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("MyGIFs/Thumbs", isDirectory: true)
    }()
    
    private let ioQueue = DispatchQueue(label: "com.enhance.thumbcache.io", qos: .utility)
    
    private init() {
        try? FileManager.default.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
    }
    
    func get(for url: URL) -> UIImage? {
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached
        }
        
        let diskPath = diskURL(for: url)
        if let data = try? Data(contentsOf: diskPath),
           let image = UIImage(data: data) {
            setMemory(image, for: url)
            return image
        }
        
        return nil
    }
    
    func set(_ image: UIImage, for url: URL) {
        setMemory(image, for: url)
        
        let diskPath = diskURL(for: url)
        ioQueue.async {
            if let data = image.jpegData(compressionQuality: 0.85) {
                try? data.write(to: diskPath, options: .atomic)
            }
        }
    }
    
    /// Remove disk thumbnails whose GIF URLs are no longer valid.
    func cleanupStaleFiles(keeping validURLs: [URL]) {
        let validNames = Set(validURLs.map { diskFilename(for: $0) })
        ioQueue.async { [thumbsDir] in
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: thumbsDir.path) else { return }
            for file in files where !validNames.contains(file) {
                try? FileManager.default.removeItem(at: thumbsDir.appendingPathComponent(file))
            }
        }
    }
    
    func clearCache() {
        memoryCache.removeAllObjects()
    }
    
    // MARK: - Private
    
    private func setMemory(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        memoryCache.setObject(image, forKey: url as NSURL, cost: cost)
    }
    
    private func diskURL(for gifURL: URL) -> URL {
        thumbsDir.appendingPathComponent(diskFilename(for: gifURL))
    }
    
    private func diskFilename(for gifURL: URL) -> String {
        let base = gifURL.deletingPathExtension().lastPathComponent
        return "\(base).thumb.jpg"
    }
}
