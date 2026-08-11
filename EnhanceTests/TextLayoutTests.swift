import Testing
import CoreGraphics
import UIKit
@testable import Enhance

/// Layout, unit merging and tile cutting.
///
/// These render to pixels and *measure* rather than comparing against checked-in reference
/// images — the same idiom as `LensDistortionTests`. What makes it work for text is that the
/// master raster is computed in process and **is** the reference, so "does the composite match"
/// is a real assertion with nothing on disk to go stale.
struct TextLayoutTests {

    private let side: CGFloat = 480

    private func overlay(_ text: String,
                         animation: TextAnimationType = .type,
                         decoration: TextDecoration = .none,
                         font: TextFont = .silkscreenBold,
                         angle: CGFloat = 0,
                         fontSize: CGFloat = 0.12) -> TextOverlay {
        TextOverlay(text: text, center: CGPoint(x: 0.5, y: 0.5), fontSize: fontSize,
                    angle: angle, font: font, color: .white, alignment: .center,
                    decoration: decoration, animation: animation, seed: 42)
    }

    /// Renders a `CGImage` to RGBA8 and returns the raw bytes plus the count of pixels carrying
    /// any ink. Ink coverage is the signal most of these tests turn on.
    private func measure(_ image: CGImage) -> (bytes: [UInt8], ink: Int) {
        let w = image.width, h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var ink = 0
        for pixel in stride(from: 3, to: buffer.count, by: 4) where buffer[pixel] > 8 { ink += 1 }
        return (buffer, ink)
    }

    // MARK: - The load-bearing test

