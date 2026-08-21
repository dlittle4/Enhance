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
    /// PIXELATE's cell shape. A typed field rather than an entry in `parameterValues`,
    /// which holds scalars only — see `PixelShape`.
    let pixelShape: PixelShape
    /// The text overlay, or `nil`. A whole value type per §6, so undo/redo, cancel and reset
    /// carry the text, its placement, style and animation as one unit.
    let textOverlay: TextOverlay?
}

@Observable
class EditorViewModel {
    var content: DetailContent
    private let gifGenerator: GIFGenerating

    /// Whether ENHANCE may run before the user has pinched the canvas — the
    /// `FeatureFlags.zoomOptional` experiment.
    ///
    /// Read once at construction rather than on every use. The editor is built fresh each time a
    /// photo is opened, so a toggle in Settings still takes effect on the next photo; and holding
    /// the answer here rather than reaching into `UserDefaults` from the generation path is what
    /// lets a test drive both branches without writing to the shared defaults, where a leaked
    /// value would silently change the behaviour of every later test in the process.
    let allowsGenerationWithoutZoom: Bool

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

    /// Which ZOOM card is selected when the editor opens, and what RESET returns to.
    ///
    /// ZOOM IN normally — the app's whole premise is a zoom. With the "make GIFs without zooming"
    /// experiment on, NO ZOOM instead: the point of that flag is that zooming is a choice, and
    /// opening on a zoom type would pre-make it.
    ///
    /// Also the baseline `hasNonDefaultSettings` compares against, so RESET does not appear on an
    /// untouched editor just because the default moved.
    var defaultAnimatorType: AnimatorType? {
        allowsGenerationWithoutZoom ? nil : .zoomIn
    }

    /// The PAUSE a GIF should start at, which depends on whether it zooms — see
    /// `ZoomPlayback.noZoomPause` for why the two differ.
    var defaultPauseDuration: Double {
        selectedAnimatorType == nil ? ZoomPlayback.noZoomPause : ZoomPlayback.defaultPause
    }

    /// Whether PAUSE is still at whatever the current selection's default is. Tolerant for the
    /// same reason `ZoomPlayback.isDefaultPause` is: a slider round-trip is not bit-exact.
    var isPauseAtDefault: Bool {
        abs(pauseDuration - defaultPauseDuration) < 1e-6
    }

    /// Applies a zoom choice the **user** made, carrying an untouched PAUSE to the new default.
    ///
    /// Only for direct selections — the zoom cards call this and nothing else does. Undo, redo
    /// and panel-cancel restore a whole `EditorSnapshot` including its pause, and routing them
    /// through here would let this rewrite the very value they are restoring.
    ///
    /// A pause the user has moved is left alone: the default follows the selection, an explicit
    /// choice does not.
    func selectAnimator(_ type: AnimatorType?) {
        let wasAtDefault = isPauseAtDefault
        selectedAnimatorType = type
        if wasAtDefault { pauseDuration = defaultPauseDuration }
    }
    var selectedModifier: ModifierType? = nil
    var isPlaying: Bool = true
    var playbackSpeed: Double = ZoomPlayback.defaultSpeed
    var pauseDuration: Double = ZoomPlayback.defaultPause
    var showSaveSheet: Bool = false
    var hasModifiedSettings: Bool = false
    var selectedEffectCategory: EffectCategory = .zoomEffects
    var selectedVisualEffect: VisualEffectType? = nil
    /// The single text overlay, `nil` until a preset is chosen. Whitespace-only text is not an
    /// active overlay (`TextOverlay.isActive`), so an empty draft never gates generation or
    /// counts as a non-default setting. Rendered as GIF stage 4 (§7.7) regardless of which
    /// category is active.
    var textOverlay: TextOverlay? = nil
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
    var pixelShape: PixelShape = .square
    var previewImage: UIImage? = nil
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Face Filters
    var detectedFaces: [DetectedFace] = []
    var selectedFaceIndex: Int? = nil
    var selectedFaceFilter: FaceFilterType? = nil
    var laserColor: LaserColor = .red
    var isDetectingFaces: Bool = false
    private let faceDetectionService = FaceDetectionService()

    // MARK: - Subject segmentation (ROADMAP §2f)

    /// The subject/background mask for the current photo, in its pixel space. `nil` means
    /// either "not segmented yet" or "this photo has no subject" — `hasSegmentedSubject`
    /// separates the two, because only the second should raise the toast.
    var subjectMask: CIImage? = nil
    /// Per-person instance masks aligned with `detectedFaces`, populated only when the
    /// HEAD MASK LAB approach flag asks for them.
    var personMasks: [CIImage?] = []
    /// BIG HEAD's union mask under the lab's chosen source; other subject effects keep
    /// `subjectMask` (always foreground).
    var bigHeadUnion: CIImage? = nil
    var isSegmentingSubject: Bool = false

    /// Whether segmentation has *run* for the current photo. Needed because `subjectMask`
    /// is `nil` in both the not-yet-run and the no-subject case, and the face tab's
    /// equivalent bug — re-toasting on every return, ROADMAP §4 — comes from exactly that
    /// conflation. This flag is what keeps the toast to once per photo.
    private var hasSegmentedSubject = false
    private let subjectSegmentationService = SubjectSegmentationService()

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

