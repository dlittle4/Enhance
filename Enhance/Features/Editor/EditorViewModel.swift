import SwiftUI
import Photos
import CoreImage
import ImageIO
import Vision

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
    var playbackSpeed: Double = 0.5
    var pauseDuration: Int = 1
    var showSaveSheet: Bool = false
    var hasModifiedSettings: Bool = false
    var selectedEffectCategory: EffectCategory = .zoomEffects
    var selectedVisualEffect: VisualEffectType? = nil
    var effectIntensity: Double = 0.5
    var effectSize: Double = 0.5
    var previewImage: UIImage? = nil
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Face Filters
    var detectedFaces: [DetectedFace] = []
    var selectedFaceIndex: Int? = nil
    var selectedFaceFilter: FaceFilterType? = nil
    var faceFilterIntensity: Double = 0.5
    var faceFilterSpeed: Double = 0.5
    var isDetectingFaces: Bool = false
    private let faceDetectionService = FaceDetectionService()

    var selectedFace: DetectedFace? {
        guard let idx = selectedFaceIndex, idx < detectedFaces.count else { return nil }
        return detectedFaces[idx]
    }

    var faceFilterSliderLabel: String {
        selectedFaceFilter?.sliderLabel ?? "INTENSITY"
    }

    var faceFilterIntensityLabel: String {
        selectedFaceFilter?.intensityBucket(faceFilterIntensity) ?? "MEDIUM"
    }

    var faceFilterSecondLabel: String {
        selectedFaceFilter?.secondSliderBucket(faceFilterSpeed) ?? "MEDIUM"
    }

    var activeFaceEffect: FaceEffect? {
        guard let filter = selectedFaceFilter else { return nil }
        return filter.effect(intensity: faceFilterIntensity, secondValue: faceFilterSpeed)
    }

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
        let hasFaceFilter = selectedFaceFilter != nil
        if case .newImage = content {
            return selectedAnimatorType != .zoomIn || selectedModifier != .straight || playbackSpeed != 0.5 || pauseDuration != 1 || isSplit || hasVisualEffect || hasFaceFilter
        }
        return selectedAnimatorType != .zoomIn || selectedModifier != .straight || playbackSpeed != 0.5 || pauseDuration != 1 || hasVisualEffect || hasFaceFilter
    }

    var speedLabel: String {
        switch playbackSpeed {
        case 0.25: return "0.25X"
        case 0.5:  return "0.5X"
        case 1.0:  return "1X"
        default:   return "\(Int(playbackSpeed))X"
        }
    }

    var pauseLabel: String {
        pauseDuration == 1 ? "1 SECOND" : "\(pauseDuration) SECONDS"
    }

    func cycleSpeed() {
        switch playbackSpeed {
        case 0.25: playbackSpeed = 0.5
        case 0.5:  playbackSpeed = 1.0
        case 1.0:  playbackSpeed = 2.0
        default:   playbackSpeed = 0.25
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
        playbackSpeed = 0.5
        pauseDuration = 1
        selectedVisualEffect = nil
        effectIntensity = 0.5
        effectSize = 0.5
        selectedEffectCategory = .zoomEffects
        previewImage = nil
        previewSourceCGImage = nil
        selectedFaceFilter = nil
        selectedFaceIndex = nil
        faceFilterIntensity = 0.5
        faceFilterSpeed = 0.5
        detectedFaces = []
        faceDetectionService.clearCache()

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

    func onFaceFilterIntensityDragEnded() {
        updateFaceFilterPreview()
        guard !isRegenerating else { return }
        if case .existingGif = content {
            hasModifiedSettings = true
            regenerateGIF()
        } else if isSplit {
            regenerateGIF()
        }
    }

    func onFaceFilterSpeedDragEnded() {
        updateFaceFilterPreview()
        guard !isRegenerating else { return }
        if case .existingGif = content {
            hasModifiedSettings = true
            regenerateGIF()
        } else if isSplit {
            regenerateGIF()
        }
    }

    func detectFacesIfNeeded() {
        guard !isDetectingFaces else { return }
        guard let source = image ?? sourceImage else { return }
        guard detectedFaces.isEmpty else { return }

        isDetectingFaces = true
        Task {
            let faces = await faceDetectionService.detectFaces(in: source)
            await MainActor.run {
                self.detectedFaces = faces
                self.isDetectingFaces = false
                if faces.count == 1 {
                    self.selectedFaceIndex = 0
                }
            }
        }
    }

    func updateFaceFilterPreview() {
        updateCombinedPreview()
    }

    /// Scale face landmark coordinates to match the downscaled preview image.
    private func scaleFace(_ face: DetectedFace, scaleX: CGFloat, scaleY: CGFloat) -> DetectedFace {
        DetectedFace(
            boundingBox: CGRect(
                x: face.boundingBox.origin.x * scaleX,
                y: face.boundingBox.origin.y * scaleY,
                width: face.boundingBox.width * scaleX,
                height: face.boundingBox.height * scaleY
            ),
            faceCenter: CGPoint(x: face.faceCenter.x * scaleX, y: face.faceCenter.y * scaleY),
            faceWidth: face.faceWidth * scaleX,
            faceHeight: face.faceHeight * scaleY,
            leftPupilCenter: face.leftPupilCenter.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) },
            rightPupilCenter: face.rightPupilCenter.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) },
            leftEyeWidth: face.leftEyeWidth * scaleX,
            rightEyeWidth: face.rightEyeWidth * scaleX,
            leftEyebrowPoints: face.leftEyebrowPoints.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) },
            rightEyebrowPoints: face.rightEyebrowPoints.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) },
            faceContourPoints: face.faceContourPoints.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) },
            normalizedBoundingBox: face.normalizedBoundingBox
        )
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
        updateCombinedPreview(debounce: debounce)
    }

    /// Unified preview that applies both visual effects and face effects together.
    private func updateCombinedPreview(debounce: Bool = false) {
        previewDebounceItem?.cancel()
        previewWorkItem?.cancel()

        guard let source = image ?? sourceImage else {
            previewImage = nil
            return
        }

        if isSplit, case .newImage = content {
            previewImage = nil
            return
        }

        let visualEffects = activeVisualEffectList
        let faceEffect = activeFaceEffect
        let face = selectedFace

        guard !visualEffects.isEmpty || (faceEffect != nil && face != nil) else {
            previewImage = nil
            return
        }

        let schedule = { [weak self] in
            guard let self else { return }
            let rect = self.visibleRect
            let work = DispatchWorkItem { [weak self] in
                guard let self,
                      let cgImage = self.getPreviewSourceCGImage(from: source) else { return }
                var result = CIImage(cgImage: cgImage)

                if let faceEffect, let face {
                    let orientedWidth = source.size.width * source.scale
                    let orientedHeight = source.size.height * source.scale
                    let scaleX = result.extent.width / orientedWidth
                    let scaleY = result.extent.height / orientedHeight
                    let scaledFace = self.scaleFace(face, scaleX: scaleX, scaleY: scaleY)
                    let previewProg = self.selectedFaceFilter?.previewProgress ?? 1.0
                    result = faceEffect.apply(to: result, face: scaledFace, progress: previewProg, frameIndex: 5)
                }

                if !visualEffects.isEmpty {
                    let imgW = result.extent.width
                    let imgH = result.extent.height
                    let vpCenterX = (rect.origin.x + rect.width / 2) * imgW
                    let vpCenterY = (1.0 - (rect.origin.y + rect.height / 2)) * imgH
                    let center = CGPoint(x: vpCenterX, y: vpCenterY)
                    for effect in visualEffects {
                        result = effect.apply(to: result, progress: 1.0, frameIndex: 0, viewportCenter: center)
                    }
                }

                guard let outputCG = self.ciContext.createCGImage(result, from: result.extent) else { return }
                let uiImage = UIImage(cgImage: outputCG, scale: source.scale, orientation: .up)
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
                if self?.selectedEffectCategory == .faceFilters {
                    self?.detectFacesIfNeeded()
                }
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
                visualEffects: activeVisualEffectList,
                faceEffect: activeFaceEffect,
                detectedFace: selectedFace
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
                visualEffects: activeVisualEffectList,
                faceEffect: activeFaceEffect,
                detectedFace: selectedFace
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
