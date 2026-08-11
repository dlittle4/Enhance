import Testing
import UIKit
@testable import Enhance

/// Local stub — `StubGIFGenerator` in EditorViewModelTests is file-private. These tests never
/// trigger generation, so it only needs to satisfy the initializer.
private struct SaveStubGenerator: GIFGenerating {
    func generateGIF(from image: UIImage, currentScale: CGFloat, visibleRect: CGRect, animator: Animator, speed: Double, pauseDuration: Double, visualEffects: [VisualEffect], faceEffect: FaceEffect?, detectedFaces: [DetectedFace], textOverlay: TextOverlay?) -> Data? { nil }
    func saveTempGIF(_ gifData: Data) -> URL? { nil }
}

/// SAVE on an existing GIF must save the *regenerated* file, never fall back to the untouched
/// original. Before the fix, `saveGIFToLibrary` read `generatedGifURL ?? existingGifURL`, so if
/// regeneration had produced in-memory data but no file URL, "SAVE NEW COPY" silently duplicated
/// the original the user had edited away from.
@MainActor
struct SaveGIFTests {

    private func existingGifViewModel() -> (EditorViewModel, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("original-\(UUID().uuidString).gif")
        // Real bytes so a bad fallback would actually save *this* file.
        try? Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]).write(to: url)
        let vm = EditorViewModel(content: .existingGif(url, 0, "asset-id"),
                                 gifGenerator: SaveStubGenerator())
        return (vm, url)
    }

    /// The bug state: an edit produced in-memory data but no generated file. The save must be
    /// refused with an error, not silently redirected to the original.
    @Test func save_withDataButNoGeneratedFile_isRefusedNotRedirected() {
        let (vm, originalURL) = existingGifViewModel()

        vm.generatedGIF = Data([1, 2, 3])   // regenerate produced data…
        vm.generatedGifURL = nil            // …but no file URL
        #expect(vm.existingGifURL == originalURL, "precondition: the original URL is still present")

        vm.saveGIFToLibrary(photoManager: PhotoManager())

        // The guard fired: error toast, and crucially the editor did NOT enter the saved state,
        // which is what it would do had it gone ahead and saved the original.
        #expect(vm.showSaveMessage)
        #expect(vm.saveMessage.contains("No GIF to save"))
        #expect(vm.enhanceState != .saved)

        try? FileManager.default.removeItem(at: originalURL)
    }

    /// The other half: with both present, the save proceeds (enters the saving toast) rather
    /// than being blocked — so the stricter guard did not break the normal path.
    @Test func save_withGeneratedFile_proceeds() {
        let (vm, originalURL) = existingGifViewModel()
        let genURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gen-\(UUID().uuidString).gif")
        try? Data([0x47, 0x49, 0x46]).write(to: genURL)

        vm.generatedGIF = Data([1, 2, 3])
        vm.generatedGifURL = genURL

        vm.saveGIFToLibrary(photoManager: PhotoManager())

        #expect(vm.showSaveMessage)
        #expect(vm.saveMessage.contains("Saving"), "expected the save to proceed, got: \(vm.saveMessage)")

        try? FileManager.default.removeItem(at: originalURL)
        try? FileManager.default.removeItem(at: genURL)
    }
}