    /// True while the text keyboard is up. Lives here rather than in the view because
    /// `wantsLiveCanvas` needs it, and that answer has to be one the model and the view share.
    var isEnteringText = false

    /// Whether the canvas shows the editable photo instead of the rendered GIF.
    ///
    /// **One answer, consulted by both sides.** This used to be a view-local computed property
    /// while `updateCombinedPreview` made its own decision from a bare `isSplit`, and the two
    /// disagreed: the view chose the live canvas for the face tab while the model concluded no
    /// preview was needed because a GIF existed, so the canvas rendered the raw, un-zoomed photo
    /// with no effect on it. Both rules were defensible alone, which is exactly why the fix is to
    /// stop having two of them.
    ///
    /// Live only while a category is actually being *edited*. FACE FILTERS needs it so face boxes
    /// are tappable and the effect is visible while a filter is being chosen; TEXT needs it while
    /// typing or positioning. Once the panel is confirmed, the GIF takes the canvas back and
    /// ENHANCE shows the rendered result, as every other category does.
    var wantsLiveCanvas: Bool {
        switch selectedEffectCategory {
        case .faceFilters: return isEditingEffect
        case .text:        return isEnteringText || isEditingEffect
        default:           return false
        }
    }

    /// Whether the editable canvas is **actually on screen** right now.
    ///
    /// `wantsLiveCanvas` says which canvas a *category* asks for; this answers what is displayed,
    /// which also depends on whether a GIF exists to show instead. Everything that decorates the
    /// live canvas — face boxes, the detection spinner — must read this rather than re-deriving it,
    /// because a decoration shown over the GIF, or hidden while the photo is up, is the same class
    /// of bug as the canvas itself picking wrong.
    ///
    /// This is the second half of that consolidation. The first pass converted the two sites that
    /// choose the canvas and left two more gating on the `isSplit` proxy, so after ENHANCE the face
    /// tab came back with the effect visible but no tappable boxes — a face could no longer be
    /// chosen. Consolidation is not finished until every reader is converted.
    var showsLiveCanvas: Bool {
        switch content {
        case .existingGif:
            return wantsLiveCanvas && sourceImage != nil
        case .newImage:
            // The GIF wins only when there is one *and* no category is asking to edit.
            return !(isSplit && generatedGifURL != nil && !wantsLiveCanvas)
        }
    }

    /// True for the span of a direct-manipulation gesture on the text overlay (drag, pinch,
    /// rotate — possibly several at once). Global undo/redo are disabled while it is set, the
    /// same way `isEditingEffect` disables them, so an undo mid-drag cannot fight the gesture.
    var isTextGestureActive = false

    /// State as it was when the panel opened, so the back chevron can discard.
    private var editEntrySnapshot: EditorSnapshot?

