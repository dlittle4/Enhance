import Testing
import UIKit
@testable import Enhance

/// Lightweight stub that records calls without doing real GIF work.
private struct StubGIFGenerator: GIFGenerating {
    var shouldSucceed: Bool = true
    
    func generateGIF(from image: UIImage, currentScale: CGFloat, visibleRect: CGRect, animator: Animator, speed: Double, pauseDuration: Double, visualEffects: [VisualEffect], faceEffect: FaceEffect? = nil, detectedFaces: [DetectedFace] = []) -> Data? {
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

    // MARK: - Parameter defaults

    @Test func effectSize_defaultsToHalf() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        #expect(vm.effectSize == 0.5)
    }


    // MARK: - resetEffects
    
    @Test func resetEffects_restoresDefaults() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedAnimatorType = .pulse
        vm.selectedModifier = .spiral
        vm.playbackSpeed = 3.0
        vm.selectedVisualEffect = .halftone
        vm.selectedEffectCategory = .visualEffects
        vm.effectSize = 0.9
        
        vm.resetEffects()
        
        #expect(vm.selectedAnimatorType == .zoomIn)
        // Phase 13c made modifiers deselectable, so the reset state is nil rather
        // than an explicit .straight pass-through.
        #expect(vm.selectedModifier == nil)
        #expect(vm.playbackSpeed == 0.5)
        #expect(vm.selectedVisualEffect == nil)
        #expect(vm.selectedEffectCategory == .zoomEffects)
        #expect(vm.effectSize == 0.5)
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

    /// The legacy shims must address the same storage as the typed API, or the view and
    /// the effect pipeline would disagree while both look correct.
    @Test func legacyShims_addressTheSameStorageAsTypedAPI() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedVisualEffect = .fisheye

        vm.effectIntensity = 0.3
        #expect(vm.value(EffectParameter.intensityID, for: VisualEffectType.fisheye) == 0.3)

        vm.setValue(0.6, EffectParameter.sizeID, for: VisualEffectType.fisheye)
        #expect(vm.effectSize == 0.6)
    }

    // MARK: - Effect edit session

    /// The panel refuses to open without a selection, which is what keeps the
    /// "never editing with nothing selected" invariant from needing checks elsewhere.
    @Test func beginEditing_withoutSelection_doesNotOpen() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.beginEditing()
        #expect(vm.isEditingEffect == false)
    }

    @Test func beginEditing_withSelection_opens() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
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

    @Test func editingTitleAndParameters_resolveFromActiveCategory() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())

        vm.selectedEffectCategory = .visualEffects
        vm.selectedVisualEffect = .dither
        #expect(vm.editingTitle == "DITHER")
        #expect(vm.editingParameters.map(\.id) == [EffectParameter.intensityID, EffectParameter.sizeID])

        vm.selectedEffectCategory = .faceFilters
        vm.selectedFaceFilter = .lazerEyes
        #expect(vm.editingTitle == "LAZER EYES")
        #expect(vm.editingParameters.count == 3)
    }

    /// The zoom tab has no per-effect controls to drill into, so it declares none.
    @Test func editingParameters_forZoomCategory_isEmpty() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.selectedEffectCategory = .zoomEffects
        vm.selectedVisualEffect = .dither
        #expect(vm.editingParameters.isEmpty)
        #expect(vm.editingTitle == "")
    }
}

