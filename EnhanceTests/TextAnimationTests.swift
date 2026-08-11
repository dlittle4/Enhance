import Testing
import CoreGraphics
@testable import Enhance

/// The five entrance presets and the placement transform.
///
/// Asserted on the state *data* rather than on rendered pixels wherever possible. That is what
/// removes the need for the snapshot infrastructure this repo does not have: preview and export
/// consume the same `[TextTileState]` and the same transform, so agreeing on the data is
/// agreeing on the result.
struct TextAnimationTests {

    private let side: CGFloat = 480

    private func overlay(_ animation: TextAnimationType,
                         text: String = "HELLO WORLD",
                         angle: CGFloat = 0) -> TextOverlay {
        TextOverlay(text: text, center: CGPoint(x: 0.5, y: 0.5), fontSize: 0.12, angle: angle,
                    font: .silkscreenBold, color: .white, alignment: .center,
                    decoration: .none, animation: animation, seed: 7)
    }

    private func layout(_ animation: TextAnimationType,
                        text: String = "HELLO WORLD") throws -> PreparedTextLayout {
        try #require(TextLayoutEngine.layout(overlay: overlay(animation, text: text),
                                             outputSide: side))
    }

    // MARK: - Endpoints

    /// Nothing may be visible in the first frame.
    ///
    /// This protects a product property with nothing to do with animation: reopening a saved GIF
    /// takes frame 0 as the new source image, so a title baked into that frame would be
    /// duplicated the next time the user edits. Prose in the plan; an assertion here.
    @Test(arguments: TextAnimationType.allCases)
    func everyPreset_atZeroProgress_isFullyTransparent(animation: TextAnimationType) throws {
        let states = animation.tileStates(at: 0, layout: try layout(animation))
        #expect(!states.isEmpty)
        for state in states {
            #expect(state.alpha == 0, "\(animation.rawValue) shows ink in the first frame")
        }
    }

    /// At full progress every cut tile must be exactly at rest, so the pause frames — one render
    /// replicated — hold a settled, complete message.
    @Test(arguments: TextAnimationType.allCases)
    func everyPreset_atFullProgress_settlesExactly(animation: TextAnimationType) throws {
        let prepared = try layout(animation)
        let states = animation.tileStates(at: 1, layout: prepared)
        let slots = animation.slotCount(in: prepared)

        for index in 0..<slots {
            #expect(states[index] == .resting,
                    "\(animation.rawValue) slot \(index) did not settle: \(states[index])")
        }
        // The cursor is the one thing that must be *gone* rather than at rest.
        if let cursor = animation.cursorStateIndex(in: prepared) {
            #expect(states[cursor].alpha == 0, "the TYPE cursor must not survive into the pause")
        }
    }

    @Test(arguments: TextAnimationType.allCases)
    func everyPreset_returnsOneStatePerSlotPlusCursor(animation: TextAnimationType) throws {
        let prepared = try layout(animation)
        let states = animation.tileStates(at: 0.5, layout: prepared)
        #expect(states.count == animation.stateCount(in: prepared))
    }

    /// Progress outside `0…1` is clamped, not extrapolated — an out-of-range value must never
    /// produce a transform that flings the text off frame.
    @Test(arguments: TextAnimationType.allCases)
    func everyPreset_clampsProgressOutsideTheUnitRange(animation: TextAnimationType) throws {
        let prepared = try layout(animation)
        #expect(animation.tileStates(at: -3, layout: prepared)
            == animation.tileStates(at: 0, layout: prepared))
        #expect(animation.tileStates(at: 4, layout: prepared)
            == animation.tileStates(at: 1, layout: prepared))
    }

    @Test(arguments: TextAnimationType.allCases)
    func everyPreset_producesFiniteValuesThroughout(animation: TextAnimationType) throws {
        let prepared = try layout(animation)
        for step in 0...40 {
            let p = CGFloat(step) / 40
            for state in animation.tileStates(at: p, layout: prepared) {
                #expect(state.alpha.isFinite && state.scaleDelta.isFinite)
                #expect(state.rotationDelta.isFinite)
                #expect(state.translationDelta.x.isFinite && state.translationDelta.y.isFinite)
                #expect(state.alpha >= 0 && state.alpha <= 1)
                #expect(state.scaleDelta > 0)
            }
        }
    }

    /// The entrance closes by 70% of the moving frames, leaving the last 30% settled.
    @Test(arguments: TextAnimationType.allCases)
    func everyPreset_isSettledByTheEntranceWindow(animation: TextAnimationType) throws {
        let prepared = try layout(animation)
        let states = animation.tileStates(at: TextAnimationType.entranceWindow, layout: prepared)
        for index in 0..<animation.slotCount(in: prepared) {
            #expect(states[index] == .resting,
                    "\(animation.rawValue) was still moving at the end of the entrance window")
        }
    }

    // MARK: - Determinism

    /// FLICKER is the only preset with randomness in it, and it must be a pure function of the
    /// stored seed. Anything else and preview disagrees with export, and two generations of the
    /// same overlay differ — neither recoverable after the fact.
    @Test func flicker_isDeterministicForASeed() throws {
        let prepared = try layout(.flicker)
        for step in 0...20 {
            let p = CGFloat(step) / 20
            #expect(TextAnimationType.flicker.tileStates(at: p, layout: prepared)
                == TextAnimationType.flicker.tileStates(at: p, layout: prepared))
        }
    }

    @Test func flicker_differsAcrossSeeds() throws {
        var a = overlay(.flicker); a.seed = 1
        var b = overlay(.flicker); b.seed = 999_999
        let layoutA = try #require(TextLayoutEngine.layout(overlay: a, outputSide: side))
        let layoutB = try #require(TextLayoutEngine.layout(overlay: b, outputSide: side))

        var differed = false
        for step in 0...20 {
            let p = CGFloat(step) / 20
            if TextAnimationType.flicker.tileStates(at: p, layout: layoutA)
                != TextAnimationType.flicker.tileStates(at: p, layout: layoutB) {
                differed = true
                break
            }
        }
        #expect(differed, "two seeds produced an identical flicker")
    }

    // MARK: - Reveal shape

    /// TYPE is a stepped reveal: each unit is fully on or fully off, never part-way. Exact 0/1
    /// alpha is also what lets the partition test compare a composite byte for byte.
    @Test func type_revealsUnitsInLogicalOrderWithoutPartialAlpha() throws {
        let prepared = try layout(.typewriter, text: "TYPING")
        var seen = 0
        for step in 0...30 {
            let states = TextAnimationType.typewriter.tileStates(at: CGFloat(step) / 30, layout: prepared)
            let visible = states.prefix(TextAnimationType.typewriter.slotCount(in: prepared))
                .filter { $0.alpha > 0 }
            for state in visible { #expect(state.alpha == 1) }
            #expect(visible.count >= seen, "the reveal went backwards")
            seen = visible.count
        }
        #expect(seen == TextAnimationType.typewriter.slotCount(in: prepared))
    }

    @Test func slide_staggersWordsRatherThanMovingThemTogether() throws {
        let prepared = try layout(.slide, text: "ONE TWO THREE")
        let states = TextAnimationType.slide.tileStates(at: 0.25, layout: prepared)
        let alphas = Set(states.map { ($0.alpha * 1000).rounded() })
        #expect(prepared.wordRanges.count >= 3)
        #expect(alphas.count > 1, "every word animated in lockstep — the stagger is missing")
    }

    @Test func pop_overshootsWithoutExceedingTheDeclaredPeak() throws {
        let prepared = try layout(.pop)
        var maxScale: CGFloat = 0
        for step in 0...100 {
            let states = TextAnimationType.pop.tileStates(at: CGFloat(step) / 100,
                                                          layout: prepared, tuning: 1.0)
            maxScale = max(maxScale, states[0].scaleDelta)
        }
        #expect(maxScale > 1.0, "POP did not overshoot")
        #expect(maxScale <= TextAnimationType.pop.peakScale + 1e-9,
                "POP exceeded peakScale, so the raster would be upscaled at its sharpest frame")
    }

    // MARK: - Transform algebra

    private func raster(_ animation: TextAnimationType,
                        angle: CGFloat = 0) throws -> RasterizedText {
        try #require(TextRasterizer.prepare(overlay: overlay(animation, angle: angle),
                                            pixelSide: side))
    }

    /// A 90°-rotated title that SLIDEs must still travel up the *screen*: preset translation is
    /// applied after the user's rotation, in output space.
    @Test func screenSpaceTranslation_survivesUserRotation() throws {
        let turned = try raster(.slide, angle: .pi / 2)
        let model = overlay(.slide, angle: .pi / 2)
        let tile = try #require(turned.tiles.first)

        let moving = TextAnimationType.slide.tileStates(at: 0.1, layout: turned.layout)[0]
        let atRest = TextTileState.resting

        let movingY = TextComposer.transform(tile: tile, state: moving, overlay: model,
                                             raster: turned, outputSide: side).ty
        let restY = TextComposer.transform(tile: tile, state: atRest, overlay: model,
                                           raster: turned, outputSide: side).ty

        // y grows downward, and RISE starts below its resting place.
        #expect(movingY > restY, "rotation leaked into the screen-space translation")
    }

    /// POP scales about the tile's own centre, so the block must not drift while it overshoots.
    @Test func localScale_doesNotMoveTheBlockCentre() throws {
        let prepared = try raster(.pop)
        let model = overlay(.pop)
        let tile = try #require(prepared.tiles.first)

        let peak = TextTileState(alpha: 1, scaleDelta: 1.08, rotationDelta: 0,
                                 translationDelta: .zero)
        let scaled = TextComposer.transform(tile: tile, state: peak, overlay: model,
                                            raster: prepared, outputSide: side)
        let rest = TextComposer.transform(tile: tile, state: .resting, overlay: model,
                                          raster: prepared, outputSide: side)

        let scaledCentre = tile.localCentre.applying(scaled)
        let restCentre = tile.localCentre.applying(rest)
        #expect(abs(scaledCentre.x - restCentre.x) < 0.001)
        #expect(abs(scaledCentre.y - restCentre.y) < 0.001)
    }

    /// The export must never pass a live pinch factor; it is defaulted so it cannot.
    @Test func exportPath_neverAppliesLiveScale() throws {
        let prepared = try raster(.pop)
        let model = overlay(.pop)
        let tile = try #require(prepared.tiles.first)

        let defaulted = TextComposer.transform(tile: tile, state: .resting, overlay: model,
                                               raster: prepared, outputSide: side)
        let explicit = TextComposer.transform(tile: tile, state: .resting, overlay: model,
                                              raster: prepared, outputSide: side, liveScale: 1.0)
        #expect(defaulted == explicit)
    }

    /// Compositing at progress 0 must leave the frame exactly as it arrived, so a GIF generated
    /// with an overlay whose entrance has not begun is byte-identical to one generated without.
    @Test func compositeAtZeroProgress_leavesTheBaseFrameUntouched() throws {
        let prepared = try raster(.pop)
        let model = overlay(.pop)
        let base = try #require(solidImage(side: Int(side)))

        let result = TextTileCompositor.composite(prepared, overlay: model, progress: 0,
                                                  over: base)
        #expect(bytes(of: result) == bytes(of: base))
    }

    @Test func compositeAtFullProgress_addsInk() throws {
        let prepared = try raster(.pop)
        let model = overlay(.pop)
        let base = try #require(solidImage(side: Int(side)))

        let result = TextTileCompositor.composite(prepared, overlay: model, progress: 1,
                                                  over: base)
        #expect(bytes(of: result) != bytes(of: base))
    }

    // MARK: - Fixtures

    private func solidImage(side: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    private func bytes(of image: CGImage) -> [UInt8] {
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
        return buffer
    }
}
