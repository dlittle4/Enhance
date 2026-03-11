import SwiftUI
import Photos
import CoreImage
import ImageIO

@Observable
class EditorViewModel {
    var content: DetailContent
    private let gifGenerator: GIFGenerating
    
    var scale: CGFloat = 1.0
    var lastScale: CGFloat = 1.0
    var offset: CGSize = .zero
    var lastOffset: CGSize = .zero
    var currentScale: CGFloat = 1.0
    var visibleRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    
    var enhanceState: EnhanceState = .ready
    var isGenerating: Bool = false
    var isRegenerating: Bool = false
    var generatedGifURL: URL? = nil
    var generatedGIF: Data? = nil
    var showShareSheet: Bool = false
    var showSaveMessage: Bool = false
    var saveMessage: String = ""
    var showControls: Bool = false
    var selectedAnimatorType: AnimatorType = .zoomIn
    var selectedModifier: ModifierType = .straight
    var isPlaying: Bool = true
    var playbackSpeed: Double = 1.0
    var pauseDuration: Int = 1
    var showEffectsSheet: Bool = false
    var showSaveSheet: Bool = false
    var hasModifiedSettings: Bool = false
    var selectedEffectCategory: EffectCategory = .zoomEffects
    var selectedVisualEffect: VisualEffectType? = nil
    var effectIntensity: Double = 0.5
    var effectSize: Double = 0.5
    var previewImage: UIImage? = nil
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    var activeVisualEffectList: [VisualEffect] {
        guard let effect = selectedVisualEffect else { return [] }
        return [effect.effect(intensity: effectIntensity, size: effectSize)]
    }

    var activeAnimator: Animator {
        if selectedModifier == .straight {
            return selectedAnimatorType.animator
        }
        return CompositeAnimator(base: selectedAnimatorType.animator, modifier: selectedModifier.modifier)
    }

    var hasNonDefaultSettings: Bool {
        let hasVisualEffect = selectedVisualEffect != nil
        if case .newImage = content {
            return selectedAnimatorType != .zoomIn || selectedModifier != .straight || playbackSpeed != 1.0 || pauseDuration != 1 || isSplit || hasVisualEffect
        }
        return selectedAnimatorType != .zoomIn || selectedModifier != .straight || playbackSpeed != 1.0 || pauseDuration != 1 || hasVisualEffect
    }

    var speedLabel: String {
        playbackSpeed == 0.5 ? "0.5X" : playbackSpeed == 1.0 ? "1X" : "\(Int(playbackSpeed))X"
    }

    var pauseLabel: String {
        pauseDuration == 1 ? "1 SECOND" : "\(pauseDuration) SECONDS"
    }

    func cycleSpeed() {
        switch playbackSpeed {
        case 1.0: playbackSpeed = 2.0
        case 2.0: playbackSpeed = 0.5
        default:  playbackSpeed = 1.0
        }
    }

    func cyclePause() {
        pauseDuration = pauseDuration >= 5 ? 1 : pauseDuration + 1
    }

    var intensityLabel: String {
        switch effectIntensity {
        case ..<0.3: return "LOW"
        case ..<0.6: return "MEDIUM"
        case ..<0.85: return "HIGH"
        default: return "MAX"
        }
    }

    var sizeLabel: String {
        switch effectSize {
        case ..<0.3: return "SMALL"
        case ..<0.6: return "MEDIUM"
        case ..<0.85: return "LARGE"
        default: return "MAX"
        }
    }

    func resetEffects() {
        selectedAnimatorType = .zoomIn
        selectedModifier = .straight
        playbackSpeed = 1.0
        pauseDuration = 1
        selectedVisualEffect = nil
        effectIntensity = 0.5
        effectSize = 0.5
        selectedEffectCategory = .zoomEffects
        previewImage = nil
        previewSourceCGImage = nil

        if case .newImage = content {
            generatedGIF = nil
            generatedGifURL = nil
            withAnimation(.spring(response: AppConstants.Animation.standard, dampingFraction: 0.8)) {
                enhanceState = .ready
                isGenerating = false
            }
        }
    }

    func onIntensityDragEnded() {
        updatePreviewImage()
        guard !isRegenerating else { return }
        if case .existingGif = content {
            hasModifiedSettings = true
            regenerateGIF()
        } else if isSplit {
            regenerateGIF()
        }
    }

    func onSizeDragEnded() {
        updatePreviewImage()
        guard !isRegenerating else { return }
        if case .existingGif = content {
            hasModifiedSettings = true
            regenerateGIF()
        } else if isSplit {
            regenerateGIF()
        }
    }

