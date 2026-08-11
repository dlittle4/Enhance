import UIKit
import Photos
import AVFoundation

class GIFLibraryService {
    @Published var myGifs: [UIImage] = []
    @Published var myGifURLs: [URL] = []
    @Published var myGifAssetIdentifiers: [String] = []
    @Published var hasLoaded = false
    
    private let albumName = "My GIFs"
    private var pendingWorkItem: DispatchWorkItem?
    private var isFetching = false

    /// Ceiling on a single fetch. Generous enough for a cold iCloud download of a
    /// full album, short enough that a wedged request self-clears within one session.
    private static let fetchTimeout: DispatchTimeInterval = .seconds(30)
    
    private var gifsCacheDir: URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cacheDir.appendingPathComponent("MyGIFs", isDirectory: true)
    }
    
    // MARK: - Fetch (single entry point, coalesced & cancellation-safe)
    
    func fetchMyGifs() {
        pendingWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performFetch()
        }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }
    
    /// Legacy alias kept for callers that expect a full clear + reload.
    func forceRefreshGifs() {
        fetchMyGifs()
    }
    
    private func performFetch() {
        guard !isFetching else { return }
        isFetching = true
        
        guard let album = PhotoLibraryService.fetchAlbumCollection(named: albumName) else {
            DispatchQueue.main.async { [weak self] in self?.hasLoaded = true }
            isFetching = false
            return
        }
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(in: album, options: fetchOptions)
        
        guard assets.count > 0 else {
            DispatchQueue.main.async { [weak self] in
                self?.myGifs = []
                self?.myGifURLs = []
                self?.myGifAssetIdentifiers = []
                self?.hasLoaded = true
                self?.isFetching = false
            }
            return
        }
        
        let imageManager = PHImageManager.default()
        let scale = UIScreen.main.scale
        let thumbnailSize = CGSize(width: 156 * scale, height: 156 * scale)
        let imgOptions = PHImageRequestOptions()
        imgOptions.isSynchronous = false
        imgOptions.deliveryMode = .highQualityFormat
        imgOptions.isNetworkAccessAllowed = true
        
        let syncQueue = DispatchQueue(label: "com.enhance.gifFetch.sync")
        var gifResults: [Int: UIImage] = [:]
        var urlResults: [Int: URL] = [:]
        var idResults: [Int: String] = [:]
        let group = DispatchGroup()
        let expectedCount = assets.count

        ensureCacheDirectory()

        assets.enumerateObjects { [weak self] asset, index, _ in
            guard let self else { return }
            syncQueue.sync { idResults[index] = asset.localIdentifier }

            // A degraded delivery is skipped so only the final high-quality image
            // counts, but PHImageManager gives no guarantee that a final delivery
            // ever arrives. LeaveGuard makes the balancing leave idempotent so a
            // repeated or missing callback can never over- or under-balance the group.
            let thumbToken = LeaveGuard(group)
            imageManager.requestImage(
                for: asset, targetSize: thumbnailSize,
                contentMode: .aspectFill, options: imgOptions
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                if let image {
                    syncQueue.sync { gifResults[index] = image }
                }
                thumbToken.leave()
            }

            let urlToken = LeaveGuard(group)
            self.stableGifURL(for: asset) { url in
                if let url {
                    syncQueue.sync { urlResults[index] = url }
                }
                urlToken.leave()
            }
        }

        // Wait with a ceiling rather than group.notify: an iCloud download that
        // stalls forever must not leave isFetching pinned true, which would make
        // every later refresh a silent no-op for the rest of the session.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let waitResult = group.wait(timeout: .now() + Self.fetchTimeout)

            var localGifs: [UIImage] = []
            var localURLs: [URL] = []
            var localIDs: [String] = []

            syncQueue.sync {
                let sortedIndices = Array(Set(gifResults.keys).intersection(urlResults.keys)).sorted()
                for index in sortedIndices {
                    if let image = gifResults[index], let url = urlResults[index] {
                        localGifs.append(image)
                        localURLs.append(url)
                        if let id = idResults[index] { localIDs.append(id) }
                    }
                }
            }

            // Only a complete, untimed-out fetch is trusted to describe the full set
            // of valid cache files. Sweeping after a partial fetch deletes cached GIFs
            // for assets that merely failed to resolve this time round, turning a
            // transient network failure into permanent cache loss.
            let isComplete = (waitResult == .success) && (localURLs.count == expectedCount)

            DispatchQueue.main.async {
                guard let self else { return }
                self.myGifs = localGifs
                self.myGifURLs = localURLs
                self.myGifAssetIdentifiers = localIDs
                self.hasLoaded = true
                self.isFetching = false

                if isComplete {
                    self.cleanupStaleCacheFiles()
                    ThumbnailCache.shared.cleanupStaleFiles(keeping: localURLs)
                }
            }
        }
    }
    
    // MARK: - Save
    
    func saveGifToAlbum(fileURL: URL, isAuthorized: Bool, requestAuth: @escaping (@escaping (Bool) -> Void) -> Void, completion: @escaping (Bool, String?, Error?) -> Void) {
        guard isAuthorized else {
            requestAuth { [weak self] success in
                if success {
                    self?.saveGifToAlbum(fileURL: fileURL, isAuthorized: true, requestAuth: requestAuth, completion: completion)
                } else {
                    completion(false, nil, NSError(domain: "PhotoLibraryNotAuthorized", code: 1))
                }
            }
            return
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            completion(false, nil, NSError(domain: "FileNotFound", code: 2, userInfo: [NSLocalizedDescriptionKey: "The GIF file could not be found"]))
            return
        }
        
        if let album = PhotoLibraryService.fetchAlbumCollection(named: albumName) {
            saveGif(fileURL: fileURL, to: album, completion: completion)
        } else {
            createAlbum { [weak self] newAlbum in
                guard let self, let newAlbum else {
                    completion(false, nil, NSError(domain: "AlbumCreationFailed", code: 3))
                    return
                }
                self.saveGif(fileURL: fileURL, to: newAlbum, completion: completion)
            }
        }
    }
    
    // MARK: - Delete
    
    func deleteAsset(identifier: String, completion: @escaping (Bool, Error?) -> Void) {
        deleteAssets(identifiers: [identifier], completion: completion)
    }
    
    func deleteAssets(identifiers: [String], completion: @escaping (Bool, Error?) -> Void) {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in assets.append(asset) }
        
        guard !assets.isEmpty else {
            completion(false, NSError(domain: "AssetNotFound", code: 4, userInfo: [NSLocalizedDescriptionKey: "No GIF assets found"]))
            return
        }
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }) { [weak self] success, error in
            if success { self?.fetchMyGifs() }
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }
    
    // MARK: - Private Helpers
    
    /// Saves the GIF and reports **which asset it created**.
    ///
    /// The identifier matters: per-GIF settings — zoom parameters, the text overlay — are stored
    /// against it. Before this returned one, a first-time save had no key to file them under, so
    /// reopening a freshly saved GIF lost its zoom framing and dropped its text entirely.
    ///
    /// `placeholderForCreatedAsset.localIdentifier` is valid to read immediately and becomes the
    /// real asset identifier once the change block commits — the same pattern `createAlbum`
    /// already uses for collections. Only meaningful when `success` is true.
    private func saveGif(fileURL: URL, to album: PHAssetCollection, completion: @escaping (Bool, String?, Error?) -> Void) {
        var createdIdentifier: String?

        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: fileURL, options: PHAssetResourceCreationOptions())

            if let placeholder = request.placeholderForCreatedAsset {
                createdIdentifier = placeholder.localIdentifier
                if let albumChange = PHAssetCollectionChangeRequest(for: album) {
                    albumChange.addAssets([placeholder] as NSArray)
                }
            }
        }) { [weak self] success, error in
            DispatchQueue.main.async {
                if success { self?.fetchMyGifs() }
                completion(success, success ? createdIdentifier : nil, error)
            }
        }
    }
    
    private func createAlbum(completion: @escaping (PHAssetCollection?) -> Void) {
        var placeholder: PHObjectPlaceholder?
        
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.albumName)
            placeholder = request.placeholderForCreatedAssetCollection
        }) { success, _ in
            guard success, let placeholder else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let result = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder.localIdentifier], options: nil)
            DispatchQueue.main.async { completion(result.firstObject) }
        }
    }
    
    /// Returns a stable cache file URL for the asset, reusing an existing copy if available.
    private func stableGifURL(for asset: PHAsset, completion: @escaping (URL?) -> Void) {
        let sanitizedId = asset.localIdentifier
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let isVideo = asset.mediaType == .video
        let ext = isVideo ? "mp4" : "gif"
        let stableURL = gifsCacheDir.appendingPathComponent("\(sanitizedId).\(ext)")

        // Remove stale cache files with the wrong extension
        let wrongExt = isVideo ? "gif" : "mp4"
        let staleURL = gifsCacheDir.appendingPathComponent("\(sanitizedId).\(wrongExt)")
        try? FileManager.default.removeItem(at: staleURL)

        // Also validate existing cached files: a .gif containing MP4 data (ftyp header) is stale
        if FileManager.default.fileExists(atPath: stableURL.path) {
            if ext == "gif", let handle = FileHandle(forReadingAtPath: stableURL.path) {
                let header = handle.readData(ofLength: 8)
                handle.closeFile()
                let isMp4 = header.count >= 8 && header[4] == 0x66 && header[5] == 0x74 && header[6] == 0x79 && header[7] == 0x70
                if isMp4 {
                    try? FileManager.default.removeItem(at: stableURL)
                } else {
                    completion(stableURL)
                    return
                }
            } else {
                completion(stableURL)
                return
            }
        }

        if isVideo {
            fallbackVideoURL(for: asset, destination: stableURL, completion: completion)
        } else {
            copyOriginalImageData(for: asset, destination: stableURL, completion: completion)
        }
    }

    /// Writes the asset's original image data — the animated GIF bytes — to `destination`.
    ///
    /// Network access is allowed because the system purges `Caches/` when storage is tight,
    /// preferentially for apps that haven't been used recently. That is exactly when the
    /// asset is also most likely to have been offloaded to iCloud, so the re-copy that
    /// repopulates the cache has to be able to pull it back down.
    private func copyOriginalImageData(for asset: PHAsset, destination: URL, completion: @escaping (URL?) -> Void) {
        let options = PHImageRequestOptions()
        options.version = .original
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            guard let data else {
                completion(nil)
                return
            }
            do {
                try data.write(to: destination, options: .atomic)
                completion(destination)
            } catch {
                completion(nil)
            }
        }
    }

    private func fallbackVideoURL(for asset: PHAsset, destination: URL, completion: @escaping (URL?) -> Void) {
        let videoOptions = PHVideoRequestOptions()
        videoOptions.version = .original
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: videoOptions) { avAsset, _, _ in
            if let urlAsset = avAsset as? AVURLAsset {
                do {
                    try FileManager.default.copyItem(at: urlAsset.url, to: destination)
                    DispatchQueue.main.async { completion(destination) }
                } catch {
                    DispatchQueue.main.async { completion(nil) }
                }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
    
    private func ensureCacheDirectory() {
        let path = gifsCacheDir.path
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(at: gifsCacheDir, withIntermediateDirectories: true)
        }
    }
    
    /// Removes cached GIF files that no longer correspond to assets in the album.
    /// Only safe to call after a fetch that resolved every asset — see `performFetch`.
    private func cleanupStaleCacheFiles() {
        let validFilenames = Set(myGifURLs.map { $0.lastPathComponent })
        guard !validFilenames.isEmpty else { return }
        let cacheDir = gifsCacheDir

        DispatchQueue.global(qos: .utility).async {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: cacheDir.path) else { return }
            for file in files where file != ThumbnailCache.directoryName && !validFilenames.contains(file) {
                try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent(file))
            }
        }
    }
}

// MARK: - LeaveGuard

/// Balances a single `DispatchGroup.enter()` with at most one `leave()`.
///
/// Photos callbacks are not guaranteed to fire exactly once — a request may deliver a
/// degraded image and then a final one, deliver nothing at all, or be cancelled. Routing
/// every leave through this type means a repeated callback cannot crash on an unbalanced
/// group, and a missing one cannot hang the fetch (the caller's timeout covers that).
final class LeaveGuard {
    private let group: DispatchGroup
    private let lock = NSLock()
    private var hasLeft = false

    init(_ group: DispatchGroup) {
        self.group = group
        group.enter()
    }

    func leave() {
        lock.lock()
        defer { lock.unlock() }
        guard !hasLeft else { return }
        hasLeft = true
        group.leave()
    }
}