    /// Tiles must partition the master exactly: no overlap, nothing dropped.
    ///
    /// This one test kills overlap double-composite at seams, dropped ink between tiles,
    /// mis-derived seam positions, local/pixel coordinate errors, and any future "optimization"
    /// that inflates tiles to contain decoration bleed. If only one test survives, this is it.
    @Test(arguments: [
        TextAnimationType.pop, .type, .wordDrop
    ])
    func tiles_partitionTheMasterRaster_withoutOverlapOrLoss(animation: TextAnimationType) throws {
        for decoration in TextDecoration.allCases {
            for text in ["HELLO THERE", "TWO\nLINES", "سلام عليكم", "GO 🎉 NOW"] {
                let model = overlay(text, animation: animation, decoration: decoration)
                guard let raster = TextRasterizer.prepare(overlay: model, pixelSide: side) else {
                    Issue.record("no raster for \(animation.rawValue)/\(decoration.rawValue)")
                    continue
                }

                let cuts = raster.tiles.filter { $0.origin == .cut }
                #expect(!cuts.isEmpty)

                // 1. No two cut tiles overlap.
                for i in 0..<cuts.count {
                    for j in (i + 1)..<cuts.count {
                        let overlap = cuts[i].pixelRect.intersection(cuts[j].pixelRect)
                        #expect(overlap.isNull || overlap.width < 1 || overlap.height < 1,
                                "tiles \(i) and \(j) overlap for \(text)")
                    }
                }

                // 2. Every master pixel belongs to exactly one tile.
                let covered = cuts.reduce(0.0) { $0 + $1.pixelRect.width * $1.pixelRect.height }
                let total = CGFloat(raster.master.width * raster.master.height)
                #expect(abs(covered - total) < total * 0.001,
                        "tiles do not cover the master for \(text)")
            }
        }
    }

    /// Compositing every tile at rest must reproduce the master. This is the same invariant seen
    /// from the pixel side: if a seam is off by one, or a crop lands upside down, the ink count
    /// moves even when the rects look right.
    @Test func restingComposite_preservesTheMastersInk() throws {
        let model = overlay("HELLO", animation: .type)
        let raster = try #require(TextRasterizer.prepare(overlay: model, pixelSide: side))

        let masterInk = measure(raster.master).ink
        let tileInk = raster.tiles
            .filter { $0.origin == .cut }
            .reduce(0) { $0 + measure($1.image).ink }

        #expect(masterInk > 0, "the master must actually contain glyphs")
        #expect(tileInk == masterInk, "cutting changed the ink: \(tileInk) vs \(masterInk)")
    }

    // MARK: - Language correctness

    /// The decisive shaping test.
    ///
    /// Arabic glyphs join: `سلام` renders with initial, medial and final forms. Laying each
    /// grapheme cluster out *in isolation* renders the isolated forms instead — a completely
    /// different set of shapes, and a silent failure that every structural test passes through.
    /// Comparing total ink between the two proves the layout was done once, for the whole string.
    /// It needs no Arabic reading ability to interpret.
    @Test func arabicJoining_survivesTiling() throws {
        let word = "سلام"
        let whole = try #require(TextRasterizer.prepare(overlay: overlay(word, animation: .pop),
                                                        pixelSide: side))
        let joinedInk = measure(whole.master).ink

        var isolatedInk = 0
        for character in word {
            let piece = overlay(String(character), animation: .pop)
            if let raster = TextRasterizer.prepare(overlay: piece, pixelSide: side) {
                isolatedInk += measure(raster.master).ink
            }
        }

        #expect(joinedInk > 0)
        #expect(isolatedInk > 0)
        #expect(joinedInk != isolatedInk,
                "joined and isolated forms rendered identically — the string was re-shaped per cluster")
    }

    /// Lam-alef is two grapheme clusters and one glyph. A cluster-sized reveal would type half a
    /// glyph; the merge rule must fold them into one unit.
    @Test func lamAlef_isASingleUnit() throws {
        let model = overlay("لا", animation: .type)
        let layout = try #require(TextLayoutEngine.layout(overlay: model, outputSide: side))
        #expect(model.text.count == 2, "precondition: two grapheme clusters")
        #expect(layout.units.count == 1, "a ligature must not be split across reveal units")
    }

    /// Grapheme clusters are never split, whatever they are made of.
    @Test(arguments: ["👩‍👩‍👧‍👦", "🇯🇵", "é", "👍🏽"])
    func graphemeClusters_areNeverSplit(sample: String) throws {
        let model = overlay(sample, animation: .type)
        let layout = try #require(TextLayoutEngine.layout(overlay: model, outputSide: side))
        #expect(layout.units.count == sample.count,
                "\(sample) produced \(layout.units.count) units for \(sample.count) clusters")
    }

    /// RTL reveals in typing order while sitting in visual order: the first-typed unit is the
    /// rightmost on screen. Getting this from Core Text's caret offsets is what makes it free.
    @Test func rtl_typesInLogicalOrderAtVisualPositions() throws {
        let model = overlay("سلام", animation: .type)
        let layout = try #require(TextLayoutEngine.layout(overlay: model, outputSide: side))
        let inked = layout.units.filter { !$0.isWhitespace }
        let first = try #require(inked.first)
        let last = try #require(inked.last)

        #expect(layout.baseDirection == .rightToLeft)
        #expect(first.order < last.order, "reveal order must stay logical")
        #expect(first.inkRect.midX > last.inkRect.midX,
                "the first-typed unit must sit to the right in an RTL line")
    }

    /// Words come from `NLTokenizer`, never a split on spaces — "don't" is one word.
    @Test func wordDrop_usesLinguisticTokens() throws {
        let model = overlay("don't stop", animation: .wordDrop)
        let layout = try #require(TextLayoutEngine.layout(overlay: model, outputSide: side))
        #expect(layout.wordRanges.count == 2,
                "expected two linguistic tokens, got \(layout.wordRanges.count)")
    }

    // MARK: - Resolution independence

    /// The parity guarantee that replaces a snapshot suite.
    ///
    /// Preview and export differ *only* in raster size, and both consume this layout and one
    /// transform function. If every geometric value scales linearly with the side, they cannot
    /// disagree — and this fails loudly the moment someone reintroduces a constant in pixels.
    @Test func layoutIsResolutionIndependent() throws {
        let model = overlay("RESOLUTION", animation: .type)
        let small = try #require(TextLayoutEngine.layout(overlay: model, outputSide: 300))
        let large = try #require(TextLayoutEngine.layout(overlay: model, outputSide: 600))

        #expect(small.units.count == large.units.count)
        #expect(small.lineCount == large.lineCount)
        #expect(small.wordRanges == large.wordRanges)

        for (a, b) in zip(small.units, large.units) {
            #expect(a.order == b.order)
            #expect(abs(a.inkRect.midX / 300 - b.inkRect.midX / 600) < 1e-6)
            #expect(abs(a.inkRect.midY / 300 - b.inkRect.midY / 600) < 1e-6)
            #expect(abs(a.inkRect.width / 300 - b.inkRect.width / 600) < 1e-6)
        }
    }

    // MARK: - Guards

    @Test(arguments: ["", "   ", "\n\t "])
    func whitespaceOnlyText_producesNoRaster(text: String) {
        #expect(TextRasterizer.prepare(overlay: overlay(text), pixelSide: side) == nil)
    }

    /// Rotation is applied at composite time, so an off-axis overlay is supersampled to keep the
    /// resample clean. Axis-aligned text must not pay that cost.
    @Test func offAxisRotation_supersamplesButRightAnglesDoNot() {
        let upright = TextRasterizer.supersampleFactor(for: overlay("A", animation: .rise))
        let turned = TextRasterizer.supersampleFactor(
            for: overlay("A", animation: .rise, angle: .pi / 5)
        )
        let rightAngle = TextRasterizer.supersampleFactor(
            for: overlay("A", animation: .rise, angle: .pi / 2)
        )

        #expect(upright == 1)
        #expect(rightAngle == 1)
        #expect(turned == 2)
    }
}
