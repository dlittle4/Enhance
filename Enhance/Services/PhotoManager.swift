import SwiftUI
import Photos

/// Facade that composes PermissionManager and GIFLibraryService.
/// Photo browsing and selection is now handled by the native PhotosPicker.
class PhotoManager: NSObject, ObservableObject {
    
    private let permissions = PermissionManager()
    private let gifLibrary = GIFLibraryService()
    private var refreshDebounceWorkItem: DispatchWorkItem?
    
    @Published var myGifs: [UIImage] = []
    @Published var myGifURLs: [URL] = []
    @Published var myGifAssetIdentifiers: [String] = []
    @Published var hasLoadedGifs = false
    @Published var isAuthorized = false
    @Published var isDenied = false
    
    override init() {
        super.init()
        
        permissions.$isAuthorized.assign(to: &$isAuthorized)
        permissions.$isDenied.assign(to: &$isDenied)
        gifLibrary.$myGifs.assign(to: &$myGifs)
        gifLibrary.$myGifURLs.assign(to: &$myGifURLs)
        gifLibrary.$myGifAssetIdentifiers.assign(to: &$myGifAssetIdentifiers)
        gifLibrary.$hasLoaded.assign(to: &$hasLoadedGifs)
        
        PHPhotoLibrary.shared().register(self)
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    // MARK: - Public API
    
    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        permissions.requestAuthorization { [weak self] success in
            if success {
                self?.gifLibrary.fetchMyGifs()
            }
            completion?(success)
        }
    }
    
    func checkAuthorizationStatus() {
        permissions.checkStatus()
        if permissions.isAuthorized {
            gifLibrary.fetchMyGifs()
        }
    }
    
    func saveGifToMyGifsAlbum(fileURL: URL, completion: @escaping (Bool, Error?) -> Void) {
        gifLibrary.saveGifToAlbum(
            fileURL: fileURL,
            isAuthorized: permissions.isAuthorized,
            requestAuth: { [weak self] authCompletion in
                self?.permissions.requestAuthorization(completion: authCompletion)
            },
            completion: completion
        )
    }
    
    func forceRefreshGifs() {
        gifLibrary.forceRefreshGifs()
    }

    func deleteGifAsset(identifier: String, completion: @escaping (Bool, Error?) -> Void) {
        gifLibrary.deleteAsset(identifier: identifier, completion: completion)
    }
    
    func deleteGifAssets(identifiers: [String], completion: @escaping (Bool, Error?) -> Void) {
        gifLibrary.deleteAssets(identifiers: identifiers, completion: completion)
    }
}

// MARK: - PHPhotoLibraryChangeObserver

extension PhotoManager: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        refreshDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.gifLibrary.fetchMyGifs()
        }
        refreshDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
}
