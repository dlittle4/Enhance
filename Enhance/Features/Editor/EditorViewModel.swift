import SwiftUI
import Photos
import CoreImage
import ImageIO
import Vision

// MARK: - EditorSnapshot

struct EditorSnapshot {
    let animatorType: AnimatorType?
    let modifier: ModifierType?
    let playbackSpeed: Double
    let pauseDuration: Int
    let visualEffect: VisualEffectType?
    /// The whole parameter store. One field replaces the four fixed Doubles this used to
    /// carry; copy-on-write means snapshots share storage until the next write.
    let parameterValues: [String: Double]
    let effectCategory: EffectCategory
    let faceFilter: FaceFilterType?
    let selectedFaceIndex: Int?
    let laserColor: LaserColor
    let tintColor: LaserColor
    let gradientStops: GradientStops
}

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

    /// Zoom parameters captured at generation time, used for regeneration so that
    /// navigating in face filter mode doesn't alter the GIF's zoom point.
    private var generationScale: CGFloat = 1.0
    private var generationVisibleRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    
    var enhanceState: EnhanceState = .ready
    var isGenerating: Bool = false
    var isRegenerating: Bool = false
    var generatedGifURL: URL? = nil
    var generatedGIF: Data? = nil
    var showShareSheet: Bool = false
    var showSaveMessage: Bool = false
    var saveMessage: String = ""
    var showControls: Bool = false
    var selectedAnimatorType: AnimatorType? = .zoomIn
    var selectedModifier: ModifierType? = nil
    var isPlaying: Bool = true
    var playbackSpeed: Double = 0.5
    var pauseDuration: Int = 1
    var showSaveSheet: Bool = false
    var hasModifiedSettings: Bool = false
    var selectedEffectCategory: EffectCategory = .zoomEffects
    var selectedVisualEffect: VisualEffectType? = nil
    /// Per-parameter control values, keyed by `EffectParameter.key(_:for:)`.
    ///
    /// Replaces the four fixed Doubles this used to hold, so an effect can declare any
    /// number of controls. Keys are namespaced per effect family and per effect, which
    /// also gives each effect its own value memory — re-selecting FISHEYE finds the
    /// value you last left it at, rather than whatever the previous effect used.
    ///
    /// In-memory only; nothing here is persisted, so `EffectParameter`'s "ids must not
    /// change once shipped" warning does not bite yet. It would the moment these are
    /// written to UserDefaults.
    var parameterValues: [String: Double] = [:]

    func value<E: ParameterizedEffect>(_ paramID: String, for effect: E, default fallback: Double = 0.5) -> Double {
        parameterValues[EffectParameter.key(paramID, for: effect)] ?? fallback
    }

    func setValue<E: ParameterizedEffect>(_ newValue: Double, _ paramID: String, for effect: E) {
        parameterValues[EffectParameter.key(paramID, for: effect)] = newValue
    }

    /// Key for a visual-effect parameter under the current selection, falling back to a
    /// stable unselected key so the shims below never silently drop a write.
    private func visualKey(_ paramID: String) -> String {
        guard let effect = selectedVisualEffect else {
            return EffectParameter.unselectedKey(paramID, namespace: VisualEffectType.parameterNamespace)
        }
        return EffectParameter.key(paramID, for: effect)
    }

    private func faceKey(_ paramID: String) -> String {
        guard let filter = selectedFaceFilter else {
            return EffectParameter.unselectedKey(paramID, namespace: FaceFilterType.parameterNamespace)
        }
        return EffectParameter.key(paramID, for: filter)
    }

    // MARK: - Legacy value API
    // Shims over `parameterValues`, keyed on the current selection. They keep the
    // existing view and tests working while the storage changes underneath, and come
    // out once the editor reads values straight from the declared parameter list.

    var effectIntensity: Double {
        get { parameterValues[visualKey(EffectParameter.intensityID)] ?? 0.5 }
        set { parameterValues[visualKey(EffectParameter.intensityID)] = newValue }
    }

    var effectSize: Double {
        get { parameterValues[visualKey(EffectParameter.sizeID)] ?? 0.5 }
        set { parameterValues[visualKey(EffectParameter.sizeID)] = newValue }
    }

    var tintColor: LaserColor = .red
    var gradientStops: GradientStops = .default
    var previewImage: UIImage? = nil
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Face Filters
    var detectedFaces: [DetectedFace] = []
    var selectedFaceIndex: Int? = nil
    var selectedFaceFilter: FaceFilterType? = nil
    var faceFilterIntensity: Double {
        get { parameterValues[faceKey(EffectParameter.intensityID)] ?? 0.5 }
        set { parameterValues[faceKey(EffectParameter.intensityID)] = newValue }
    }

    var faceFilterSpeed: Double {
        get { parameterValues[faceKey(EffectParameter.secondaryID)] ?? 0.5 }
        set { parameterValues[faceKey(EffectParameter.secondaryID)] = newValue }
    }

    var laserColor: LaserColor = .red
    var isDetectingFaces: Bool = false
    private let faceDetectionService = FaceDetectionService()

    /// Called after a successful save to signal the editor should close.
    var onSaveComplete: (() -> Void)?

    // MARK: - Undo / Redo

    private var undoStack: [EditorSnapshot] = []
    private var redoStack: [EditorSnapshot] = []
    private let maxUndoDepth = 50

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func pushUndo() {
        undoStack.append(currentSnapshot())
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        restore(snapshot)
    }

    /// Pushes an undo entry for a continuous control, at most once per `minimumGap`.
    ///
    /// `ColorPicker` writes on every drag frame of the system colour wheel, so an
    /// unguarded push would bury the stack in near-identical entries and make undo
    /// useless. `previousStops` is the value *before* the change — SwiftUI's
    /// `onChange` hands it over, and snapshots must capture pre-change state.
    func pushUndoCoalesced(previousStops: GradientStops, minimumGap: TimeInterval = 0.7) {
        let now = Date()
        guard now.timeIntervalSince(lastCoalescedUndo) > minimumGap else { return }
        lastCoalescedUndo = now

        undoStack.append(currentSnapshot(gradientStopsOverride: previousStops))
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    /// Debounced regeneration for controls that emit a stream of values instead of a
    /// discrete commit. Sliders regenerate on drag-end; `ColorPicker` has no such
    /// signal, so it coalesces here.
    func scheduleRegenerate(after delay: TimeInterval = 0.45) {
        regenerateWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isRegenerating else { return }
            if case .existingGif = self.content {
                self.hasModifiedSettings = true
                self.regenerateGIF()
            } else if self.isSplit {
                self.regenerateGIF()
            }
        }
        regenerateWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private var regenerateWorkItem: DispatchWorkItem?
    private var lastCoalescedUndo: Date = .distantPast

    private func currentSnapshot(gradientStopsOverride: GradientStops? = nil) -> EditorSnapshot {
        EditorSnapshot(
            animatorType: selectedAnimatorType,
            modifier: selectedModifier,
            playbackSpeed: playbackSpeed,
            pauseDuration: pauseDuration,
            visualEffect: selectedVisualEffect,
            parameterValues: parameterValues,
            effectCategory: selectedEffectCategory,
            faceFilter: selectedFaceFilter,
            selectedFaceIndex: selectedFaceIndex,
            laserColor: laserColor,
            tintColor: tintColor,
            gradientStops: gradientStopsOverride ?? gradientStops
        )
    }

    private func restore(_ snapshot: EditorSnapshot) {
        selectedAnimatorType = snapshot.animatorType
        selectedModifier = snapshot.modifier
        playbackSpeed = snapshot.playbackSpeed
        pauseDuration = snapshot.pauseDuration
        selectedVisualEffect = snapshot.visualEffect
        parameterValues = snapshot.parameterValues
        selectedEffectCategory = snapshot.effectCategory
        selectedFaceFilter = snapshot.faceFilter
        selectedFaceIndex = snapshot.selectedFaceIndex
        laserColor = snapshot.laserColor
        tintColor = snapshot.tintColor
        gradientStops = snapshot.gradientStops

        updateCombinedPreview()

        if selectedEffectCategory == .faceFilters {
            detectFacesIfNeeded()
        }

        if case .existingGif = content {
            hasModifiedSettings = true
            regenerateGIF()
        } else if isSplit {
            regenerateGIF()
        }
    }

    var selectedFace: DetectedFace? {
        guard let idx = selectedFaceIndex, idx < detectedFaces.count else { return nil }
        return detectedFaces[idx]
    }

    /// Faces that the active face effect should target. When no face is
    /// explicitly selected, all detected faces are included. Tapping a
    /// face isolates it; tapping it again reverts to all.
    var activeFaces: [DetectedFace] {
        if let idx = selectedFaceIndex, idx < detectedFaces.count {
            return [detectedFaces[idx]]
        }
        return detectedFaces
    }

    /// Clears a single-face-only filter when switching back to all-faces mode.
    func clearSingleFaceFilterIfNeeded() {
        if selectedFaceFilter?.requiresSingleFace == true {
            selectedFaceFilter = nil
        }
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

    /// Reads the value store directly by well-known id — deliberately *not* via
    /// `filter.parameters`, which allocates an array and would run on every debounced
    /// preview update.
    var activeFaceEffect: FaceEffect? {
        guard let filter = selectedFaceFilter else { return nil }
        return filter.effect(
            intensity: value(EffectParameter.intensityID, for: filter),
            secondValue: value(EffectParameter.secondaryID, for: filter),
            laserColor: laserColor
        )
    }

    /// Same hot-path rule as `activeFaceEffect`: direct dict reads, never `.parameters`.
    var activeVisualEffectList: [VisualEffect] {
        guard let effect = selectedVisualEffect else { return [] }
        let options = EffectOptions(
            size: value(EffectParameter.sizeID, for: effect),
            tintColor: tintColor,
            gradientStops: gradientStops
        )
        return [effect.effect(intensity: value(EffectParameter.intensityID, for: effect), options: options)]
    }

    var activeAnimator: Animator {
        guard let animType = selectedAnimatorType else {
            return StaticAnimator()
        }
        guard let mod = selectedModifier, mod != .straight else {
            return animType.animator
        }
        return CompositeAnimator(base: animType.animator, modifier: mod.modifier)
    }

    var hasNonDefaultSettings: Bool {
        let hasVisualEffect = selectedVisualEffect != nil
        let hasFaceFilter = selectedFaceFilter != nil
        if case .newImage = content {
            return selectedAnimatorType != .zoomIn || selectedModifier != nil || playbackSpeed != 0.5 || pauseDuration != 1 || isSplit || hasVisualEffect || hasFaceFilter
        }
        return selectedAnimatorType != .zoomIn || selectedModifier != nil || playbackSpeed != 0.5 || pauseDuration != 1 || hasVisualEffect || hasFaceFilter
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
        pushUndo()

        selectedAnimatorType = .zoomIn
        selectedModifier = nil
        playbackSpeed = 0.5
        pauseDuration = 1
        selectedVisualEffect = nil
        parameterValues.removeAll()
        selectedEffectCategory = .zoomEffects
        previewImage = nil
        previewSourceCGImage = nil
        effectThumbnails = [:]
        thumbnailSourceCGImage = nil
        selectedFaceFilter = nil
        selectedFaceIndex = nil
        laserColor = .red
        tintColor = .red
        gradientStops = .default
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
                if faces.isEmpty {
                    self.showToast("NO FACES DETECTED")
                }
            }
        }
    }

    func redetectFaces() {
        guard !isDetectingFaces else { return }
        guard let source = image ?? sourceImage else { return }

        detectedFaces = []
        selectedFaceIndex = nil
        isDetectingFaces = true
        Task {
            let faces = await faceDetectionService.redetect(in: source)
            await MainActor.run {
                self.detectedFaces = faces
                self.isDetectingFaces = false
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

    // MARK: - Effect Thumbnails

    /// Cached mini-thumbnails showing each visual effect applied to the user's photo.
    var effectThumbnails: [VisualEffectType: UIImage] = [:]
    private var thumbnailSourceCGImage: CGImage?
    private let thumbnailDimension: Int = 120

    /// Generates small preview thumbnails for all visual effects on a background thread.
    func generateEffectThumbnails() {
        guard let source = image ?? sourceImage else { return }
        guard effectThumbnails.isEmpty else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let thumb = self.getThumbnailSourceCGImage(from: source)
            guard let thumb else { return }

            let ciInput = CIImage(cgImage: thumb)
            var results: [VisualEffectType: UIImage] = [:]

            for effectType in VisualEffectType.selectable {
                let options = EffectOptions(size: 0.5, tintColor: .purple, gradientStops: .default)
                let effect = effectType.effect(intensity: 0.7, options: options)
                let progress = effectType.previewProgress
                let output = effect.apply(to: ciInput, progress: progress, frameIndex: 3)
                if let cgOut = self.ciContext.createCGImage(output, from: output.extent) {
                    results[effectType] = UIImage(cgImage: cgOut)
                }
            }

            DispatchQueue.main.async {
                self.effectThumbnails = results
            }
        }
    }

    private func getThumbnailSourceCGImage(from source: UIImage) -> CGImage? {
        if let cached = thumbnailSourceCGImage { return cached }
        guard let data = source.jpegData(compressionQuality: 0.7),
              let imgSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return source.cgImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: thumbnailDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(imgSource, 0, options as CFDictionary) else {
            return source.cgImage
        }
        thumbnailSourceCGImage = thumb
        return thumb
    }

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
        let faces = activeFaces

        guard !visualEffects.isEmpty || (faceEffect != nil && !faces.isEmpty) else {
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

                if let faceEffect, !faces.isEmpty {
                    let orientedWidth = source.size.width * source.scale
                    let orientedHeight = source.size.height * source.scale
                    let scaleX = result.extent.width / orientedWidth
                    let scaleY = result.extent.height / orientedHeight
                    let previewProg = self.selectedFaceFilter?.previewProgress ?? 1.0
                    for face in faces {
                        let scaledFace = self.scaleFace(face, scaleX: scaleX, scaleY: scaleY)
                        result = faceEffect.apply(to: result, face: scaledFace, progress: previewProg, frameIndex: 5)
                    }
                }

                if !visualEffects.isEmpty {
                    let imgW = result.extent.width
                    let imgH = result.extent.height
                    let vpCenterX = (rect.origin.x + rect.width / 2) * imgW
                    let vpCenterY = (1.0 - (rect.origin.y + rect.height / 2)) * imgH
                    let center = CGPoint(x: vpCenterX, y: vpCenterY)
                    let previewProg = self.selectedVisualEffect?.previewProgress ?? 1.0
                    for effect in visualEffects {
                        result = effect.apply(to: result, progress: previewProg, frameIndex: 0, viewportCenter: center)
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
                guard let self else { return }
                self.sourceImage = image

                if let id = self.existingGifAssetIdentifier, let params = Self.loadZoomParams(for: id) {
                    self.generationScale = params.scale
                    self.generationVisibleRect = params.rect
                } else {
                    self.generationScale = 2.0
                    self.generationVisibleRect = CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7)
                }

                self.currentScale = self.generationScale
                self.visibleRect = self.generationVisibleRect

                if self.selectedEffectCategory == .faceFilters {
                    self.detectFacesIfNeeded()
                }
            }
        }
    }
    
    /// Whether the user can generate without zooming in — true when a visual
    /// effect, face filter, or modifier is applied that will animate on its own.
    private var hasEffectsWithoutZoom: Bool {
        selectedVisualEffect != nil || selectedFaceFilter != nil || selectedModifier != nil
    }

    func generateGIF() {
        guard let imageToUse = image else {
            showToast("Error: No image selected")
            return
        }
        
        let needsZoom = selectedAnimatorType != nil
        if needsZoom && currentScale <= 1.0 {
            showToast("Zoom in on the image first!")
            withAnimation(.spring(response: AppConstants.Animation.standard, dampingFraction: 0.6)) {
                currentScale = 1.2
                DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Animation.standard) {
                    withAnimation { self.currentScale = 1.0 }
                }
            }
            return
        }

        if !needsZoom && !hasEffectsWithoutZoom {
            showToast("Select an effect or zoom type first!")
            return
        }
        
        generationScale = currentScale
        generationVisibleRect = visibleRect

        withAnimation(.spring(response: AppConstants.Animation.slow, dampingFraction: 0.7)) {
            enhanceState = .generating
            isGenerating = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let animator = activeAnimator
            
            if let gifData = gifGenerator.generateGIF(
                from: imageToUse, currentScale: generationScale,
                visibleRect: generationVisibleRect, animator: animator,
                speed: playbackSpeed,
                pauseDuration: Double(pauseDuration),
                visualEffects: activeVisualEffectList,
                faceEffect: activeFaceEffect,
                detectedFaces: activeFaces
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
        let canRegenerate = generationScale > 1.0 || selectedAnimatorType == nil || hasEffectsWithoutZoom
        guard let sourceImg, canRegenerate else { return }
        
        withAnimation { isRegenerating = true }
        
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let animator = activeAnimator
            
            if let gifData = gifGenerator.generateGIF(
                from: sourceImg, currentScale: generationScale,
                visibleRect: generationVisibleRect, animator: animator,
                speed: playbackSpeed,
                pauseDuration: Double(pauseDuration),
                visualEffects: activeVisualEffectList,
                faceEffect: activeFaceEffect,
                detectedFaces: activeFaces
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
                    HapticService.success()
                    self.showToast("GIF saved to My GIFs")
                    withAnimation(.spring(response: AppConstants.Animation.slow, dampingFraction: 0.7)) {
                        self.enhanceState = .saved
                        self.hasModifiedSettings = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        photoManager.forceRefreshGifs()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.onSaveComplete?()
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
        
        persistZoomParams(for: identifier)
        showToast("Updating GIF...")
        
        photoManager.deleteGifAsset(identifier: identifier) { [weak self] success, error in
            guard let self else { return }
            if success {
                photoManager.saveGifToMyGifsAlbum(fileURL: url) { [weak self] saveSuccess, saveError in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if saveSuccess {
                            HapticService.success()
                            self.showToast("GIF updated")
                            withAnimation(.spring(response: AppConstants.Animation.slow, dampingFraction: 0.7)) {
                                self.enhanceState = .saved
                                self.hasModifiedSettings = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                photoManager.forceRefreshGifs()
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                self.onSaveComplete?()
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

    // MARK: - Zoom Param Persistence

    private static let zoomParamsPrefix = "zoomParams_"

    static func saveZoomParams(scale: CGFloat, rect: CGRect, for identifier: String) {
        guard !identifier.isEmpty else { return }
        let values: [Double] = [Double(scale), rect.origin.x, rect.origin.y, rect.width, rect.height]
        UserDefaults.standard.set(values, forKey: "\(zoomParamsPrefix)\(identifier)")
    }

    static func loadZoomParams(for identifier: String) -> (scale: CGFloat, rect: CGRect)? {
        guard !identifier.isEmpty,
              let values = UserDefaults.standard.array(forKey: "\(zoomParamsPrefix)\(identifier)") as? [Double],
              values.count == 5 else { return nil }
        return (CGFloat(values[0]), CGRect(x: values[1], y: values[2], width: values[3], height: values[4]))
    }

    func persistZoomParams(for identifier: String) {
        Self.saveZoomParams(scale: generationScale, rect: generationVisibleRect, for: identifier)
    }
}
