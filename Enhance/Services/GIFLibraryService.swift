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
        
        ensureCacheDirectory()
        
        assets.enumerateObjects { [weak self] asset, index, _ in
            guard let self else { return }
            syncQueue.sync { idResults[index] = asset.localIdentifier }
            
            group.enter()
            imageManager.requestImage(
                for: asset, targetSize: thumbnailSize,
                contentMode: .aspectFill, options: imgOptions
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                if let image {
                    syncQueue.sync { gifResults[index] = image }
                }
                group.leave()
            }
            
            group.enter()
            self.stableGifURL(for: asset) { url in
                if let url {
                    syncQueue.sync { urlResults[index] = url }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            syncQueue.sync {
                let sortedIndices = Array(Set(gifResults.keys).intersection(urlResults.keys)).sorted()
                var localGifs: [UIImage] = []
                var localURLs: [URL] = []
                var localIDs: [String] = []
                
                for index in sortedIndices {
                    if let image = gifResults[index], let url = urlResults[index] {
                        localGifs.append(image)
                        localURLs.append(url)
                        if let id = idResults[index] { localIDs.append(id) }
                    }
                }
                
                self.myGifs = localGifs
                self.myGifURLs = localURLs
                self.myGifAssetIdentifiers = localIDs
            }
            self.hasLoaded = true
            self.isFetching = false
            self.cleanupStaleCacheFiles()
            ThumbnailCache.shared.cleanupStaleFiles(keeping: self.myGifURLs)
        }
    }
    
    // MARK: - Save
    
    func saveGifToAlbum(fileURL: URL, isAuthorized: Bool, requestAuth: @escaping (@escaping (Bool) -> Void) -> Void, completion: @escaping (Bool, Error?) -> Void) {
        guard isAuthorized else {
            requestAuth { [weak self] success in
                if success {
                    self?.saveGifToAlbum(fileURL: fileURL, isAuthorized: true, requestAuth: requestAuth, completion: completion)
                } else {
                    completion(false, NSError(domain: "PhotoLibraryNotAuthorized", code: 1))
                }
            }
            return
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            completion(false, NSError(domain: "FileNotFound", code: 2, userInfo: [NSLocalizedDescriptionKey: "The GIF file could not be found"]))
            return
        }
        
        if let album = PhotoLibraryService.fetchAlbumCollection(named: albumName) {
            saveGif(fileURL: fileURL, to: album, completion: completion)
        } else {
            createAlbum { [weak self] newAlbum in
                guard let self, let newAlbum else {
                    completion(false, NSError(domain: "AlbumCreationFailed", code: 3))
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
    
    private func saveGif(fileURL: URL, to album: PHAssetCollection, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: fileURL, options: PHAssetResourceCreationOptions())
            
            if let placeholder = request.placeholderForCreatedAsset,
               let albumChange = PHAssetCollectionChangeRequest(for: album) {
                albumChange.addAssets([placeholder] as NSArray)
            }
        }) { [weak self] success, error in
            DispatchQueue.main.async {
                if success { self?.fetchMyGifs() }
                completion(success, error)
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
            let options = PHContentEditingInputRequestOptions()
            options.canHandleAdjustmentData = { _ in true }

            asset.requestContentEditingInput(with: options) { [weak self] input, _ in
                if let url = input?.fullSizeImageURL {
                    do {
                        try FileManager.default.copyItem(at: url, to: stableURL)
                        completion(stableURL)
                    } catch {
                        completion(nil)
                    }
                } else {
                    self?.fallbackVideoURL(for: asset, destination: stableURL, completion: completion)
                }
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
    private func cleanupStaleCacheFiles() {
        let validFilenames = Set(myGifURLs.map { $0.lastPathComponent })
        let cacheDir = gifsCacheDir
        
        DispatchQueue.global(qos: .utility).async {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: cacheDir.path) else { return }
            for file in files where !validFilenames.contains(file) {
                try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent(file))
            }
        }
    }
}
