import Testing
import UIKit
@testable import Enhance

struct GIFGeneratorTests {
    
    /// Creates a minimal 10x10 red UIImage for testing.
    private func makeTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        return renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }
    
    // MARK: - generateGIF
    
    @Test func generateGIF_withValidInput_returnsData() {
        let generator = GIFGenerator()
        let image = makeTestImage()
        let data = generator.generateGIF(
            from: image,
            currentScale: 2.0,
            visibleRect: CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7),
            animator: ZoomInAnimator()
        )
        #expect(data != nil)
    }
    
    @Test func generateGIF_startsWithGIFMagicBytes() {
        let generator = GIFGenerator()
        let image = makeTestImage()
        guard let data = generator.generateGIF(
            from: image,
            currentScale: 2.0,
            visibleRect: CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7),
            animator: ZoomInAnimator()
        ) else {
            Issue.record("GIF generation returned nil")
            return
        }
        
        let header = data.prefix(6)
        let gif89a = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]) // "GIF89a"
        let gif87a = Data([0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) // "GIF87a"
        #expect(header == gif89a || header == gif87a)
    }
    
    @Test func generateGIF_withScaleTooLow_returnsNil() {
        let generator = GIFGenerator()
        let image = makeTestImage()
        let data = generator.generateGIF(
            from: image,
            currentScale: 1.0,
            visibleRect: CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7),
            animator: ZoomInAnimator()
        )
        #expect(data == nil)
    }
    
    @Test func generateGIF_withDifferentAnimators_allProduceData() {
        let generator = GIFGenerator()
        let image = makeTestImage()
        let rect = CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7)
        
        for type in AnimatorType.allCases {
            let data = generator.generateGIF(from: image, currentScale: 2.0, visibleRect: rect, animator: type.animator)
            #expect(data != nil)
        }
    }
    
    @Test func generateGIF_withVisualEffect_returnsData() {
        let generator = GIFGenerator()
        let image = makeTestImage()
        let data = generator.generateGIF(
            from: image,
            currentScale: 2.0,
            visibleRect: CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7),
            animator: ZoomInAnimator(),
            visualEffects: [FadeToBWEffect()]
        )
        #expect(data != nil)
    }
    
    @Test func generateGIF_withCompositeAnimator_returnsData() {
        let generator = GIFGenerator()
        let image = makeTestImage()
        let composite = CompositeAnimator(base: ZoomInAnimator(), modifier: ShakeModifier())
        let data = generator.generateGIF(
            from: image,
            currentScale: 2.0,
            visibleRect: CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7),
            animator: composite
        )
        #expect(data != nil)
    }
    
    // MARK: - saveTempGIF
    
    @Test func saveTempGIF_writesFileAndReturnsURL() {
        let generator = GIFGenerator()
        let testData = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
        
        guard let url = generator.saveTempGIF(testData) else {
            Issue.record("saveTempGIF returned nil")
            return
        }
        
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.pathExtension == "gif")
        
        try? FileManager.default.removeItem(at: url)
    }
    
    @Test func saveTempGIF_preservesData() throws {
        let generator = GIFGenerator()
        let testData = Data(repeating: 0xAB, count: 256)
        
        guard let url = generator.saveTempGIF(testData) else {
            Issue.record("saveTempGIF returned nil")
            return
        }
        
        let readBack = try Data(contentsOf: url)
        #expect(readBack == testData)
        
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - Speed parameter
    
    @Test func generateGIF_withDifferentSpeeds_allProduceData() {
        let generator = GIFGenerator()
        let image = makeTestImage()
        let rect = CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7)
        
        for speed in [0.5, 1.0, 2.0, 4.0] {
            let data = generator.generateGIF(from: image, currentScale: 2.0, visibleRect: rect, animator: ZoomInAnimator(), speed: speed)
            #expect(data != nil)
        }
    }
}
