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

    /// The asset identifier of a GIF saved in this session that has not yet played its arrival
    /// animation in the gallery, or `nil` when there is nothing waiting.
    ///
    /// Keyed by identifier rather than by a bare "something was saved" flag so a second save
    /// landing while the first is still revealing replaces a known cell rather than corrupting an
    /// in-flight animation. `updateOriginalGIF` is a delete-then-create, so re-saving an existing
    /// GIF produces a genuinely new identifier and is honestly the same "a new item appeared"
    /// event as a first save.
    @Published var justSavedIdentifier: String?

    /// Called once the arrival animation has finished — or been abandoned, if the user left the
    /// gallery. Either way the cell goes back to rendering normally.
    func clearJustSaved(_ identifier: String) {
        guard justSavedIdentifier == identifier else { return }
        justSavedIdentifier = nil
    }
    
    private var isObservingPhotoLibrary = false
    
    override init() {
        super.init()
        
        permissions.$isAuthorized.assign(to: &$isAuthorized)
        permissions.$isDenied.assign(to: &$isDenied)
        gifLibrary.$myGifs.assign(to: &$myGifs)
        gifLibrary.$myGifURLs.assign(to: &$myGifURLs)
        gifLibrary.$myGifAssetIdentifiers.assign(to: &$myGifAssetIdentifiers)
        gifLibrary.$hasLoaded.assign(to: &$hasLoadedGifs)
        
        registerObserverIfAuthorized()
    }
    
    deinit {
        if isObservingPhotoLibrary {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }
    
    /// Only register for photo library changes after permission is granted.
    /// Calling register() while status is .notDetermined triggers the system permission dialog.
    private func registerObserverIfAuthorized() {
        guard !isObservingPhotoLibrary else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            PHPhotoLibrary.shared().register(self)
            isObservingPhotoLibrary = true
        }
    }
    
    // MARK: - Public API
    
    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        permissions.requestAuthorization { [weak self] success in
            if success {
                self?.registerObserverIfAuthorized()
                self?.gifLibrary.fetchMyGifs()
            } else {
                self?.hasLoadedGifs = true
            }
            completion?(success)
        }
    }
    
    func checkAuthorizationStatus() {
        permissions.checkStatus()
        if permissions.isAuthorized {
            registerObserverIfAuthorized()
            gifLibrary.fetchMyGifs()
        } else {
            hasLoadedGifs = true
        }
    }
    
    /// Completion carries the new asset's local identifier, so callers can persist per-GIF
    /// settings against it — see `GIFLibraryService.saveGif`.
    func saveGifToMyGifsAlbum(fileURL: URL, completion: @escaping (Bool, String?, Error?) -> Void) {
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
