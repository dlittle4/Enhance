import Testing
import UIKit
@testable import Enhance

/// Lightweight stub that records calls without doing real GIF work.
private struct StubGIFGenerator: GIFGenerating {
    var shouldSucceed: Bool = true
    
    func generateGIF(from image: UIImage, currentScale: CGFloat, visibleRect: CGRect, animator: Animator, speed: Double, pauseDuration: Double, visualEffects: [VisualEffect]) -> Data? {
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
        vm.selectedVisualEffect = .fadeToBW
        #expect(vm.hasNonDefaultSettings == true)
    }

    // MARK: - effectSize defaults

    @Test func effectSize_defaultsToHalf() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        #expect(vm.effectSize == 0.5)
    }

    @Test func sizeLabel_returnsCorrectBuckets() {
        let vm = EditorViewModel(content: .newImage(makeImage()), gifGenerator: StubGIFGenerator())
        vm.effectSize = 0.1
        #expect(vm.sizeLabel == "SMALL")
        vm.effectSize = 0.5
        #expect(vm.sizeLabel == "MEDIUM")
        vm.effectSize = 0.7
        #expect(vm.sizeLabel == "LARGE")
        vm.effectSize = 0.9
        #expect(vm.sizeLabel == "MAX")
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
        #expect(vm.selectedModifier == .straight)
        #expect(vm.playbackSpeed == 1.0)
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
}