    /// State captured at the *start* of a gesture session, pushed once when it ends — one undo
    /// entry per session no matter how many recognizers took part (§8.6).
    private var textGestureEntrySnapshot: EditorSnapshot?

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
        case .text:          return textOverlay?.isActive == true
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
        // COLOR and STYLE are built directly (like zoom's speed/pause/motion), plus the
        // per-preset tunable; none are declared `EffectParameter`s, so this stays empty.
        case .text:          return []
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
        // FILL — which now carries its own swatches rather than pushing them into a second,
        // blank-labelled row — and the per-preset tunable, plus FROM for the presets that
        // travel. STYLE is held back until decoration renders correctly.
        //
        // The old counts were 3 and 4; folding the swatches into FILL took one off each. The
        // note that used to live here, about four rows overflowing an SE 3 into a scroll where a
        // slider drag would fight it, is doubly obsolete: `ParameterSliderRow` scoped its drag to
        // the knob on 2026-08-12, so the conflict cannot arise, and ROADMAP §1a accepts the
        // scroll regardless.
        case .text:          return (textOverlay?.animation.usesFromRow == true) ? 3 : 2
        }
    }

    var editingTitle: String {
        switch selectedEffectCategory {
        case .visualEffects: return selectedVisualEffect?.rawValue ?? ""
        case .faceFilters:   return selectedFaceFilter?.rawValue ?? ""
        // Matches the card that opened the panel. The other three categories call their
        // no-effect card ORIGINAL; ZOOM calls it NO ZOOM, because "original" describes a picture
        // and what is being switched off here is a movement *(user's call, 2026-08-13)*.
        case .zoomEffects:   return selectedAnimatorType?.rawValue.uppercased() ?? "NO ZOOM"
        case .text:          return textOverlay?.animation.rawValue ?? "TEXT"
        }
    }

    /// Opens the panel for the current selection, capturing the values to revert to.
    /// No-ops without a selection, which keeps the `isEditingEffect` invariant.
    func beginEditing() {
        guard hasEditableSelection else { return }
        editEntrySnapshot = currentSnapshot()
        isEditingEffect = true
        // Opening the panel can flip `wantsLiveCanvas`, and the live canvas is only worth showing
        // with a preview on it — otherwise the face tab renders the raw photo. Refreshing here is
        // what keeps the two in step at the moment the canvas swaps.
        updateCombinedPreview()
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
        // Confirming hands the canvas back to the GIF, so the static preview is no longer wanted.
        updateCombinedPreview()
    }

    /// Opens a direct-manipulation gesture session, capturing the pre-gesture state. Called from
    /// the first recognizer's `.began` (the 0→1 transition of `TextGestureSession`'s counter), so
    /// a simultaneous drag+pinch+rotate still captures exactly one entry snapshot.
    func beginTextGesture() {
        guard !isTextGestureActive else { return }
        isTextGestureActive = true
        textGestureEntrySnapshot = currentSnapshot()
    }

    /// Closes the gesture session. Pushes the pre-gesture snapshot (pre-change discipline, matching
    /// `commitEditing`) only if the overlay actually changed, then requests one regeneration — so a
    /// cancelled or no-op gesture litters neither the undo stack nor the GIF queue.
    func endTextGesture() {
        guard isTextGestureActive else { return }
        isTextGestureActive = false
        defer { textGestureEntrySnapshot = nil }

        if let entry = textGestureEntrySnapshot, entry.textOverlay != textOverlay {
            push(entry)
            regenerateIfNeeded()
        }
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
        // A regeneration already in flight must not swallow this request. Record that another is
        // wanted and re-fire it when the current one finishes (see `drainPendingRegeneration`).
        // Dropping it here was an open P1: with slider commits it bit occasionally, but direct
        // manipulation of a text overlay fires this constantly, and a silently-absent edit reads
        // as the app ignoring the user. See FEATURE-TEXT-EFFECTS.md §8.7.
        guard !isRegenerating else { regeneratePending = true; return }
        if case .existingGif = content {
            hasModifiedSettings = true
            regenerateGIF()
        } else if isSplit {
            regenerateGIF()
        }
    }

    /// Set when `regenerateIfNeeded` is called during an in-flight regeneration; drained at every
    /// completion path of `regenerateGIF` so the last-requested state always reaches the GIF.
    /// Read-only outside this type — only `regenerateIfNeeded` sets it and only the drain clears it.
    private(set) var regeneratePending = false

    /// Re-fires a regeneration that was queued while one was running. Called from every exit of
    /// `regenerateGIF` — success and both error paths — after `isRegenerating` is cleared, so the
    /// guard in `regenerateIfNeeded` sees the door open. Internal rather than private so the
    /// queue-and-refire cycle can be driven deterministically in a test without the async hop.
    func drainPendingRegeneration() {
        guard regeneratePending else { return }
        regeneratePending = false
        regenerateIfNeeded()
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
            gradientStops: gradientStopsOverride ?? gradientStops,
            pixelShape: pixelShape,
            textOverlay: textOverlay
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
        pixelShape = snapshot.pixelShape
        gradientStops = snapshot.gradientStops
        textOverlay = snapshot.textOverlay

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

    /// Toggle the target face: tapping the selected one reverts to all-faces, tapping a
    /// different one isolates it.
    func toggleFaceSelection(_ index: Int) {
        if selectedFaceIndex == index {
            selectedFaceIndex = nil
            clearSingleFaceFilterIfNeeded()
        } else {
            selectedFaceIndex = index
        }
    }

    /// Reads the value store directly by well-known id — deliberately *not* via
    /// `filter.parameters`, which allocates an array and would run on every debounced
    /// preview update.
    var activeFaceEffect: FaceEffect? {
        guard let filter = selectedFaceFilter else { return nil }

        let built = filter.effect(
            intensity: value(EffectParameter.intensityID, for: filter),
            secondValue: value(EffectParameter.secondaryID, for: filter),
            laserColor: laserColor
        )

        // BIG HEAD enlarges the head's real outline, so it needs segmentation — and like ECHO,
        // the factory has none. Without a mask it returns the frame untouched rather than
        // falling back to the bump-distortion version, which was rejected on look.
        if let bigHead = built as? BigHeadEffect {
            // The shared union mask, fetched async when the card was selected — no Vision call
            // happens here; this is read on every preview rebuild. When the lab's PERSON MASKS
            // approach is on, the per-face instances fetched alongside the union ride in too,
            // matched by normalized face centre so the preview's downsampling cannot desync them.
            guard let source = image ?? sourceImage else {
                return bigHead.withMask(bigHeadUnion ?? subjectMask)
            }
            let size = CGSize(width: source.size.width * source.scale,
                              height: source.size.height * source.scale)
            let perFace: [BigHeadEffect.PerFaceMask] = zip(detectedFaces, personMasks).compactMap {
                face, mask in
                guard let mask, size.width > 0, size.height > 0 else { return nil }
                // AUTO FIT's scan: one small render per face, here on the already-computed
                // masks rather than in any frame loop. Cheap enough to run unconditionally —
                // the toggle decides whether headMask *uses* the result, so flipping it in the
                // lab needs no refetch.
                let derived = HeadGeometryScanner.scan(mask: mask, face: face, context: ciContext)
                return BigHeadEffect.PerFaceMask(
                    normCenter: CGPoint(x: face.faceCenter.x / size.width,
                                        y: face.faceCenter.y / size.height),
                    mask: mask,
                    neckNormY: derived.neckNormY,
                    crownNormY: derived.crownNormY
                )
            }
            return bigHead.withMask(bigHeadUnion ?? subjectMask, perFace: perFace)
        }
        return built
    }

    /// Same hot-path rule as `activeFaceEffect`: direct dict reads, never `.parameters`.
    var activeVisualEffectList: [VisualEffect] {
        guard let effect = selectedVisualEffect else { return [] }
        let options = EffectOptions(
            size: value(EffectParameter.sizeID, for: effect),
            tertiary: value(EffectParameter.tertiaryID, for: effect),
            quaternary: value(EffectParameter.quaternaryID, for: effect),
            quinary: value(EffectParameter.quinaryID, for: effect),
            tintColor: tintColor,
            gradientStops: gradientStops,
            pixelShape: pixelShape
        )
        var built = effect.effect(intensity: value(EffectParameter.intensityID, for: effect), options: options)

        // ECHO draws *from* the subject mask rather than being masked by it, so it is the one
        // effect the factory cannot finish building — the factory has no segmentation.
        if let echo = built as? SubjectEchoEffect {
            built = echo.withMask(subjectMask)
        }

        // The one choke point both the preview and the GIF read, so wrapping here covers
        // both paths — there is no second place to keep in sync.
        guard effect.parameters.contains(where: { $0.id == EffectParameter.backgroundOnlyID }),
              EffectParameter.isOn(value(EffectParameter.backgroundOnlyID, for: effect))
        else { return [built] }

        return [BackgroundOnlyEffect(wrapped: built, mask: subjectMask)]
    }

    /// The zoom, with the motion modifier layered over it.
    ///
    /// The no-zoom case used to return a bare `StaticAnimator()` and **discard the modifier**.
    /// That was unreachable while one of the three zoom types was always selected, and ROADMAP
    /// §3f flagged it as the thing to fix first if the state was ever re-exposed. The ORIGINAL
    /// card re-exposes it: SHAKE over a held framing is a real request — `hasEffectsWithoutZoom`
    /// counts the modifier as reason enough to generate — so dropping it would have produced a
    /// still for a user who explicitly asked for movement.
    ///
    /// The modifier composes over whichever base is in play, which is what the two-`guard` shape
    /// obscured by returning early on a condition the modifier does not depend on.
    var activeAnimator: Animator {
        let base: Animator = selectedAnimatorType?.animator ?? StaticAnimator()
        guard let mod = selectedModifier, mod != .straight else { return base }
        return CompositeAnimator(base: base, modifier: mod.modifier)
    }

    var hasNonDefaultSettings: Bool {
        let hasVisualEffect = selectedVisualEffect != nil
        let hasFaceFilter = selectedFaceFilter != nil
        let hasText = textOverlay?.isActive == true
        // Tolerant comparison, not `!=`. Speed used to be one of four exact literals so
        // equality worked; with a continuous geometric slider, moving the knob off the
        // default and back yields 0.5000000000000001 and RESET would never disappear.
        // PAUSE compares against the *selection's* default, not a fixed 1s — a no-zoom GIF
        // starts at 3s, and comparing to the wrong baseline would show RESET on an untouched
        // editor and hide it on a genuinely edited one.
        let timingChanged = !ZoomPlayback.isDefaultSpeed(playbackSpeed) || !isPauseAtDefault
        let base = selectedAnimatorType != defaultAnimatorType || hasActiveModifier || timingChanged
            || hasVisualEffect || hasFaceFilter || hasText

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

        selectedAnimatorType = defaultAnimatorType
        selectedModifier = nil
        playbackSpeed = ZoomPlayback.defaultSpeed
        // After the animator, which is what `defaultPauseDuration` reads.
        pauseDuration = defaultPauseDuration
        selectedVisualEffect = nil
        isEditingEffect = false
        editEntrySnapshot = nil
        parameterValues.removeAll()
        selectedEffectCategory = .zoomEffects
        previewImage = nil
        previewSourceCGImage = nil
        effectThumbnails = [:]
        faceFilterThumbnails = [:]
        // `originalThumbnail` is deliberately kept — it depends on the photo alone, which RESET
        // cannot change. The face crop goes, because detection does.
        originalFaceThumbnail = nil
        textThumbnailFrames = [:]
        thumbnailSourceCGImage = nil
        selectedFaceFilter = nil
        selectedFaceIndex = nil
        laserColor = .red
        tintColor = .red
        pixelShape = .square
        gradientStops = .default
        textOverlay = nil
        detectedFaces = []
        faceDetectionService.clearCache()
        clearSubjectMask()

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

    /// Segment the current photo, once. Called when BACKGROUND ONLY is switched on — the
    /// first moment a mask is actually needed — rather than on photo load, which would
    /// charge every user a segmentation pass for a control most will never touch.
    ///
    /// Follows the face precedent on absence (ROADMAP §1g, user's call): a toast, with the
    /// cards left live. It does **not** repeat that feature's bug of re-toasting on every
    /// visit; `hasSegmentedSubject` gates it to once per photo.
    /// The lab settings the last segmentation fetch was made under. When the user changes a
    /// data-dependent toggle in HEAD MASK LAB and comes back, the fetch must rerun — without
    /// this, "apply lab settings to the app" would silently mean "apply them after the next
    /// photo change", which reads as the lab being broken *(user request, 2026-08-21: test lab
    /// settings on any photo through the real editor)*.
    private var segmentationFetchKey: String?

    private var currentSegmentationKey: String {
        let t = HeadMaskTuningStore.shared.tuning
        return "\(t.unionSource.rawValue)|\(t.usePersonMasks)"
    }

    func segmentSubjectIfNeeded() {
        guard !isSegmentingSubject else { return }
        guard !(hasSegmentedSubject && segmentationFetchKey == currentSegmentationKey) else { return }
        guard let source = image ?? sourceImage else { return }

        isSegmentingSubject = true
        let key = currentSegmentationKey
        let tuning = HeadMaskTuningStore.shared.tuning
        Task {
            // The shared union for ECHO and BACKGROUND ONLY is always the foreground request —
            // those effects are outside the lab's remit and must not change under it.
            let mask = await subjectSegmentationService.subjectMask(for: source)
            // BIG HEAD's union follows the lab's source choice. For .foreground this is the
            // same cached mask, so it costs nothing extra.
            let bigHeadUnion = tuning.unionSource == .foreground
                ? mask
                : ((try? subjectSegmentationService.subjectMask(for: source, source: tuning.unionSource)) ?? mask)
            // The lab's person-mask approach needs per-face instances; fetched in the same pass
            // so toggling the setting never adds a second loading stall.
            let person = tuning.usePersonMasks
                ? await subjectSegmentationService.personMasks(
                    for: source,
                    at: detectedFaces.map(\.faceCenter),
                    radii: detectedFaces.map { $0.faceWidth * 0.5 }
                )
                : []
            await MainActor.run {
                self.subjectMask = mask
                self.bigHeadUnion = bigHeadUnion
                self.personMasks = person
                self.hasSegmentedSubject = true
                self.segmentationFetchKey = key
                self.isSegmentingSubject = false
                if mask == nil {
                    self.showToast("NO SUBJECT DETECTED")
                }
                // The mask changes what the selected effect renders, so the preview built
                // before it arrived is now stale.
                self.updateCombinedPreview()
            }
        }
    }

    /// Pay the segmentation model's one-time load before the user can ask for it.
    ///
    /// Measured on device (ROADMAP §1g): the first request costs ~214 ms against 15–30 ms warm.
    /// Called when the VISUAL tab opens rather than on photo load — that is one tap earlier than
    /// BACKGROUND ONLY can possibly be reached, and it keeps the cost off users who never open
    /// the tab at all. Cheap to call repeatedly; it does not touch the cache, so the photo the
    /// user actually picked still gets its own segmentation pass.
    func prewarmSegmentation() {
        guard !hasSegmentedSubject else { return }
        subjectSegmentationService.prewarm()
    }

    /// Drop the mask when the photo changes. Without this a new photo would composite
    /// against the previous one's silhouette, which reads as a segmentation failure.
    func clearSubjectMask() {
        subjectMask = nil
        personMasks = []
        bigHeadUnion = nil
        segmentationFetchKey = nil
        hasSegmentedSubject = false
        subjectSegmentationService.clearCache()
    }

    func redetectFaces() {
        guard !isDetectingFaces else { return }
        guard let source = image ?? sourceImage else { return }

        detectedFaces = []
        selectedFaceIndex = nil
        // Thumbnails are cropped to a specific face; a new detection invalidates them.
        faceFilterThumbnails = [:]
        originalFaceThumbnail = nil
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

    /// The photo with nothing applied, at card-thumbnail size: the ORIGINAL card's backdrop on
    /// the IMAGE and TEXT carousels.
    ///
    /// Deliberately *not* cleared by `resetEffects`, unlike every other thumbnail here. Those
    /// are invalidated because they depend on state RESET clears; this one depends only on the
    /// photo, which cannot change for the life of the editor.
    var originalThumbnail: UIImage?

    /// The same, cropped to the first detected face, for the FACE carousel — whose every other
    /// card is a face crop, so a full-frame ORIGINAL there would not read as the same photo.
    ///
    /// Built alongside `faceFilterThumbnails` and invalidated wherever those are, since the crop
    /// is only meaningful against the detection that produced it.
    var originalFaceThumbnail: UIImage?

    /// Renders `originalThumbnail` once. Called from each carousel's `onAppear` rather than the
    /// editor's, for the reason `extractSourceImage` documents: an existing GIF's source lands
    /// asynchronously, well after the editor itself has appeared.
    func generateOriginalThumbnail() {
        guard originalThumbnail == nil else { return }
        guard let source = image ?? sourceImage else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self, let thumb = self.getThumbnailSourceCGImage(from: source) else { return }
            let plain = UIImage(cgImage: thumb)
            DispatchQueue.main.async { self.originalThumbnail = plain }
        }
    }

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

    /// Card previews for the text presets: the photo with a placeholder word on it, rendered as a
    /// short **frame sequence** so each card plays its own entrance rather than showing one still.
    ///
    /// A still could not distinguish these presets honestly — POP and SPIN both read as "big text"
    /// at their peak, and TYPEWRITER's whole character is the reveal over time. Playing them is the
    /// only way a card answers "what does this do".
    ///
    /// Rendered through `TextTileCompositor`, the same code the GIF uses, so a card cannot promise
    /// something the export does not deliver. Cheap enough to precompute: the source thumbnail is
    /// 120px, so a frame is ~57KB and the whole set is a few MB.
    var textThumbnailFrames: [TextAnimationType: [UIImage]] = [:]

    /// Frames per card loop, and how many of those hold on the settled text at the end. The hold
    /// matters — without it the loop restarts the instant it finishes and never reads as arriving.
    static let textPreviewFrameCount = 16
    static let textPreviewHoldFrames = 5

    /// Progress for a given frame: the entrance spread across the moving frames, then settled.
    static func textPreviewProgress(frame: Int) -> CGFloat {
        let moving = textPreviewFrameCount - textPreviewHoldFrames
        guard frame < moving else { return 1 }
        return CGFloat(frame) / CGFloat(max(1, moving - 1))
    }

    func generateTextThumbnails() {
        guard textThumbnailFrames.isEmpty else { return }
        guard let source = image ?? sourceImage else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self, let thumb = self.getThumbnailSourceCGImage(from: source) else { return }

            let side = CGFloat(min(thumb.width, thumb.height))
            var results: [TextAnimationType: [UIImage]] = [:]

            for preset in TextAnimationType.allCases {
                var overlay = TextOverlay.makeDefault(animation: preset, text: "TEXT", seed: 7)
                // Larger than the editor default: the card is a fraction of the canvas, and text at
                // 0.12 of it is unreadable at card size.
                overlay.fontSize = 0.22
                guard let raster = TextRasterizer.prepare(overlay: overlay, pixelSide: side) else {
                    continue
                }
                var frames: [UIImage] = []
                for index in 0..<Self.textPreviewFrameCount {
                    let composed = TextTileCompositor.composite(
                        raster, overlay: overlay,
                        progress: Self.textPreviewProgress(frame: index), over: thumb
                    )
                    frames.append(UIImage(cgImage: composed))
                }
                results[preset] = frames
            }

            DispatchQueue.main.async { self.textThumbnailFrames = results }
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

            // The same crop with no effect on it, so the ORIGINAL card is the *comparison* the
            // rest of the carousel is judged against rather than a differently-framed photo.
            let plain = self.ciContext.createCGImage(base, from: crop).map(UIImage.init(cgImage:))

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
                self.originalFaceThumbnail = plain
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

        // Once a GIF exists it should be on screen, not a stale static preview — *unless* the
        // canvas is showing the live photo, in which case the preview is what makes the effect
        // visible. Consulting the shared property is what keeps this in step with the view.
        if isSplit, case .newImage = content, !wantsLiveCanvas {
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
                    // One batch call with every face already scaled into preview space — the
                    // scaling stays here with the caller (it owns the coordinate space), and
                    // effects whose faces interact get to see all of them at once.
                    let scaledFaces = faces.map { $0.scaled(x: scaleX, y: scaleY) }
                    result = faceEffect.apply(
                        to: result, faces: scaledFaces, progress: previewProg, frameIndex: 5
                    )

                    // Rasterise the face pass before any visual effect sees it — the same thing
                    // the GIF path does, for the same reason.
                    //
                    // Face effects build their glow with `CIAdditionCompositing` — LAZER EYES
                    // stacks five layers per eye, THIRD EYE its rays — which pushes the brightest
                    // pixels well past 1.0. Straight to screen that is invisible, because the
                    // rasteriser normalises on the way out. A visual effect chained *after* it
                    // does arithmetic on those values instead: SLICE SHIFT composites bands with
                    // source-over, and over-range premultiplied pixels came out **black** exactly
                    // where the glow was brightest.
                    //
                    // `GIFGenerator.faceEffectedSource` renders a CGImage between the two stages,
                    // which is why the GIF was always correct. Doing the same here is what makes
                    // the two paths agree — the divergence was the bug, not either stage alone.
                    //
                    // **Not `CIColorClamp`.** That was tried first and it dims the effect: it
                    // clips in the linear working space, which measured max red 255 → 215 and
                    // removed every pixel above 240, so the preview lost the glow's hot core
                    // while the GIF kept it. Rasterising normalises through the display transfer
                    // function instead and matches the GIF exactly. An approximation of what the
                    // export does is not the same as doing what the export does.
                    if let flattened = ciContext.createCGImage(result, from: result.extent) {
                        result = CIImage(cgImage: flattened)
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
    
    init(
        content: DetailContent,
        gifGenerator: GIFGenerating = GIFGenerator(),
        allowsGenerationWithoutZoom: Bool = FeatureFlags.zoomOptional
    ) {
        self.content = content
        self.gifGenerator = gifGenerator
        self.allowsGenerationWithoutZoom = allowsGenerationWithoutZoom
        // After the stored property above, which `defaultAnimatorType` reads.
        self.selectedAnimatorType = allowsGenerationWithoutZoom ? nil : .zoomIn
        // And after the animator, which decides which pause default applies.
        self.pauseDuration = allowsGenerationWithoutZoom
            ? ZoomPlayback.noZoomPause
            : ZoomPlayback.defaultPause
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

                // Restore the authored text, so reopening lands on the words the user wrote rather
                // than an empty keyboard over a title already baked into the pixels.
                if let id = self.existingGifAssetIdentifier, self.textOverlay == nil {
                    self.textOverlay = Self.loadTextOverlay(for: id)
                }

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
                // Same retry reason as the zoom preview above: for an existing GIF the source
                // lands after the carousel has already asked for its thumbnails.
                if self.selectedEffectCategory == .text {
                    self.generateTextThumbnails()
                }

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
            || textOverlay?.isActive == true
    }

    /// The zoom the GIF is generated with: normally the user's own pinch.
    ///
    /// The exception is the `allowsGenerationWithoutZoom` experiment. With it on, a zoom type
    /// selected and no pinch behind it, generation uses `ZoomFraming.fallback` instead of the
    /// untouched 1× canvas.
    ///
    /// **That substitution is what makes the experiment mean anything.** At 1× the generator's
    /// two endpoint framings — `fullViewParams` and `userZoomParams` — are the same framing, so
    /// ZOOM IN would interpolate between a value and itself and hand back a still. Lifting the
    /// nag without this would trade "the app refuses" for "the app agrees and does nothing",
    /// which is worse.
    ///
    /// The fallback is not an arbitrary default either: it is exactly the framing the ZOOM cards
    /// already show while no pinch has been made (`zoomCardFraming`), so the GIF that comes out
    /// matches the card the user tapped.
    /// The whole frame. At 1× the visible region *is* the entire image, by definition.
    static let fullFrameRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    var generationFraming: (scale: CGFloat, rect: CGRect) {
        // Un-zoomed: the full frame, **never** whatever `visibleRect` happens to hold.
        //
        // That field is published by the canvas's scroll delegate, and a callback arriving before
        // the scroll view has bounds could leave it describing a zero-sized region off-centre —
        // which the generator renders as the image shifted right and down (fixed at source in
        // `ImageCanvasView.syncBindings`). Deriving it here instead of trusting the field means a
        // future regression in that publisher cannot move an un-zoomed GIF off-centre again: at
        // 1× there is only one correct answer and this states it.
        guard currentScale > 1.0 else {
            guard allowsGenerationWithoutZoom, selectedAnimatorType != nil else {
                return (currentScale, Self.fullFrameRect)
            }
            return (ZoomFraming.fallback.scale, ZoomFraming.fallback.rect)
        }
        return (currentScale, visibleRect)
    }

    func generateGIF() {
        guard let imageToUse = image else {
            showToast("Error: No image selected")
            return
        }

        let needsZoom = selectedAnimatorType != nil
        if needsZoom && currentScale <= 1.0 && !allowsGenerationWithoutZoom {
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
        
        let framing = generationFraming
        generationScale = framing.scale
        generationVisibleRect = framing.rect

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
                detectedFaces: activeFaces,
                textOverlay: textOverlay,
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
                detectedFaces: activeFaces,
                textOverlay: textOverlay,
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
                        self.drainPendingRegeneration()
                    }
                } catch {
                    DispatchQueue.main.async {
                        withAnimation { self.isRegenerating = false }
                        self.showToast("Error creating GIF")
                        self.drainPendingRegeneration()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    withAnimation { self.isRegenerating = false }
                    self.showToast("Error creating GIF")
                    self.drainPendingRegeneration()
                }
            }
        }
    }
    
    func saveGIFToLibrary(photoManager: PhotoManager) {
        // `generatedGifURL`, never a fallback to `existingGifURL`. Saving on an existing GIF
        // means saving a *new copy of the edit*; if regeneration never produced a file, the
        // old fallback silently saved the untouched original instead. `updateOriginalGIF`
        // already requires the generated file for the same reason — this makes SAVE match.
        guard let url = generatedGifURL, generatedGIF != nil else {
            showToast("Error: No GIF to save")
            return
        }
        
        showToast("Saving GIF...")
        
        photoManager.saveGifToMyGifsAlbum(fileURL: url) { [weak self] success, newIdentifier, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if success {
                    // File this edit's settings against the asset that was just created. Without
                    // the identifier there was no key, so a first-time save lost its zoom framing
                    // and — worse — dropped its text: reopening rebuilt from the deliberately
                    // textless frame 0, so the next regeneration erased a title the user could
                    // still see baked into the pixels.
                    if let newIdentifier {
                        self.persistZoomParams(for: newIdentifier)
                        self.persistTextOverlay(for: newIdentifier)
                        // Marks the cell the gallery should reveal once the editor is out of the
                        // way. Set here rather than in the gallery because this is the only place
                        // that knows *which* asset is new.
                        photoManager.justSavedIdentifier = newIdentifier
                    }
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
        
        // Deliberately *not* persisting against `identifier` here: this path deletes that asset a
        // line below, so anything written against it is orphaned the moment it lands — it only
        // accumulates dead UserDefaults keys. The settings are filed against the replacement
        // asset's identifier in the save completion instead.
        showToast("Updating GIF...")
        
        photoManager.deleteGifAsset(identifier: identifier) { [weak self] success, error in
            guard let self else { return }
            if success {
                photoManager.saveGifToMyGifsAlbum(fileURL: url) { [weak self] saveSuccess, newIdentifier, saveError in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if saveSuccess {
                            // "Update original" is a delete followed by a create, so the asset comes
                            // back with a *new* identifier. Settings written against the old one
                            // above are now orphaned — re-file them here, or reopening the updated
                            // GIF finds nothing and loses its zoom framing and its text.
                            if let newIdentifier {
                                self.persistZoomParams(for: newIdentifier)
                                self.persistTextOverlay(for: newIdentifier)
                                // The replacement asset is new, so it arrives in the grid the
                                // same way a first-time save does and earns the same reveal.
                                photoManager.justSavedIdentifier = newIdentifier
                            }
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

    /// Same instruction as the ENHANCE nag ("Zoom in on the image first!"), just arriving
    /// earlier. Kept short so the toast pill fits comfortably over the image container
    /// rather than stretching across it; naming the subject was detail the gesture hint
    /// did not need.
    static let zoomHintMessage = "Pinch to zoom in"

    /// Set the first time the user works the canvas by hand. Latched rather than derived
    /// from `currentScale`, so the hint does not blink back when they pinch out to 1x
    /// again — by then they have discovered the gesture and the hint is noise.
    private(set) var hasUsedCanvas = false

    /// Whether to show the arrival hint. Nothing on the editor said that pinching is how
    /// the zoom target gets chosen, so a first-time user could reasonably tap ENHANCE and
    /// be told off for it.
    /// Latches once the user touches the text — same discipline as `hasUsedCanvas`. Set from the
    /// gesture session and from reopening the keyboard, so any real interaction retires the hint.
    private(set) var hasUsedTextOverlay = false

    func noteTextInteraction() {
        guard !hasUsedTextOverlay else { return }
        hasUsedTextOverlay = true
    }

    /// Set when the user picks a preset card. Navigation state, like `hasUsedCanvas` — not
    /// snapshotted, because undo should not resurrect a hint.
    private(set) var hasChosenTextPreset = false

    func noteTextPresetChosen() { hasChosenTextPreset = true }

    /// Tells the user how to get back into the words, now that opening the TEXT tab no longer
    /// throws them into the keyboard.
    ///
    /// **Waits for a preset to be chosen.** Merely arriving in the carousel is too early: choosing
    /// an effect is the prerequisite for editing, so a hint about editing greets the user before
    /// the thing it describes is reachable. After a preset is picked the advice is actionable, and
    /// it is the moment the keyboard *stops* opening by itself — which is exactly when someone
    /// would otherwise wonder how to change the words.
    ///
    /// Silent while the keyboard or the panel owns the screen, since it would be describing
    /// something the user is already doing, and retired for good once the text is touched.
    static let textHintMessage = "DOUBLE TAP TO EDIT TEXT"

    var showsTextHint: Bool {
        guard selectedEffectCategory == .text else { return false }
        guard hasChosenTextPreset else { return false }
        guard textOverlay?.isActive == true else { return false }
        guard !hasUsedTextOverlay else { return false }
        guard !isEditingEffect else { return false }
        guard showControls else { return false }
        return true
    }

    var showsZoomHint: Bool {
        // Silent while zooming is optional. This hint is the ENHANCE nag arriving early — it
        // exists so a first-time user is not told off for tapping ENHANCE without pinching. With
        // the experiment on there is nothing to be told off for, so instructing them to pinch
        // is advice for a requirement that no longer exists *(user's call, 2026-08-13)*.
        guard !allowsGenerationWithoutZoom else { return false }
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

    // MARK: - Text Overlay Persistence

    /// The text overlay is the one effect whose *recipe* has to survive a round trip.
    ///
    /// Everything else can be re-chosen from a card, but text is authored — losing the words means
    /// retyping them. Reopening a saved GIF otherwise gave a blank editor over pixels that already
    /// had a title baked in, and adding a preset started from an empty keyboard.
    ///
    /// Storing it is safe because the first frame of every entrance is deliberately empty (§6), so
    /// the source image reconstructed from frame 0 carries no text and regeneration cannot double
    /// it up. Keyed by asset identifier, exactly as the zoom parameters are.
    private static let textOverlayPrefix = "textOverlay_"

    static func saveTextOverlay(_ overlay: TextOverlay?, for identifier: String) {
        guard !identifier.isEmpty else { return }
        let key = "\(textOverlayPrefix)\(identifier)"
        guard let overlay, overlay.isActive,
              let data = try? JSONEncoder().encode(overlay) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func loadTextOverlay(for identifier: String) -> TextOverlay? {
        guard !identifier.isEmpty,
              let data = UserDefaults.standard.data(forKey: "\(textOverlayPrefix)\(identifier)")
        else { return nil }
        return try? JSONDecoder().decode(TextOverlay.self, from: data)
    }

    func persistTextOverlay(for identifier: String) {
        Self.saveTextOverlay(textOverlay, for: identifier)
    }
}
