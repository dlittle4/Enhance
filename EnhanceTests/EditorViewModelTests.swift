import Testing
import UIKit
@testable import Enhance

/// Lightweight stub that records calls without doing real GIF work.
private struct StubGIFGenerator: GIFGenerating {
    var shouldSucceed: Bool = true
    
    func generateGIF(from image: UIImage, currentScale: CGFloat, visibleRect: CGRect, animator: Animator, speed: Double, pauseDuration: Double, visualEffects: [VisualEffect], faceEffect: FaceEffect? = nil, detectedFaces: [DetectedFace] = [], textOverlay: TextOverlay? = nil) -> Data? {
        guard shouldSucceed else { return nil }
        return Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
    }
    
    func saveTempGIF(_ gifData: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stub.gif")
        try? gifData.write(to: url)
        return url
    }
}

struct EditorViewModelTests {
    
    private func makeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        return renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }
    
    // MARK: - Initial state
    
    @Test func newImage_initialState_isReady() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        
        #expect(vm.enhanceState == .ready)
        #expect(vm.isGenerating == false)
        #expect(vm.generatedGIF == nil)
        #expect(vm.generatedGifURL == nil)
        #expect(vm.showControls == false)
    }
    
    @Test func existingGif_initialState_isShare() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.gif")
        try? Data().write(to: url)
        let vm = EditorViewModel(content: .existingGif(url, 0, "test-id"), gifGenerator: StubGIFGenerator())
        
        #expect(vm.enhanceState == .share)
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - Defaults & hasNonDefaultSettings
    
    @Test func hasNonDefaultSettings_withDefaults_isFalse() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        #expect(vm.hasNonDefaultSettings == false)
    }
    
    @Test func hasNonDefaultSettings_afterChangingAnimator_isTrue() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedAnimatorType = .zoomOut
        #expect(vm.hasNonDefaultSettings == true)
    }
    
    @Test func hasNonDefaultSettings_afterChangingModifier_isTrue() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedModifier = .shake
        #expect(vm.hasNonDefaultSettings == true)
    }
    
    @Test func hasNonDefaultSettings_afterChangingSpeed_isTrue() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.playbackSpeed = 2.0
        #expect(vm.hasNonDefaultSettings == true)
    }
    
    @Test func hasNonDefaultSettings_afterSelectingVisualEffect_isTrue() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedVisualEffect = .chromaShift
        #expect(vm.hasNonDefaultSettings == true)
    }

    // MARK: - resetEffects
    
    @Test func resetEffects_restoresDefaults() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedAnimatorType = .pulse
        vm.selectedModifier = .spiral
        vm.playbackSpeed = 3.0
        vm.selectedVisualEffect = .halftone
        vm.selectedEffectCategory = .visualEffects
        
        vm.resetEffects()
        
        #expect(vm.selectedAnimatorType == .zoomIn)
        // Phase 13c made modifiers deselectable, so the reset state is nil rather
        // than an explicit .straight pass-through.
        #expect(vm.selectedModifier == nil)
        #expect(vm.playbackSpeed == 0.5)
        #expect(vm.selectedVisualEffect == nil)
        #expect(vm.selectedEffectCategory == .zoomEffects)
    }
    
    @Test func resetEffects_forNewImage_clearsGeneratedGIF() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.generatedGIF = Data([1, 2, 3])
        vm.generatedGifURL = URL(fileURLWithPath: "/tmp/test.gif")
        vm.enhanceState = .share
        
        vm.resetEffects()
        
        #expect(vm.generatedGIF == nil)
        #expect(vm.generatedGifURL == nil)
        #expect(vm.enhanceState == .ready)
    }
    
    @Test func resetEffects_forExistingGif_keepsEnhanceState() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keep.gif")
        try? Data().write(to: url)
        let vm = EditorViewModel(content: .existingGif(url, 0, "id"), gifGenerator: StubGIFGenerator())
        
        vm.selectedAnimatorType = .pulse
        vm.resetEffects()
        
        #expect(vm.enhanceState == .share)
        try? FileManager.default.removeItem(at: url)
    }

    /// RESET on an existing GIF used to clear the state without re-rendering, so the
    /// old effects stayed on screen and SAVE stayed disabled.
    ///
    /// Asserts the flag rather than the rendered GIF on purpose: `regenerateIfNeeded`
    /// sets `hasModifiedSettings` *before* calling `regenerateGIF()`, which bails while
    /// `sourceImg` is nil because `extractSourceImage` is async. So this is true the
    /// moment reset returns, with no waiting and no timing assumption.
    @Test func resetEffects_onExistingGif_marksSettingsModified() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("regen.gif")
        try? Data().write(to: url)
        let vm = EditorViewModel(content: .existingGif(url, 0, "id"), gifGenerator: StubGIFGenerator())

        #expect(!vm.hasModifiedSettings)
        vm.resetEffects()

        #expect(vm.hasModifiedSettings)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Regeneration guard (Stage E, §8.7)

    private func regenReadyViewModel() -> EditorViewModel {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("regen-guard-\(UUID().uuidString).gif")
        try? Data().write(to: url)
        return EditorViewModel(content: .existingGif(url, 0, "id"), gifGenerator: StubGIFGenerator())
    }

    /// The P1 fix: an edit made while a regeneration is in flight must be queued, not dropped.
    /// Before this, the `guard !isRegenerating else { return }` swallowed it silently — with
    /// direct manipulation that would read as the app ignoring the user.
    @Test func regenerateIfNeeded_whileInFlight_queuesInsteadOfDropping() {
        let vm = regenReadyViewModel()
        vm.isRegenerating = true // simulate a regeneration already running

        #expect(!vm.regeneratePending)
        vm.regenerateIfNeeded()
        #expect(vm.regeneratePending, "the edit must be recorded, not silently dropped")
    }

    /// Draining after the in-flight run finishes re-fires the queued request exactly once and
    /// clears the flag, so the last-requested state reaches the GIF.
    @Test func drainPendingRegeneration_afterInFlight_refiresTheQueuedRequest() {
        let vm = regenReadyViewModel()
        vm.isRegenerating = true
        vm.regenerateIfNeeded() // queued
        #expect(vm.regeneratePending)

        vm.isRegenerating = false // the running regeneration completes
        vm.drainPendingRegeneration()

        #expect(!vm.regeneratePending, "the queued request must be consumed")
        // The re-fire ran regenerateIfNeeded again: on an existing GIF that marks settings modified
        // before dispatching, so this is observable synchronously the moment the drain returns.
        #expect(vm.hasModifiedSettings)
    }

    /// With nothing queued, draining is a no-op — it must not fire a spurious extra regeneration.
    @Test func drainPendingRegeneration_withNothingQueued_doesNothing() {
        let vm = regenReadyViewModel()
        #expect(!vm.regeneratePending)
        vm.drainPendingRegeneration()
        #expect(!vm.regeneratePending)
        #expect(!vm.hasModifiedSettings)
    }

    // MARK: - showsZoomHint

    private func makeHintReadyViewModel() -> EditorViewModel {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        // The editor fades its controls in after the open transition; the hint rides in
        // with them rather than popping in mid-transition.
        vm.showControls = true
        return vm
    }

    @Test func showsZoomHint_onArrival_isTrue() {
        #expect(makeHintReadyViewModel().showsZoomHint)
    }

    @Test func showsZoomHint_beforeControlsAppear_isFalse() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        #expect(vm.showControls == false)
        #expect(!vm.showsZoomHint)
    }

    @Test func showsZoomHint_afterTheUserWorksTheCanvas_isFalse() {
        let vm = makeHintReadyViewModel()
        vm.noteCanvasInteraction()
        #expect(!vm.showsZoomHint)
    }

    /// The load-bearing one. Latched rather than derived from `currentScale`, so pinching
    /// back out to 1x does not bring the hint back — by then the user has found the
    /// gesture and repeating the instruction is just noise.
    @Test func showsZoomHint_afterZoomingBackToOne_staysHidden() {
        let vm = makeHintReadyViewModel()

        vm.noteCanvasInteraction()
        vm.currentScale = 3.0
        #expect(!vm.showsZoomHint)

        vm.currentScale = 1.0
        #expect(!vm.showsZoomHint, "the hint must not blink back once the gesture is known")
    }

    @Test func showsZoomHint_whileZoomed_isFalse() {
        let vm = makeHintReadyViewModel()
        vm.currentScale = 2.0
        #expect(!vm.showsZoomHint)
    }

    /// An existing GIF opens with its saved zoom already applied, so its user has made
    /// this choice before.
    @Test func showsZoomHint_forExistingGif_isFalse() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hint.gif")
        try? Data().write(to: url)
        let vm = EditorViewModel(content: .existingGif(url, 0, "id"), gifGenerator: StubGIFGenerator())
        vm.showControls = true
        vm.currentScale = 1.0

        #expect(!vm.showsZoomHint)
        try? FileManager.default.removeItem(at: url)
    }

    /// The panel owns the screen while open, and the canvas is not the thing being edited.
    @Test func showsZoomHint_whileEditingAnEffect_isFalse() {
        let vm = makeHintReadyViewModel()
        vm.beginEditing()

        #expect(vm.isEditingEffect)
        #expect(!vm.showsZoomHint)
    }

    /// Once a GIF exists the canvas shows it rather than a pinchable image.
    @Test func showsZoomHint_afterGenerating_isFalse() {
        let vm = makeHintReadyViewModel()
        vm.enhanceState = .share

        #expect(vm.isSplit)
        #expect(!vm.showsZoomHint)
    }

    @Test func noteCanvasInteraction_isIdempotent() {
        let vm = makeHintReadyViewModel()
        vm.noteCanvasInteraction()
        vm.noteCanvasInteraction()
        #expect(vm.hasUsedCanvas)
        #expect(!vm.showsZoomHint)
    }

    // MARK: - zoomCardFraming

    /// With no zoom set the two endpoint framings are identical, so all three cards would
    /// show the same untouched photo. The fallback is what keeps them distinguishable.
    @Test func zoomCardFraming_withoutAUserZoom_isTheFallback() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())

        #expect(vm.currentScale == 1.0)
        #expect(vm.zoomCardFraming == .fallback)
        #expect(vm.zoomCardFraming.scale > 1.5, "identical stills would say nothing")
    }

    /// The point of the snapshot: `currentScale` and `visibleRect` are rewritten on every
    /// scroll-delegate callback, so cards reading them live would re-crop continuously
    /// under the user's fingers.
    @Test func zoomCardFraming_doesNotTrackTheCanvasUntilTheGestureSettles() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())

        vm.currentScale = 3.0
        vm.visibleRect = CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.2)

        #expect(vm.zoomCardFraming == .fallback, "mid-gesture values must not reach the cards")
    }

    @Test func commitZoomCardFraming_publishesTheUsersFraming() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())

        vm.currentScale = 3.0
        vm.visibleRect = CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.2)
        vm.commitZoomCardFraming()

        #expect(vm.zoomCardFraming.scale == 3.0)
        #expect(abs(vm.zoomCardFraming.center.x - 0.2) < 1e-9)
        #expect(abs(vm.zoomCardFraming.center.y - 0.6) < 1e-9)
    }

    /// Pinching back out to 1x should return the cards to the fallback rather than leave
    /// them cropped to a zoom that no longer exists.
    @Test func commitZoomCardFraming_afterZoomingBackOut_returnsToTheFallback() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())

        vm.currentScale = 3.0
        vm.commitZoomCardFraming()
        #expect(vm.zoomCardFraming != .fallback)

        vm.currentScale = 1.0
        vm.commitZoomCardFraming()
        #expect(vm.zoomCardFraming == .fallback)
    }

    // MARK: - zoomPreviewImage

    /// The zoom tab asks for its thumbnail in `onAppear`. For an existing GIF that runs
    /// *before* `sourceImage` has finished loading, so the call is a no-op — and the tab
    /// never asks again. The cards stayed blank until the user switched tabs and came
    /// back, which re-fired the onAppear.
    ///
    /// Pins the invariant the fix depends on: an early no-op must leave the build
    /// retryable, so the retry fired when `sourceImage` lands actually produces an image.
    @Test func generateZoomPreviewImage_afterAnEarlyNoOp_stillBuildsWhenTheSourceArrives() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoomthumb.gif")
        try? Data().write(to: url)
        let vm = EditorViewModel(content: .existingGif(url, 0, "id"), gifGenerator: StubGIFGenerator())

        // What the zoom tab does on appear, before the source has loaded.
        #expect(vm.image == nil && vm.sourceImage == nil)
        vm.generateZoomPreviewImage()
        #expect(vm.zoomPreviewImage == nil)

        // What the source-image load now does when it completes.
        vm.sourceImage = makeImage()
        vm.generateZoomPreviewImage()

        // Polled rather than slept: the build hops to a utility queue and back.
        //
        // The budget is deliberately generous. At 2s this failed intermittently — not because the
        // build never happened, but because several simulators and builds share this machine (four
        // sessions work this repo in parallel) and a starved utility queue can miss a tight window.
        // A flaky test is worse than a slow one: it trains you to re-run rather than read. The
        // assertion is unchanged — the image must still be built — only the patience is longer, and
        // the loop exits the moment it appears, so the happy path costs the same.
        var built = false
        for _ in 0..<200 {
            if vm.zoomPreviewImage != nil { built = true; break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(built, "an early no-op must not prevent a later build")

        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - activeAnimator
    
    @Test func activeAnimator_withStraight_returnsBaseAnimator() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedModifier = .straight
        vm.selectedAnimatorType = .zoomIn
        
        let animator = vm.activeAnimator
        #expect(animator is ZoomInAnimator)
    }
    
    @Test func activeAnimator_withShake_returnsComposite() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedModifier = .shake
        
        let animator = vm.activeAnimator
        #expect(animator is CompositeAnimator)
    }
    
    // MARK: - activeVisualEffectList
    
    @Test func activeVisualEffectList_withNone_isEmpty() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        #expect(vm.activeVisualEffectList.isEmpty)
    }
    
    @Test func activeVisualEffectList_withSelection_hasOneElement() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedVisualEffect = .chromaShift
        #expect(vm.activeVisualEffectList.count == 1)
    }
    
    // MARK: - isSaveEnabled
    
    @Test func isSaveEnabled_forNewImage_requiresSplit() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        #expect(vm.isSaveEnabled == false)
        
        vm.enhanceState = .share
        #expect(vm.isSaveEnabled == true)
    }
    
    @Test func isSaveEnabled_forExistingGif_requiresModifiedSettings() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("save.gif")
        try? Data().write(to: url)
        let vm = EditorViewModel(content: .existingGif(url, 0, "id"), gifGenerator: StubGIFGenerator())
        
        #expect(vm.isSaveEnabled == false)
        
        vm.hasModifiedSettings = true
        #expect(vm.isSaveEnabled == true)
        
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - isSplit & buttonText
    
    @Test func isSplit_reflectsEnhanceState() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        
        #expect(vm.isSplit == false)
        vm.enhanceState = .share
        #expect(vm.isSplit == true)
        vm.enhanceState = .saved
        #expect(vm.isSplit == true)
    }
    
    @Test func buttonText_matchesState() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        
        #expect(vm.buttonText == "ENHANCE")
        vm.enhanceState = .generating
        #expect(vm.buttonText == "GENERATING...")
        vm.enhanceState = .share
        #expect(vm.buttonText == "SHARE")
    }
    
    // MARK: - showToast
    
    @Test func showToast_setsMessageAndFlag() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.showToast("Test message")
        
        #expect(vm.saveMessage == "Test message")
        #expect(vm.showSaveMessage == true)
    }
    
    // MARK: - Content accessors
    
    @Test func image_returnsImageForNewContent() {
        let img = makeImage()
        let vm = EditorViewModel(content: .newImage(img), gifGenerator: StubGIFGenerator())
        #expect(vm.image != nil)
    }
    
    @Test func image_returnsNilForExistingGif() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("x.gif")
        try? Data().write(to: url)
        let vm = EditorViewModel(content: .existingGif(url, 0, "id"), gifGenerator: StubGIFGenerator())
        #expect(vm.image == nil)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Parameter value store

    @Test func parameterValue_unsetReturnsDefault() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        #expect(vm.value(EffectParameter.intensityID, for: VisualEffectType.fisheye) == 0.5)
        #expect(vm.value(EffectParameter.sizeID, for: VisualEffectType.dither, default: 0.25) == 0.25)
    }

    @Test func parameterValue_roundTrips() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.setValue(0.8, EffectParameter.sizeID, for: VisualEffectType.dither)
        #expect(vm.value(EffectParameter.sizeID, for: VisualEffectType.dither) == 0.8)
    }

    /// Each effect keeps its own values, so re-selecting an effect finds what you left
    /// it at rather than the previous effect's setting.
    @Test func parameterValues_areIndependentPerEffect() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.setValue(0.1, EffectParameter.intensityID, for: VisualEffectType.fisheye)
        vm.setValue(0.9, EffectParameter.intensityID, for: VisualEffectType.dither)

        #expect(vm.value(EffectParameter.intensityID, for: VisualEffectType.fisheye) == 0.1)
        #expect(vm.value(EffectParameter.intensityID, for: VisualEffectType.dither) == 0.9)
    }

    /// The cross-family case the key namespace exists for, exercised through the store
    /// rather than just the key builder.
    @Test func parameterValues_doNotCrossBetweenVisualAndFaceEffects() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.setValue(0.2, EffectParameter.intensityID, for: VisualEffectType.fisheye)
        vm.setValue(0.7, EffectParameter.intensityID, for: FaceFilterType.fisheye)

        #expect(vm.value(EffectParameter.intensityID, for: VisualEffectType.fisheye) == 0.2)
        #expect(vm.value(EffectParameter.intensityID, for: FaceFilterType.fisheye) == 0.7)
    }

    @Test func resetEffects_clearsAllParameterValues() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.setValue(0.9, EffectParameter.intensityID, for: VisualEffectType.dither)
        vm.setValue(0.1, EffectParameter.intensityID, for: FaceFilterType.googlyEyes)

        vm.resetEffects()

        #expect(vm.parameterValues.isEmpty)
        #expect(vm.value(EffectParameter.intensityID, for: VisualEffectType.dither) == 0.5)
    }

    /// Undo carries the whole parameter store, so a value change is undoable even though
    /// it is no longer a named stored property.
    @Test func undo_restoresParameterValues() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedVisualEffect = .dither
        vm.setValue(0.2, EffectParameter.sizeID, for: VisualEffectType.dither)

        vm.pushUndo()
        vm.setValue(0.9, EffectParameter.sizeID, for: VisualEffectType.dither)
        #expect(vm.value(EffectParameter.sizeID, for: VisualEffectType.dither) == 0.9)

        vm.undo()
        #expect(vm.value(EffectParameter.sizeID, for: VisualEffectType.dither) == 0.2)
    }

    // MARK: - Text overlay (Stage F model plumbing)

    private func activeOverlay(_ text: String = "HELLO",
                              animation: TextAnimationType = .pop) -> TextOverlay {
        TextOverlay(text: text, center: CGPoint(x: 0.5, y: 0.5), fontSize: 0.12, angle: 0,
                    font: .silkscreenBold, color: .white, alignment: .center,
                    decoration: .shadow, animation: animation, seed: 5)
    }

    @Test func hasNonDefaultSettings_withActiveTextOverlay_isTrue() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        #expect(vm.hasNonDefaultSettings == false)
        vm.textOverlay = activeOverlay()
        #expect(vm.hasNonDefaultSettings == true)
    }

    /// Whitespace-only text is not an active overlay, so it must not read as a non-default setting
    /// — otherwise RESET would appear for an empty draft the user never really made.
    @Test func hasNonDefaultSettings_withWhitespaceOnlyText_isFalse() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.textOverlay = activeOverlay("   \n ")
        #expect(vm.hasNonDefaultSettings == false)
    }

    @Test func resetEffects_clearsTextOverlay() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.textOverlay = activeOverlay()
        vm.resetEffects()
        #expect(vm.textOverlay == nil)
    }

    /// The overlay is a snapshot field, so undo restores it as one unit with everything else.
    @Test func undo_restoresTextOverlay() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.textOverlay = activeOverlay("FIRST")

        vm.pushUndo()
        vm.textOverlay = activeOverlay("SECOND")
        #expect(vm.textOverlay?.text == "SECOND")

        vm.undo()
        #expect(vm.textOverlay?.text == "FIRST")
    }

    /// A gesture session that changes the overlay records exactly one undo entry, and undo
    /// restores the pre-gesture state.
    @Test func textGesture_committingAChange_recordsOneUndoEntry() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.textOverlay = activeOverlay("HELLO")
        #expect(vm.canUndo == false)

        vm.beginTextGesture()
        vm.textOverlay?.center = CGPoint(x: 0.3, y: 0.4) // as a drag would
        vm.endTextGesture()

        #expect(vm.canUndo == true)
        #expect(vm.isTextGestureActive == false)
        vm.undo()
        #expect(vm.textOverlay?.center == CGPoint(x: 0.5, y: 0.5))
    }

    /// A gesture that ends where it began — a tap that selected but moved nothing, or a cancelled
    /// pinch — must not litter the undo stack.
    @Test func textGesture_withNoChange_pushesNoUndoEntry() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.textOverlay = activeOverlay("HELLO")

        vm.beginTextGesture()
        vm.endTextGesture()

        #expect(vm.canUndo == false)
    }

    // MARK: - Text overlay persistence

    /// Text is authored, not chosen from a card, so losing it on a round trip means retyping it.
    /// The recipe has to survive being saved and reopened.
    @Test func textOverlay_roundTripsThroughPersistence() throws {
        let id = "text-persist-\(UUID().uuidString)"
        var overlay = activeOverlay("SUNSET", animation: .slide)
        overlay.color = .pink
        overlay.center = CGPoint(x: 0.3, y: 0.7)
        overlay.fontSize = 0.18
        overlay.tuning = 0.8

        EditorViewModel.saveTextOverlay(overlay, for: id)
        let restored = try #require(EditorViewModel.loadTextOverlay(for: id))

        #expect(restored == overlay, "every authored field must survive the round trip")
        UserDefaults.standard.removeObject(forKey: "textOverlay_\(id)")
    }

    /// Clearing the text must clear the stored recipe too, or a removed title would come back on
    /// the next open.
    @Test func textOverlay_persistingNil_clearsTheStoredRecipe() {
        let id = "text-clear-\(UUID().uuidString)"
        EditorViewModel.saveTextOverlay(activeOverlay("GONE"), for: id)
        #expect(EditorViewModel.loadTextOverlay(for: id) != nil)

        EditorViewModel.saveTextOverlay(nil, for: id)
        #expect(EditorViewModel.loadTextOverlay(for: id) == nil)
    }

    /// A whitespace-only overlay is not an overlay, so it must not be stored either.
    @Test func textOverlay_whitespaceOnly_isNotPersisted() {
        let id = "text-blank-\(UUID().uuidString)"
        EditorViewModel.saveTextOverlay(activeOverlay("   "), for: id)
        #expect(EditorViewModel.loadTextOverlay(for: id) == nil)
    }

    // MARK: - Effect edit session

    /// The panel refuses to open without a selection *on the tabs that need one*, which
    /// is what keeps the "never editing with nothing selected" invariant.
    @Test func beginEditing_onImageTab_withoutSelection_doesNotOpen() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedEffectCategory = .visualEffects
        vm.beginEditing()
        #expect(vm.isEditingEffect == false)
    }

    @Test func beginEditing_onFaceTab_withoutSelection_doesNotOpen() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedEffectCategory = .faceFilters
        vm.beginEditing()
        #expect(vm.isEditingEffect == false)
    }

    /// Zoom is the exception: speed, pause and motion are meaningful even with no zoom
    /// type selected, so the panel always has something to edit.
    @Test func beginEditing_onZoomTab_alwaysOpens() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedEffectCategory = .zoomEffects
        vm.selectedAnimatorType = nil
        vm.beginEditing()
        #expect(vm.isEditingEffect == true)
    }

    /// A stale selection on another tab must not open a blank panel here.
    @Test func beginEditing_onImageTab_ignoresAFaceSelection() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedFaceFilter = .googlyEyes
        vm.selectedEffectCategory = .visualEffects
        vm.beginEditing()
        #expect(vm.isEditingEffect == false)
    }

    @Test func beginEditing_withSelection_opens() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedEffectCategory = .visualEffects
        vm.selectedVisualEffect = .dither
        vm.beginEditing()
        #expect(vm.isEditingEffect == true)
    }

    /// Back discards: values return to what they were on entry, and *no* undo entry is
    /// recorded, because from the user's point of view nothing happened.
    @Test func cancelEditing_revertsValuesAndPushesNoUndoEntry() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedVisualEffect = .dither
        vm.setValue(0.3, EffectParameter.intensityID, for: VisualEffectType.dither)
        #expect(vm.canUndo == false)

        vm.beginEditing()
        vm.setValue(0.8, EffectParameter.intensityID, for: VisualEffectType.dither)
        vm.cancelEditing()

        #expect(vm.isEditingEffect == false)
        #expect(vm.value(EffectParameter.intensityID, for: VisualEffectType.dither) == 0.3)
        #expect(vm.canUndo == false, "cancel must not record history")
    }

    /// Confirm keeps the changes and records exactly one entry for the whole visit,
    /// however many parameters moved. The trailing `canUndo == false` is the part that
    /// proves "exactly one" rather than merely "at least one".
    @Test func commitEditing_keepsValuesAndPushesExactlyOneUndoEntry() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedVisualEffect = .dither
        vm.setValue(0.3, EffectParameter.intensityID, for: VisualEffectType.dither)
        vm.setValue(0.4, EffectParameter.sizeID, for: VisualEffectType.dither)

        vm.beginEditing()
        vm.setValue(0.8, EffectParameter.intensityID, for: VisualEffectType.dither)
        vm.setValue(0.9, EffectParameter.sizeID, for: VisualEffectType.dither)
        vm.commitEditing()

        #expect(vm.isEditingEffect == false)
        #expect(vm.value(EffectParameter.intensityID, for: VisualEffectType.dither) == 0.8)
        #expect(vm.value(EffectParameter.sizeID, for: VisualEffectType.dither) == 0.9)
        #expect(vm.canUndo == true)

        vm.undo()
        #expect(vm.value(EffectParameter.intensityID, for: VisualEffectType.dither) == 0.3)
        #expect(vm.value(EffectParameter.sizeID, for: VisualEffectType.dither) == 0.4)
        #expect(vm.canUndo == false, "a visit must record one entry, not one per parameter")
    }

    /// A restore can clear the very selection the panel is editing, so it must always
    /// close the panel rather than leave it open over nothing.
    @Test func undo_whileEditing_closesThePanel() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedVisualEffect = .dither
        vm.pushUndo()
        vm.beginEditing()
        #expect(vm.isEditingEffect == true)

        vm.undo()
        #expect(vm.isEditingEffect == false)
    }

    @Test func resetEffects_closesThePanel() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedVisualEffect = .dither
        vm.beginEditing()
        #expect(vm.isEditingEffect == true)

        vm.resetEffects()
        #expect(vm.isEditingEffect == false)
    }

    // MARK: - Panel content resolution

    /// PIXELATE's SHAPE is typed state, so undo/redo has to carry it explicitly — it is not
    /// in `parameterValues` and would otherwise survive an undo unchanged.
    @Test func pixelShape_roundTripsThroughUndo() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedEffectCategory = .visualEffects
        vm.selectedVisualEffect = .pixelate
        #expect(vm.pixelShape == .square)

        vm.pushUndo()
        vm.pixelShape = .hex
        vm.undo()
        #expect(vm.pixelShape == .square, "undo must restore the shape")

        vm.redo()
        #expect(vm.pixelShape == .hex, "redo must reapply it")
    }

    @Test func resetEffects_restoresTheDefaultPixelShape() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.pixelShape = .hex
        vm.resetEffects()
        #expect(vm.pixelShape == .square)
    }

    @Test func editingTitleAndParameters_resolveFromActiveCategory() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())

        vm.selectedEffectCategory = .visualEffects
        vm.selectedVisualEffect = .dither
        #expect(vm.editingTitle == "DITHER")
        // INTENSITY / SCALE / LEVELS — LEVELS was split out of INTENSITY in the control
        // audit, so this list is three long rather than two.
        #expect(vm.editingParameters.map(\.id) == [
            EffectParameter.intensityID, EffectParameter.sizeID, EffectParameter.tertiaryID
        ])

        vm.selectedEffectCategory = .faceFilters
        vm.selectedFaceFilter = .lazerEyes
        #expect(vm.editingTitle == "LAZER EYES")
        #expect(vm.editingParameters.count == 3)
    }

    /// The zoom panel builds its rows directly rather than from a declared list, so
    /// `editingParameters` stays empty — but the title comes from the animator, and the
    /// raw values are mixed case ("Zoom In") so the uppercasing is load-bearing.
    @Test func editingTitle_forZoomCategory_isTheUppercasedAnimatorName() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedEffectCategory = .zoomEffects
        vm.selectedVisualEffect = .dither

        vm.selectedAnimatorType = .zoomIn
        #expect(vm.editingParameters.isEmpty)
        #expect(vm.editingTitle == "ZOOM IN")

        vm.selectedAnimatorType = .pulse
        #expect(vm.editingTitle == "PULSE")

        vm.selectedAnimatorType = nil
        #expect(vm.editingTitle == "NO ZOOM")
    }

    // MARK: - Modifier normalisation

    @Test func modifierSelection_mapsNilToStraight() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        #expect(vm.selectedModifier == nil)
        #expect(vm.modifierSelection == .straight)
    }

    /// LINEAR displays as selected but must never be *stored* — nil stays canonical, so
    /// hasActiveModifier, hasEffectsWithoutZoom and resetEffects keep working untouched.
    @Test func modifierSelection_writingStraightStoresNil() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedModifier = .shake
        vm.modifierSelection = .straight
        #expect(vm.selectedModifier == nil)
        #expect(vm.modifierSelection == .straight)
    }

    @Test func modifierSelection_roundTripsRealModifiers() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        for mod in [ModifierType.shake, .spiral] {
            vm.modifierSelection = mod
            #expect(vm.selectedModifier == mod)
            #expect(vm.modifierSelection == mod)
        }
    }

    // MARK: - Face filter thumbnails

    /// The specific trap: fired before detection completes there are no faces, the
    /// generator would produce thirteen unmodified copies of the photo, and the
    /// `isEmpty` memo would cache them for the session — cards silently showing no
    /// effect. The guard must leave the cache untouched so a later run can fill it.
    @Test func faceFilterThumbnails_withNoFaces_leaveCacheEmpty() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        #expect(vm.detectedFaces.isEmpty)

        vm.generateFaceFilterThumbnails()

        #expect(vm.faceFilterThumbnails.isEmpty, "an empty cache must stay fillable")
    }

    @Test func resetEffects_clearsBothThumbnailCaches() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.effectThumbnails[.dither] = makeImage()
        vm.faceFilterThumbnails[.googlyEyes] = makeImage()

        vm.resetEffects()

        #expect(vm.effectThumbnails.isEmpty)
        #expect(vm.faceFilterThumbnails.isEmpty)
    }

    /// A new detection targets a different face, so thumbnails cropped to the old one
    /// must not survive it.
    @Test func redetectFaces_invalidatesFaceThumbnails() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.faceFilterThumbnails[.lazerEyes] = makeImage()

        vm.redetectFaces()

        #expect(vm.faceFilterThumbnails.isEmpty)
    }

    // MARK: - Continuous speed and pause

    /// The regression this guards shows up as "RESET never goes away". Speed used to be
    /// one of four exact literals so `!= 0.5` worked; the geometric map makes the
    /// round-trip 0.5000000000000001, and an equality check would leave RESET visible
    /// forever once the knob had been moved and put back.
    @Test func hasNonDefaultSettings_afterSpeedRoundTrip_isFalse() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        #expect(vm.hasNonDefaultSettings == false)

        let original = vm.speedUnit
        vm.speedUnit = 0.9
        #expect(vm.hasNonDefaultSettings == true)

        vm.speedUnit = original
        #expect(vm.hasNonDefaultSettings == false, "returning to the default position must clear RESET")
    }

    @Test func speedUnit_roundTripsThroughTheViewModel() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.speedUnit = 0.5
        #expect(abs(vm.playbackSpeed - 1.0) < 1e-9, "midpoint should be 1x")
        #expect(abs(vm.speedUnit - 0.5) < 1e-9)

        vm.speedUnit = 1.0
        #expect(abs(vm.playbackSpeed - 4.0) < 1e-9, "top of the track should reach the generator's clamp")
    }

    /// A whole second of pause was the old minimum; zero is now reachable and meaningful.
    @Test func pauseDuration_reachesZero() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.pauseUnit = 0
        #expect(vm.pauseDuration == 0)
        vm.pauseUnit = 1
        #expect(vm.pauseDuration == 5.0)
    }

    /// Pins the `Int(playbackSpeed)` truncation that used to render 1.5 as "1X".
    @Test func speedLabel_showsRealUnitsNotTheLatticeInteger() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.playbackSpeed = 1.5
        #expect(vm.speedLabel == "1.5X")
        vm.pauseDuration = 2.5
        #expect(vm.pauseLabel == "2.5S")
    }

    /// pauseDuration changed Int -> Double, and it travels through EditorSnapshot.
    @Test func undo_restoresFractionalPause() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.pauseDuration = 1.0
        vm.pushUndo()
        vm.pauseDuration = 3.75

        vm.undo()
        #expect(vm.pauseDuration == 1.0)
    }

    /// `.straight` is stored as nil everywhere else, so it must not light up RESET.
    @Test func hasNonDefaultSettings_withStraightModifier_isFalse() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedModifier = .straight
        #expect(vm.hasActiveModifier == false)
        #expect(vm.hasNonDefaultSettings == false)

        vm.selectedModifier = .shake
        #expect(vm.hasActiveModifier == true)
        #expect(vm.hasNonDefaultSettings == true)
    }

    // MARK: - Face selection

    @Test func toggleFaceSelection_isolatesAndReverts() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.toggleFaceSelection(1)
        #expect(vm.selectedFaceIndex == 1)
        vm.toggleFaceSelection(1)  // tapping the selected one reverts to all-faces
        #expect(vm.selectedFaceIndex == nil)
    }
}

