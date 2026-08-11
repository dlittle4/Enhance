import Testing
import UIKit
import ImageIO
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
    
    /// Phase 13c removed the hard `currentScale > 1.0` guard so effects-only GIFs
    /// (visual/face effects with no zoom) can be generated. Generation at 1x must
    /// succeed; it is the ViewModel's job to decide whether 1x is meaningful.
    @Test func generateGIF_atUnityScale_stillProducesData() {
        let generator = GIFGenerator()
        let image = makeTestImage()
        let data = generator.generateGIF(
            from: image,
            currentScale: 1.0,
            visibleRect: CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7),
            animator: ZoomInAnimator()
        )
        #expect(data != nil)
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
    
    // MARK: - Text overlay (Stage D pipeline splice)

    private func makeOverlay(_ text: String = "HI",
                             animation: TextAnimationType = .pop) -> TextOverlay {
        TextOverlay(text: text, center: CGPoint(x: 0.5, y: 0.5), fontSize: 0.12, angle: 0,
                    font: .silkscreenBold, color: .white, alignment: .center,
                    decoration: .shadow, animation: animation, seed: 99)
    }

    private func frameCount(of data: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return 0 }
        return CGImageSourceGetCount(source)
    }

    /// The Stage D gate: with no overlay, the generator must be byte-for-byte what it was before
    /// the text pass existed. Passing `nil` explicitly must equal omitting the argument entirely,
    /// so the whole no-text world is provably untouched. See FEATURE-TEXT-EFFECTS.md §12.9.
    @Test func generateGIF_withNilTextOverlay_isByteIdenticalToOmittingIt() {
        let generator = GIFGenerator()
        let image = makeTestImage()
        let rect = CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7)

        let withoutArg = generator.generateGIF(from: image, currentScale: 2.0, visibleRect: rect,
                                               animator: ZoomInAnimator())
        let withNil = generator.generateGIF(from: image, currentScale: 2.0, visibleRect: rect,
                                            animator: ZoomInAnimator(), textOverlay: nil)
        #expect(withoutArg != nil)
        #expect(withoutArg == withNil)
    }

    @Test func generateGIF_withTextOverlay_returnsData() {
        let generator = GIFGenerator()
        let data = generator.generateGIF(
            from: makeTestImage(), currentScale: 2.0,
            visibleRect: CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7),
            animator: ZoomInAnimator(), textOverlay: makeOverlay()
        )
        #expect(data != nil)
    }

    /// Adding text must change the pixels but not the timeline: the overlay is composited into
    /// existing frames, never inserted as new ones, so the frame count is unchanged.
    @Test func generateGIF_addingText_changesTheBytesButNotTheFrameCount() {
        let generator = GIFGenerator()
        let image = makeTestImage()
        let rect = CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7)

        guard let plain = generator.generateGIF(from: image, currentScale: 2.0, visibleRect: rect,
                                                animator: ZoomInAnimator()),
              let texted = generator.generateGIF(from: image, currentScale: 2.0, visibleRect: rect,
                                                 animator: ZoomInAnimator(),
                                                 textOverlay: makeOverlay()) else {
            Issue.record("GIF generation returned nil")
            return
        }

        #expect(plain != texted, "the overlay must change the rendered pixels")
        #expect(frameCount(of: plain) == frameCount(of: texted),
                "text is composited into frames, not added as new ones")
    }

    /// FLICKER is the one preset with randomness, seeded from the overlay. Two generations of the
    /// same overlay must be byte-identical, or preview and export could never be trusted to agree.
    @Test func generateGIF_withText_isDeterministic() {
        let generator = GIFGenerator()
        let image = makeTestImage()
        let rect = CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7)
        let overlay = makeOverlay("GO", animation: .flicker)

        let first = generator.generateGIF(from: image, currentScale: 2.0, visibleRect: rect,
                                          animator: ZoomInAnimator(), textOverlay: overlay)
        let second = generator.generateGIF(from: image, currentScale: 2.0, visibleRect: rect,
                                           animator: ZoomInAnimator(), textOverlay: overlay)
        #expect(first != nil)
        #expect(first == second)
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
