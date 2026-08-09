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
    let pauseDuration: Double
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
    var playbackSpeed: Double = ZoomPlayback.defaultSpeed
    var pauseDuration: Double = ZoomPlayback.defaultPause
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

    var tintColor: LaserColor = .red
    var gradientStops: GradientStops = .default
    var previewImage: UIImage? = nil
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Face Filters
    var detectedFaces: [DetectedFace] = []
    var selectedFaceIndex: Int? = nil
    var selectedFaceFilter: FaceFilterType? = nil
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

    /// Single place undo entries are recorded. Snapshots must capture *pre-change*
    /// state, so every caller passes the state as it was before the edit it represents.
    private func push(_ snapshot: EditorSnapshot) {
        undoStack.append(snapshot)
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func pushUndo() {
        push(currentSnapshot())
    }

    // MARK: - Effect edit session

    /// True while the effect detail panel is open. Navigation state, deliberately *not*
    /// part of `EditorSnapshot` — undo should not teleport between panels.
    var isEditingEffect = false

    /// State as it was when the panel opened, so the back chevron can discard.
    private var editEntrySnapshot: EditorSnapshot?

    /// Whether the active category has something for the panel to edit.
    ///
    /// Zoom always does: even with no zoom type selected, speed, pause and motion are
    /// still meaningful. The other two need a selection, and checking per category also
    /// stops the zoom tab opening a blank panel because a visual effect happens to be
    /// selected on another tab.
    private var hasEditableSelection: Bool {
        switch selectedEffectCategory {
        case .zoomEffects:   return true
        case .visualEffects: return selectedVisualEffect != nil
        case .faceFilters:   return selectedFaceFilter != nil
        }
    }

    /// Normalises the optional modifier for an always-one-selected control.
    ///
    /// `nil` stays canonical in storage — `hasActiveModifier`, `hasEffectsWithoutZoom`
    /// and `resetEffects` all keep working untouched — while LINEAR displays as selected.
    var modifierSelection: ModifierType {
        get { selectedModifier ?? .straight }
        set { selectedModifier = (newValue == .straight) ? nil : newValue }
    }

    /// The parameters the open panel should render, resolved from the active category.
    var editingParameters: [EffectParameter] {
        switch selectedEffectCategory {
        case .visualEffects: return selectedVisualEffect?.parameters ?? []
        case .faceFilters:   return selectedFaceFilter?.parameters ?? []
        case .zoomEffects:   return []
        }
    }

    /// How many rows the open panel will render. The panel needs this to size them
    /// before layout, and cannot infer it from opaque content.
    var editingRowCount: Int {
        switch selectedEffectCategory {
        // Speed, pause, motion — built directly rather than declared.
        case .zoomEffects:   return 3
        case .visualEffects: return selectedVisualEffect?.parameters.count ?? 0
        case .faceFilters:   return selectedFaceFilter?.parameters.count ?? 0
        }
    }

    var editingTitle: String {
        switch selectedEffectCategory {
        case .visualEffects: return selectedVisualEffect?.rawValue ?? ""
        case .faceFilters:   return selectedFaceFilter?.rawValue ?? ""
        case .zoomEffects:   return selectedAnimatorType?.rawValue.uppercased() ?? "NO ZOOM"
        }
    }

    /// Opens the panel for the current selection, capturing the values to revert to.
    /// No-ops without a selection, which keeps the `isEditingEffect` invariant.
    func beginEditing() {
        guard hasEditableSelection else { return }
        editEntrySnapshot = currentSnapshot()
        isEditingEffect = true
    }

    /// Discards everything changed since the panel opened. Pushes no undo entry — from
    /// the user's point of view nothing happened.
    func cancelEditing() {
        guard let snapshot = editEntrySnapshot else {
            isEditingEffect = false
            return
        }
        editEntrySnapshot = nil
        restore(snapshot)
    }

    /// Keeps the changes and records **one** undo entry for the whole visit, regardless
    /// of how many parameters moved. Pushes the *entry* snapshot, not the current one —
    /// same pre-change discipline as `pushUndoCoalesced`.
    ///
    /// Pushed unconditionally rather than gated on an equality check: `GradientStops`
    /// holds `Color`s, whose equality LEARNINGS records as opaque, and an occasional
    /// no-op entry is a far smaller cost than a silently dropped one.
    func commitEditing() {
        if let snapshot = editEntrySnapshot {
            push(snapshot)
        }
        editEntrySnapshot = nil
        isEditingEffect = false
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

        push(currentSnapshot(gradientStopsOverride: previousStops))
    }

    /// Regenerates if the content warrants it, skipping when one is already in flight.
    ///
    /// Consolidates a block that was copy-pasted across eight `.onChange` handlers, the
    /// parameter drag-end path, and `restore()` — where the in-flight guard was
    /// *missing*, so an undo or a panel cancel landing on top of a running regeneration
    /// could stack two. That was the ROADMAP's open P1.
    func regenerateIfNeeded() {
        guard !isRegenerating else { return }
        if case .existingGif = content {
            hasModifiedSettings = true
            regenerateGIF()
        } else if isSplit {
            regenerateGIF()
        }
    }

    /// Debounced regeneration for controls that emit a stream of values instead of a
    /// discrete commit. Sliders regenerate on drag-end; `ColorPicker` has no such
    /// signal, so it coalesces here.
    func scheduleRegenerate(after delay: TimeInterval = 0.45) {
        regenerateWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.regenerateIfNeeded()
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

        // Navigation is not snapshotted, and a restore can clear the very selection the
        // panel is editing — so always leave the panel rather than risk an open panel
        // with no effect behind it.
        isEditingEffect = false
        editEntrySnapshot = nil

        updateCombinedPreview()

        if selectedEffectCategory == .faceFilters {
            detectFacesIfNeeded()
        }

        regenerateIfNeeded()
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
        // Tolerant comparison, not `!=`. Speed used to be one of four exact literals so
        // equality worked; with a continuous geometric slider, moving the knob off the
        // default and back yields 0.5000000000000001 and RESET would never disappear.
        let timingChanged = !ZoomPlayback.isDefaultSpeed(playbackSpeed)
            || !ZoomPlayback.isDefaultPause(pauseDuration)
        let base = selectedAnimatorType != .zoomIn || hasActiveModifier || timingChanged
            || hasVisualEffect || hasFaceFilter

        if case .newImage = content {
            return base || isSplit
        }
        return base
    }

    var speedLabel: String { ZoomPlayback.speedText(playbackSpeed) }

    var pauseLabel: String { ZoomPlayback.pauseText(pauseDuration) }

    // MARK: - Slider positions
    //
    // The panel's sliders work in 0…1; the generator works in multiples and seconds.
    // Exposing the conversion as properties means the view binds `$viewModel.speedUnit`
    // directly, with no bespoke `Binding` at the call site.

    var speedUnit: Double {
        get { ZoomPlayback.unit(speed: playbackSpeed) }
        set { playbackSpeed = ZoomPlayback.speed(unit: newValue) }
    }

    var pauseUnit: Double {
        get { ZoomPlayback.unit(pause: pauseDuration) }
        set { pauseDuration = ZoomPlayback.pause(unit: newValue) }
    }

    /// `.straight` is stored as nil everywhere else — `activeAnimator` treats the two
    /// identically — so it must not count as a modifier here either.
    var hasActiveModifier: Bool {
        selectedModifier != nil && selectedModifier != .straight
    }

    func resetEffects() {
        pushUndo()

        selectedAnimatorType = .zoomIn
        selectedModifier = nil
        playbackSpeed = ZoomPlayback.defaultSpeed
        pauseDuration = ZoomPlayback.defaultPause
        selectedVisualEffect = nil
        isEditingEffect = false
        editEntrySnapshot = nil
        parameterValues.removeAll()
        selectedEffectCategory = .zoomEffects
        previewImage = nil
        previewSourceCGImage = nil
        effectThumbnails = [:]
        faceFilterThumbnails = [:]
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
        } else {
            // Editing an existing GIF: clearing the state above changes nothing the user
            // can see until it is re-rendered, so RESET used to leave the old effects on
            // screen with SAVE disabled. Every other control routes through here; RESET
            // is the one that mutates the most and asked for it the least.
            regenerateIfNeeded()
        }
    }

    /// Commit point for any parameter slider: refresh the preview, then regenerate.
    ///
    /// This replaces four methods (intensity / size / face intensity / face second) that
    /// were byte-identical apart from calling `updateFaceFilterPreview()` instead of
    /// `updatePreviewImage()` — and those forward to the same `updateCombinedPreview()`,
    /// so the distinction never existed.
    func onParameterDragEnded() {
        updatePreviewImage()
        regenerateIfNeeded()
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
                } else {
                    // Here, not on the category change — see the doc comment.
                    self.generateFaceFilterThumbnails()
                }
            }
        }
    }

    func redetectFaces() {
        guard !isDetectingFaces else { return }
        guard let source = image ?? sourceImage else { return }

        detectedFaces = []
        selectedFaceIndex = nil
        // Thumbnails are cropped to a specific face; a new detection invalidates them.
        faceFilterThumbnails = [:]
        isDetectingFaces = true
        Task {
            let faces = await faceDetectionService.redetect(in: source)
            await MainActor.run {
                self.detectedFaces = faces
                self.isDetectingFaces = false
                if !faces.isEmpty {
                    self.generateFaceFilterThumbnails()
                }
            }
        }
    }

    func updateFaceFilterPreview() {
        updateCombinedPreview()
    }

    private var previewWorkItem: DispatchWorkItem?
    private var previewDebounceItem: DispatchWorkItem?
    private var previewSourceCGImage: CGImage?
    private let previewMaxDimension: Int = 650

    // MARK: - Effect Thumbnails

    /// Cached mini-thumbnails showing each visual effect applied to the user's photo.
    var effectThumbnails: [VisualEffectType: UIImage] = [:]

    /// The same, for face filters — cropped to the first detected face.
    ///
    /// Separate from `effectThumbnails` because it cannot be built at the same time:
    /// face effects need a `DetectedFace`, which arrives asynchronously and may never
    /// arrive at all.
    var faceFilterThumbnails: [FaceFilterType: UIImage] = [:]
    private var thumbnailSourceCGImage: CGImage?
    private let thumbnailDimension: Int = 120

    /// The un-effected photo behind the ZOOM cards, at preview resolution.
    ///
    /// Shares `getPreviewSourceCGImage`'s cache with the live canvas preview rather than
    /// decoding its own copy. Note these cards *magnify* it, unlike the 120pt effect
    /// thumbnails, so at a high user zoom it will read soft — acceptable, because the
    /// card is communicating a framing rather than image detail.
    var zoomPreviewImage: UIImage?

    /// What the ZOOM cards crop to.
    ///
    /// A published **snapshot**, not a live read of `currentScale` / `visibleRect`. Those
    /// are rewritten on every scroll-delegate callback, so reading them directly made all
    /// three cards re-crop continuously while the user was pinching — motion in the
    /// corner of the eye, competing with the photo they were framing. It now moves only
    /// when a gesture settles.
    private(set) var zoomCardFraming: ZoomFraming = .fallback

    /// Publishes the current canvas framing to the cards. Called when a canvas gesture
    /// comes to rest, and once after an existing GIF restores its saved zoom.
    func commitZoomCardFraming() {
        let resolved: ZoomFraming
        let scale = max(1, currentScale)
        if scale > 1.01 {
            resolved = ZoomFraming(scale: scale, center: CGPoint(x: visibleRect.midX, y: visibleRect.midY))
        } else {
            resolved = .fallback
        }
        guard resolved != zoomCardFraming else { return }
        withAnimation(.easeInOut(duration: AppConstants.Animation.quick)) {
            zoomCardFraming = resolved
        }
    }

    func generateZoomPreviewImage() {
        guard zoomPreviewImage == nil else { return }
        guard let source = image ?? sourceImage else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self,
                  let cgImage = self.getPreviewSourceCGImage(from: source) else { return }
            let preview = UIImage(cgImage: cgImage)
            DispatchQueue.main.async {
                self.zoomPreviewImage = preview
            }
        }
    }

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

    /// Builds face-filter card thumbnails, cropped to the first detected face.
    ///
    /// **Must be called from face detection's completion, never from the category
    /// change.** Fired early it runs with zero faces, returns thirteen unmodified
    /// copies of the photo, and the `isEmpty` memo below caches them for the rest of
    /// the session — the cards would silently show no effect at all.
    ///
    /// Cropped rather than whole-image because these effects are local: laser eyes and
    /// googly eyes are invisible on a full-frame thumbnail of a distant subject.
    func generateFaceFilterThumbnails() {
        guard faceFilterThumbnails.isEmpty else { return }
        guard let source = image ?? sourceImage else { return }
        guard let face = detectedFaces.first else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self,
                  let cgSource = self.getPreviewSourceCGImage(from: source) else { return }

            let base = CIImage(cgImage: cgSource)
            // Same conversion the live preview uses: detection ran on the full-size
            // source, the effect runs on the downscaled copy.
            let scaleX = base.extent.width / (source.size.width * source.scale)
            let scaleY = base.extent.height / (source.size.height * source.scale)
            let scaledFace = face.scaled(x: scaleX, y: scaleY)

            // ~1.8x the face box, so the crop carries enough surrounding context to
            // read as a portrait rather than a disembodied feature.
            let box = scaledFace.boundingBox
            let crop = box
                .insetBy(dx: -box.width * 0.4, dy: -box.height * 0.4)
                .intersection(base.extent)
            guard !crop.isNull, crop.width > 1, crop.height > 1 else { return }

            var results: [FaceFilterType: UIImage] = [:]
            for filter in FaceFilterType.allCases {
                let effect = filter.effect(intensity: 0.7, secondValue: 0.5, laserColor: .red)
                let output = effect.apply(
                    to: base,
                    face: scaledFace,
                    progress: filter.previewProgress,
                    frameIndex: 5
                )
                if let cgOut = self.ciContext.createCGImage(output, from: crop) {
                    results[filter] = UIImage(cgImage: cgOut)
                }
            }

            DispatchQueue.main.async {
                self.faceFilterThumbnails = results
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
                        let scaledFace = face.scaled(x: scaleX, y: scaleY)
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
                // Restored programmatically, so no gesture will publish it.
                self.commitZoomCardFraming()

                // `image` is nil for an existing GIF and `sourceImage` only lands here,
                // *after* the zoom tab has already appeared and asked for its thumbnail.
                // Without this retry the cards stayed blank until the user switched tabs
                // and came back, which re-fired the onAppear.
                self.generateZoomPreviewImage()

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
                pauseDuration: pauseDuration,
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
                pauseDuration: pauseDuration,
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
    
    // MARK: - Arrival hint

    /// Wording deliberately in the same voice as the ENHANCE nag ("Zoom in on the image
    /// first!"), because it is the same instruction arriving earlier.
    static let zoomHintMessage = "Pinch to zoom in on your subject"

    /// Set the first time the user works the canvas by hand. Latched rather than derived
    /// from `currentScale`, so the hint does not blink back when they pinch out to 1x
    /// again — by then they have discovered the gesture and the hint is noise.
    private(set) var hasUsedCanvas = false

    /// Whether to show the arrival hint. Nothing on the editor said that pinching is how
    /// the zoom target gets chosen, so a first-time user could reasonably tap ENHANCE and
    /// be told off for it.
    var showsZoomHint: Bool {
        // An existing GIF opens with its saved zoom already applied, so its user has
        // made this choice before and does not need telling.
        guard case .newImage = content else { return false }
        guard !hasUsedCanvas else { return false }
        // The canvas shows a finished GIF, not a pinchable image.
        guard !isSplit else { return false }
        // The panel owns the screen while it is open.
        guard !isEditingEffect else { return false }
        // Rides in with the rest of the controls rather than popping in mid-transition.
        guard showControls else { return false }
        return currentScale <= 1.0
    }

    func noteCanvasInteraction() {
        guard !hasUsedCanvas else { return }
        withAnimation(.easeInOut(duration: AppConstants.Animation.standard)) {
            hasUsedCanvas = true
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
