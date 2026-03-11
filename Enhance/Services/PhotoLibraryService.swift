import Photos

/// Minimal helper for album-level queries used by GIFLibraryService.
/// Photo browsing and selection is now handled by the native PhotosPicker.
class PhotoLibraryService {
    static func fetchAlbumCollection(named name: String) -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "localizedTitle = %@", name)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions).firstObject
    }
}