    private var previewWorkItem: DispatchWorkItem?
    private var previewDebounceItem: DispatchWorkItem?
    private var previewSourceCGImage: CGImage?
    private let previewMaxDimension: Int = 650

    private func getPreviewSourceCGImage(from source: UIImage) -> CGImage? {
        if let cached = previewSourceCGImage { return cached }
        guard let data = source.jpegData(compressionQuality: 0.9),
              let imgSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return source.cgImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: previewMaxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(imgSource, 0, options as CFDictionary) else {
            return source.cgImage
        }
        previewSourceCGImage = thumb
        return thumb
    }

    func updatePreviewImage(debounce: Bool = false) {
        previewDebounceItem?.cancel()
        previewWorkItem?.cancel()

        guard let source = image, !isSplit else {
            previewImage = nil
            return
        }
        let effects = activeVisualEffectList
        guard !effects.isEmpty else {
            previewImage = nil
            return
        }

        let schedule = { [weak self] in
            guard let self else { return }
            let rect = self.visibleRect
            let work = DispatchWorkItem { [weak self] in
                guard let self,
                      let cgImage = self.getPreviewSourceCGImage(from: source) else { return }
                let ciImage = CIImage(cgImage: cgImage)

                let imgW = ciImage.extent.width
                let imgH = ciImage.extent.height
                let vpCenterX = (rect.origin.x + rect.width / 2) * imgW
                let vpCenterY = (1.0 - (rect.origin.y + rect.height / 2)) * imgH
                let center = CGPoint(x: vpCenterX, y: vpCenterY)

                var result = ciImage
                for effect in effects {
                    result = effect.apply(to: result, progress: 1.0, frameIndex: 0, viewportCenter: center)
                }
                guard let outputCG = self.ciContext.createCGImage(result, from: result.extent) else { return }
                let uiImage = UIImage(cgImage: outputCG, scale: source.scale, orientation: source.imageOrientation)
                DispatchQueue.main.async {
                    self.previewImage = uiImage
                }
            }
            self.previewWorkItem = work
            DispatchQueue.global(qos: .userInteractive).async(execute: work)
        }

        if debounce {
            let debounceWork = DispatchWorkItem(block: schedule)
            previewDebounceItem = debounceWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: debounceWork)
        } else {
            schedule()
        }
    }
    
    /// For existing GIFs: the first frame extracted for re-editing
    var sourceImage: UIImage?
    
    var image: UIImage? {
        if case .newImage(let img) = content { return img }
        return nil
    }
    
    var existingGifURL: URL? {
        if case .existingGif(let url, _, _) = content { return url }
        return nil
    }
    
    var existingGifAssetIdentifier: String? {
        if case .existingGif(_, _, let id) = content { return id }
        return nil
    }
    
    var gifURL: URL? {
        generatedGifURL ?? existingGifURL
    }
    
    var gifIndex: Int {
        return -1
    }
    
    /// Whether the SAVE button should be tappable
    var isSaveEnabled: Bool {
        if case .newImage = content {
            return isSplit
        }
        return hasModifiedSettings && !isRegenerating
    }
    
    var isSplit: Bool {
        enhanceState == .share || enhanceState == .saved
    }
    
    var buttonText: String {
        switch enhanceState {
        case .ready: return "ENHANCE"
        case .generating: return "GENERATING..."
        case .share, .saved: return "SHARE"
        }
    }
    
    init(content: DetailContent, gifGenerator: GIFGenerating = GIFGenerator()) {
        self.content = content
        self.gifGenerator = gifGenerator
        if case .existingGif(let url, _, _) = content {
            enhanceState = .share
            extractSourceImage(from: url)
        }
    }
    
    private func extractSourceImage(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = try? Data(contentsOf: url),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return
            }
            let image = UIImage(cgImage: cgImage)
            DispatchQueue.main.async {
                self?.sourceImage = image
                self?.currentScale = 2.0
                self?.visibleRect = CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7)
            }
        }
    }
    
    func generateGIF() {
        guard image != nil else {
            showToast("Error: No image selected")
            return
        }
        
        if currentScale <= 1.0 {
            showToast("Zoom in on the image first!")
            withAnimation(.spring(response: AppConstants.Animation.standard, dampingFraction: 0.6)) {
                currentScale = 1.2
                DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Animation.standard) {
                    withAnimation { self.currentScale = 1.0 }
                }
            }
            return
        }
        
        withAnimation(.spring(response: AppConstants.Animation.slow, dampingFraction: 0.7)) {
            enhanceState = .generating
            isGenerating = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let animator = activeAnimator
            
            if let gifData = gifGenerator.generateGIF(
                from: image!, currentScale: currentScale,
                visibleRect: visibleRect, animator: animator,
                speed: playbackSpeed,
                pauseDuration: Double(pauseDuration),
                visualEffects: activeVisualEffectList
            ) {
                let tempDir = FileManager.default.temporaryDirectory
                let fileURL = tempDir.appendingPathComponent("\(UUID().uuidString).gif")
                
                do {
                    try gifData.write(to: fileURL)
                    DispatchQueue.main.async {
                        self.generatedGIF = gifData
                        self.generatedGifURL = fileURL
                        withAnimation(.spring(response: AppConstants.Animation.slow, dampingFraction: 0.7)) {
                            self.enhanceState = .share
                            self.isGenerating = false
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.resetToReady()
                        self.showToast("Error creating GIF")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.resetToReady()
                    self.showToast("Error creating GIF")
                }
            }
        }
    }
    
    func regenerateGIF() {
        let sourceImg: UIImage? = image ?? sourceImage
        guard let sourceImg, currentScale > 1.0 else { return }
        
        withAnimation { isRegenerating = true }
        
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let animator = activeAnimator
            
            if let gifData = gifGenerator.generateGIF(
                from: sourceImg, currentScale: currentScale,
                visibleRect: visibleRect, animator: animator,
                speed: playbackSpeed,
                pauseDuration: Double(pauseDuration),
                visualEffects: activeVisualEffectList
            ) {
                let tempDir = FileManager.default.temporaryDirectory
                let fileURL = tempDir.appendingPathComponent("\(UUID().uuidString).gif")
                
                do {
                    try gifData.write(to: fileURL)
                    DispatchQueue.main.async {
                        self.generatedGIF = gifData
                        self.generatedGifURL = fileURL
                        withAnimation(.spring(response: AppConstants.Animation.standard, dampingFraction: 0.8)) {
                            self.isRegenerating = false
                            self.enhanceState = .share
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        withAnimation { self.isRegenerating = false }
                        self.showToast("Error creating GIF")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    withAnimation { self.isRegenerating = false }
                    self.showToast("Error creating GIF")
                }
            }
        }
    }
    
    func saveGIFToLibrary(photoManager: PhotoManager) {
        guard let url = gifURL, generatedGIF != nil else {
            showToast("Error: No GIF to save")
            return
        }
        
        showToast("Saving GIF...")
        
        photoManager.saveGifToMyGifsAlbum(fileURL: url) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if success {
                    self.showToast("GIF saved to My GIFs")
                    withAnimation(.spring(response: AppConstants.Animation.slow, dampingFraction: 0.7)) {
                        self.enhanceState = .saved
                        self.hasModifiedSettings = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        photoManager.forceRefreshGifs()
                    }
                } else {
                    self.showToast("Error saving: \(error?.localizedDescription ?? "Unknown error")")
                    withAnimation { self.enhanceState = .share }
                }
            }
        }
    }
    
    func updateOriginalGIF(photoManager: PhotoManager) {
        guard let identifier = existingGifAssetIdentifier, !identifier.isEmpty else {
            showToast("Error: Cannot find original GIF")
            return
        }
        guard let url = generatedGifURL, generatedGIF != nil else {
            showToast("Error: No modified GIF to save")
            return
        }
        
        showToast("Updating GIF...")
        
        photoManager.deleteGifAsset(identifier: identifier) { [weak self] success, error in
            guard let self else { return }
            if success {
                photoManager.saveGifToMyGifsAlbum(fileURL: url) { [weak self] saveSuccess, saveError in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if saveSuccess {
                            self.showToast("GIF updated")
                            withAnimation(.spring(response: AppConstants.Animation.slow, dampingFraction: 0.7)) {
                                self.enhanceState = .saved
                                self.hasModifiedSettings = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                photoManager.forceRefreshGifs()
                            }
                        } else {
                            self.showToast("Error saving: \(saveError?.localizedDescription ?? "Unknown error")")
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.showToast("Error deleting original: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
    
    func showToast(_ message: String) {
        saveMessage = message
        withAnimation { showSaveMessage = true }
    }
    
    private func resetToReady() {
        withAnimation(.spring(response: AppConstants.Animation.slow, dampingFraction: 0.7)) {
            enhanceState = .ready
            isGenerating = false
        }
    }
}
