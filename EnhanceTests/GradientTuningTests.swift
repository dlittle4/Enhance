import Testing
import Foundation
import SwiftUI
@testable import Enhance

/// Covers the pure pieces behind the STATIC / DITHER experiments. What the effects *look* like
/// is judged in the simulator — these guard the parts that can be wrong invisibly: the flag
/// combination policy, the float precision the noise depends on, and whether a tuned value
/// actually survives to the clipboard.
struct GradientTuningTests {

    // MARK: - Style resolution

    /// The promise the flags make: an install that never touches them renders the old gradient.
    @Test func resolve_withNoFlags_isPlainMesh() {
        let style = ButtonGradientStyle.resolve(staticOn: false, ditherOn: false, tuning: .default)
        #expect(style == .mesh)
        #expect(style.isQuantized == false)
    }

    @Test func resolve_staticOnly_usesNoiseAndNoOrdering() {
        let style = ButtonGradientStyle.resolve(staticOn: true, ditherOn: false, tuning: .default)
        #expect(style.noiseAmount == GradientTuning.default.noiseAmount)
        #expect(style.orderedAmount == 0)
        #expect(style.isQuantized)
    }

    @Test func resolve_ditherOnly_usesOrderingAndNoNoise() {
        let style = ButtonGradientStyle.resolve(staticOn: false, ditherOn: true, tuning: .default)
        #expect(style.noiseAmount == 0)
        #expect(style.orderedAmount == GradientTuning.default.orderedAmount)
        #expect(style.isQuantized)
    }

    /// Both toggles on has to read as *combined*, not as whichever one won. Full-strength noise
    /// swamps the Bayer matrix, so the blend halves it — if that ever regresses to the STATIC
    /// value, the second toggle silently stops doing anything visible.
    @Test func resolve_bothOn_blendsRatherThanPickingOne() {
        let both = ButtonGradientStyle.resolve(staticOn: true, ditherOn: true, tuning: .default)
        let onlyStatic = ButtonGradientStyle.resolve(staticOn: true, ditherOn: false, tuning: .default)

        #expect(both.noiseAmount > 0)
        #expect(both.orderedAmount > 0)
        #expect(both.noiseAmount < onlyStatic.noiseAmount)
    }

    /// The amounts come from the tuning, so dragging NOISE to zero in the lab has to be able to
    /// turn the effect off even with the flag on.
    @Test func resolve_readsAmountsFromTuning() {
        var tuning = GradientTuning.default
        tuning.noiseAmount = 0
        let style = ButtonGradientStyle.resolve(staticOn: true, ditherOn: false, tuning: tuning)
        #expect(style.isQuantized == false)
    }

    // MARK: - Pulse

    @Test func poles_areDeterministic() {
        let tuning = GradientTuning.default
        #expect(tuning.poles(at: 3.25).light == tuning.poles(at: 3.25).light)
        #expect(tuning.poles(at: 3.25).mid == tuning.poles(at: 3.25).mid)
    }

    @Test func poles_repeatEveryPulseDuration() {
        let tuning = GradientTuning.default
        let a = tuning.poles(at: 1.0)
        let b = tuning.poles(at: 1.0 + tuning.pulseDuration)
        #expect(a.light == b.light)
        #expect(a.dark == b.dark)
    }

    /// A pulse of zero would divide by zero in the sine; it has to pin rather than produce NaN.
    @Test func poles_withZeroPulse_holdAtStateA() {
        var tuning = GradientTuning.default
        tuning.pulseDuration = 0
        #expect(tuning.poles(at: 99).light == tuning.poleLightA.color)
    }

    // MARK: - Frame seed

    /// The bug this exists to catch: passing `timeIntervalSinceReferenceDate` (~7.8×10⁸) into a
    /// `float` shader argument leaves no mantissa for the fraction, so every frame hashes
    /// identically and the static freezes. The seed must stay in a range float32 resolves.
    @Test func frameSeed_staysSmallEnoughForFloat32() {
        let tuning = GradientTuning.default
        let now = Date().timeIntervalSinceReferenceDate
        let seed = tuning.frameSeed(at: now)

        #expect(seed >= 0)
        #expect(seed < 4096)
        #expect(Double(Float(seed)) == seed, "seed must survive the float32 shader argument")
    }

    @Test func frameSeed_advancesOncePerTick() {
        let tuning = GradientTuning.default          // 12fps
        let base = 1_000.0
        let sameTick = tuning.frameSeed(at: base + 0.01)
        let nextTick = tuning.frameSeed(at: base + (1.0 / 12.0) + 0.01)

        #expect(tuning.frameSeed(at: base) == sameTick)
        #expect(nextTick != sameTick)
    }

    // MARK: - Density field

    /// The reason the density stops are not a copy of the button palette: quantizing needs a
    /// luminance *spread*, and the original nine colours are a hue swirl that all sit between
    /// 0.49 and 0.77. Without a spread there is no falloff across the button, only even noise.
    @Test func meshPalette_spansAWideLuminanceRange() {
        let colors = GradientTuning.default.meshPalette(swapped: false)
        #expect(colors.count == 9)

        let luminances = [GradientTuning.default.meshLight,
                          GradientTuning.default.meshMid,
                          GradientTuning.default.meshDark].map { 0.299 * $0.r + 0.587 * $0.g + 0.114 * $0.b }
        let spread = luminances.max()! - luminances.min()!
        #expect(spread > 0.3, "got \(luminances)")
    }

    @Test func meshPalette_swappedDiffersFromUnswapped() {
        let tuning = GradientTuning.default
        #expect(tuning.meshPalette(swapped: true) != tuning.meshPalette(swapped: false))
    }

    // MARK: - Persistence and export

    @Test func tuning_roundTripsThroughCodable() throws {
        var tuning = GradientTuning.default
        tuning.poleLightA = RGBColor(r: 0.1, g: 0.2, b: 0.3)
        tuning.cellSize = 13

        let data = try JSONEncoder().encode(tuning)
        let decoded = try JSONDecoder().decode(GradientTuning.self, from: data)
        #expect(decoded == tuning)
    }

    @Test func store_persistsAndResets() throws {
        // A scratch suite, so a tuned palette cannot leak into the app's own defaults and change
        // what the next simulator launch renders.
        let suiteName = "GradientTuningTests-\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }

        let store = GradientTuningStore(defaults: suite)
        store.tuning.cellSize = 20
        #expect(GradientTuningStore(defaults: suite).tuning.cellSize == 20)

        store.reset()
        #expect(GradientTuningStore(defaults: suite).tuning == .default)
    }

    /// The whole point of the lab is that what you tuned is what you paste. A snippet built from
    /// the defaults instead of the live values would look plausible and be wrong.
    @Test func swiftSnippet_carriesTheTunedValues() {
        var tuning = GradientTuning.default
        tuning.poleLightA = RGBColor(r: 0.125, g: 0.25, b: 0.5)
        tuning.cellSize = 13

        let snippet = tuning.swiftSnippet
        #expect(snippet.contains("RGBColor(r: 0.125, g: 0.250, b: 0.500)"))
        #expect(snippet.contains("cellSize: 13.000"))
    }

    // MARK: - Label contrast

    /// The case the feature exists for: poles dragged somewhere dark must stop giving black text.
    @Test func labelColor_auto_goesWhiteOnADarkGround() {
        var tuning = GradientTuning.default
        let nearBlack = RGBColor(r: 0.08, g: 0.05, b: 0.14)
        tuning.poleLightA = nearBlack
        tuning.poleLightB = nearBlack
        tuning.poleDarkA = nearBlack
        tuning.poleDarkB = nearBlack

        #expect(tuning.labelColor(at: 0) == .white)
    }

    @Test func labelColor_auto_staysBlackOnTheStockMintPalette() {
        #expect(GradientTuning.default.labelColor(at: 0) == .black)
    }

    /// Luminance is weighted, not averaged — the whole reason not to threshold on brightness.
    /// Pure green and pure blue have near-identical RGB averages and wildly different luminance,
    /// so a naive implementation gets one of these two backwards.
    @Test func labelColor_auto_weightsGreenOverBlue() {
        var green = GradientTuning.default
        let pureGreen = RGBColor(r: 0, g: 1, b: 0)
        green.poleLightA = pureGreen; green.poleLightB = pureGreen
        green.poleDarkA = pureGreen; green.poleDarkB = pureGreen

        var blue = GradientTuning.default
        let pureBlue = RGBColor(r: 0, g: 0, b: 1)
        blue.poleLightA = pureBlue; blue.poleLightB = pureBlue
        blue.poleDarkA = pureBlue; blue.poleDarkB = pureBlue

        #expect(green.labelColor(at: 0) == .black)
        #expect(blue.labelColor(at: 0) == .white)
    }

    @Test func labelColor_manualModesIgnoreTheGround() {
        var tuning = GradientTuning.default
        tuning.labelMode = .white
        #expect(tuning.labelColor(at: 0) == .white)
        tuning.labelMode = .black
        #expect(tuning.labelColor(at: 0) == .black)
    }

    /// The two anchors of the WCAG scale, which pin the maths at both ends.
    @Test func contrastRatio_matchesTheKnownBounds() {
        let white = RGBColor(r: 1, g: 1, b: 1)
        let black = RGBColor(r: 0, g: 0, b: 0)
        #expect(abs(GradientTuning.contrastRatio(of: .black, on: white) - 21) < 0.01)
        #expect(abs(GradientTuning.contrastRatio(of: .white, on: white) - 1) < 0.01)
        #expect(abs(GradientTuning.contrastRatio(of: .white, on: black) - 21) < 0.01)
    }

    /// `.auto` picks the better of the two, so by construction it can never be beaten by the mode
    /// it rejected. Worth pinning: this is the property the feature actually promises.
    @Test func labelContrast_autoIsNeverWorseThanEitherFixedChoice() {
        for ground in [RGBColor(r: 0.9, g: 0.9, b: 0.2),
                       RGBColor(r: 0.1, g: 0.1, b: 0.3),
                       RGBColor(r: 0.5, g: 0.5, b: 0.5)] {
            var tuning = GradientTuning.default
            tuning.poleLightA = ground; tuning.poleLightB = ground
            tuning.poleDarkA = ground; tuning.poleDarkB = ground

            tuning.labelMode = .auto
            let auto = tuning.labelContrast(at: 0)
            tuning.labelMode = .black
            let black = tuning.labelContrast(at: 0)
            tuning.labelMode = .white
            let white = tuning.labelContrast(at: 0)

            #expect(auto >= black - 0.001, "ground \(ground)")
            #expect(auto >= white - 0.001, "ground \(ground)")
        }
    }

    /// At two levels the mid poles are not rendered, so letting them drag the average would have
    /// the label reacting to a colour that is not on screen.
    @Test func averageGround_ignoresMidPolesAtTwoLevels() {
        var tuning = GradientTuning.default
        tuning.levels = 2
        let without = tuning.ground(at: 0)

        tuning.poleMidA = RGBColor(r: 0, g: 0, b: 0)
        tuning.poleMidB = RGBColor(r: 0, g: 0, b: 0)
        #expect(tuning.ground(at: 0) == without)

        tuning.levels = 3
        #expect(tuning.ground(at: 0) != without)
    }

    /// The behaviour the live label is for: a pulse running from a bright pole pair to a dark one
    /// has no single right answer, so the choice has to change partway through the cycle.
    @Test func labelColor_auto_tracksThePulse() {
        var tuning = GradientTuning.default
        let bright = RGBColor(r: 0.95, g: 0.95, b: 0.9)
        let dark = RGBColor(r: 0.06, g: 0.04, b: 0.12)
        tuning.poleLightA = bright; tuning.poleDarkA = bright
        tuning.poleLightB = dark;  tuning.poleDarkB = dark

        // t=0 sits at pole set A, a quarter-pulse later the sine has carried it to B.
        #expect(tuning.labelColor(at: 0) == .black)
        #expect(tuning.labelColor(at: tuning.pulseDuration / 4) == .white)
    }

    /// The counterpart: a palette that stays on one side of the crossover must *not* flicker,
    /// or every button in the app develops a twitch.
    @Test func labelColor_auto_isStableWhenThePulseDoesNotCross() {
        let tuning = GradientTuning.default
        let choices = stride(from: 0.0, to: tuning.pulseDuration, by: 0.1)
            .map { tuning.labelColor(at: $0) }
        #expect(Set(choices.map { $0 == .white }).count == 1)
    }

    /// The lab reports the worst moment, not the current one — a look that is fine for most of
    /// the cycle and unreadable at one end is exactly what needs flagging.
    @Test func worstLabelContrast_findsTheDipRatherThanAnInstant() {
        var tuning = GradientTuning.default
        // A mid grey is the hardest ground there is: neither black nor white clears 4.5.
        let awkward = RGBColor(r: 0.46, g: 0.46, b: 0.46)
        tuning.poleLightA = GradientTuning.default.poleLightA
        tuning.poleDarkA = GradientTuning.default.poleLightA
        tuning.poleLightB = awkward
        tuning.poleDarkB = awkward

        #expect(tuning.worstLabelContrast() < tuning.labelContrast(at: 0))
    }

    // MARK: - Drift

    @Test func driftOffset_isZeroWhenSpeedIsZero() {
        var tuning = GradientTuning.default
        tuning.driftSpeed = 0
        #expect(tuning.driftOffset(at: 1234) == .zero)
    }

    /// Direction has to actually mean direction: 0 travels along x, a quarter turn along y.
    @Test func driftOffset_followsItsAngle() {
        var tuning = GradientTuning.default
        tuning.driftSpeed = 10
        tuning.driftAngle = 0
        let right = tuning.driftOffset(at: 1)
        #expect(abs(right.width - 10) < 0.001)
        #expect(abs(right.height) < 0.001)

        tuning.driftAngle = .pi / 2
        let down = tuning.driftOffset(at: 1)
        #expect(abs(down.width) < 0.001)
        #expect(abs(down.height - 10) < 0.001)
    }

    /// Same float32 trap as `frameSeed`: an unbounded offset stops resolving and the drift stalls.
    ///
    /// The property that matters is **not** that the offset is exactly representable as a `Float`
    /// — almost no real value is, and asserting that made this test pass or fail on the wall clock.
    /// It is that consecutive ticks stay far enough apart to survive the narrowing, which is what
    /// keeps the pattern moving once the value reaches the GPU.
    @Test func driftOffset_staysResolvableAtFloat32() {
        var tuning = GradientTuning.default
        tuning.driftSpeed = 40
        tuning.driftAngle = 0

        let now = Date().timeIntervalSinceReferenceDate
        let period = 4 * tuning.cellSize * 256
        #expect(abs(tuning.driftOffset(at: now).width) <= period)

        let next = now + 1 / tuning.staticFrameRate
        #expect(Float(tuning.driftOffset(at: now).width) != Float(tuning.driftOffset(at: next).width))
    }

    /// The wrap lands back on the Bayer lattice, so the pattern is continuous across it rather
    /// than jumping once a period.
    @Test func driftOffset_wrapsOnTheBayerPeriod() {
        var tuning = GradientTuning.default
        tuning.driftSpeed = 40
        tuning.driftAngle = 0

        let period = 4 * tuning.cellSize * 256
        let a = tuning.driftOffset(at: 0)
        let b = tuning.driftOffset(at: period / tuning.driftSpeed)
        #expect(abs(a.width - b.width) < 0.001)
    }

    // MARK: - Presets

    @Test func presets_saveLoadAndDelete() throws {
        let suiteName = "GradientPresetTests-\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }

        let store = GradientTuningStore(defaults: suite)
        store.tuning.cellSize = 7
        let saved = store.saveCurrentAsPreset(staticOn: true, ditherOn: false)

        store.tuning.cellSize = 3
        store.load(saved)
        #expect(store.tuning.cellSize == 7)

        store.delete(saved)
        #expect(store.savedPresets.isEmpty)
    }

    @Test func presets_surviveRelaunch() throws {
        let suiteName = "GradientPresetTests-\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }

        let store = GradientTuningStore(defaults: suite)
        store.tuning.cellSize = 9
        store.saveCurrentAsPreset(staticOn: false, ditherOn: true)

        let reloaded = GradientTuningStore(defaults: suite)
        #expect(reloaded.savedPresets.first?.tuning.cellSize == 9)
        // The effect state is half of what a preset means, so it has to survive too.
        #expect(reloaded.savedPresets.first?.ditherOn == true)
        #expect(reloaded.savedPresets.first?.staticOn == false)
    }

    /// RESET is meant to be safe to press. Losing every saved look to it would make it the most
    /// dangerous button in the sheet.
    @Test func reset_keepsPresets() throws {
        let suiteName = "GradientPresetTests-\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }

        let store = GradientTuningStore(defaults: suite)
        store.tuning.cellSize = 11
        store.saveCurrentAsPreset(staticOn: true, ditherOn: false)
        store.reset()

        #expect(store.tuning == .default)
        #expect(store.savedPresets.count == 1)
        #expect(store.savedPresets.first?.tuning.cellSize == 11)
    }

    // MARK: - The built-in preset

    /// ORIGINAL is the one tap back to the app's pre-experiment look, so it must always be there
    /// and always be first — including on a fresh install with nothing saved.
    @Test func presets_alwaysLeadWithOriginal() throws {
        let suiteName = "GradientPresetTests-\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }

        let store = GradientTuningStore(defaults: suite)
        #expect(store.presets.count == 1)
        #expect(store.presets.first == .original)

        store.saveCurrentAsPreset(staticOn: true, ditherOn: false)
        #expect(store.presets.first == .original)
        #expect(store.presets.count == 2)
    }

    /// What makes it *original*: stock palette **and** the quantizer off. A preset carrying only
    /// the colours would restore the palette and leave the static running, which is not the look.
    @Test func original_isTheStockPaletteWithTheEffectOff() {
        #expect(GradientPreset.original.tuning == .default)
        #expect(GradientPreset.original.staticOn == false)
        #expect(GradientPreset.original.ditherOn == false)

        let style = ButtonGradientStyle.resolve(
            staticOn: GradientPreset.original.staticOn,
            ditherOn: GradientPreset.original.ditherOn,
            tuning: GradientPreset.original.tuning
        )
        #expect(style == .mesh)
    }

    /// A stray long-press must not take the escape hatch with it.
    @Test func original_cannotBeDeleted() throws {
        let suiteName = "GradientPresetTests-\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }

        let store = GradientTuningStore(defaults: suite)
        store.delete(.original)
        #expect(store.presets.contains(.original))
    }

    /// Presets written before they carried the effect toggles must still load. They could only
    /// have been saved with the quantizer on, since the lab had no other mode.
    @Test func presets_decodeFromBeforeTheyCarriedEffectState() throws {
        let tuning = try JSONEncoder().encode(GradientTuning.default)
        let legacy = """
        [{"id":"\(UUID().uuidString)","tuning":\(String(data: tuning, encoding: .utf8)!)}]
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode([GradientPreset].self, from: legacy)
        #expect(decoded.count == 1)
        #expect(decoded[0].staticOn == true)
        #expect(decoded[0].isBuiltIn == false)
    }

    // MARK: - Forward compatibility

    /// A tuning stored before the lab grew halftone, split and levels must still load, with the
    /// new fields defaulted — otherwise every parameter added to the lab silently wipes whatever
    /// the user had tuned.
    @Test func decoding_toleratesABlobFromAnOlderBuild() throws {
        let legacy = """
        {"poleLightA":{"r":0.1,"g":0.2,"b":0.3},
         "poleDarkA":{"r":0.4,"g":0.5,"b":0.6},
         "poleLightB":{"r":0.1,"g":0.2,"b":0.3},
         "poleDarkB":{"r":0.4,"g":0.5,"b":0.6},
         "meshLight":{"r":0.1,"g":0.2,"b":0.3},
         "meshMid":{"r":0.4,"g":0.5,"b":0.6},
         "meshDark":{"r":0.7,"g":0.8,"b":0.9},
         "borderStartA":{"r":0,"g":0,"b":0},"borderEndA":{"r":0,"g":0,"b":0},
         "borderStartB":{"r":0,"g":0,"b":0},"borderEndB":{"r":0,"g":0,"b":0},
         "cellSize":5,"noiseAmount":1,"orderedAmount":0,
         "pulseDuration":4,"staticFrameRate":10,"borderRotationDuration":8}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(GradientTuning.self, from: legacy)

        // What was stored survives.
        #expect(decoded.cellSize == 5)
        #expect(decoded.poleLightA == RGBColor(r: 0.1, g: 0.2, b: 0.3))
        // What was not stored defaults rather than throwing.
        #expect(decoded.levels == GradientTuning.default.levels)
        #expect(decoded.halftoneAmount == GradientTuning.default.halftoneAmount)
        #expect(decoded.labelMode == GradientTuning.default.labelMode)
    }

    // MARK: - Camera role

    /// The fork's ground state: until the lab pulls them apart, the camera button renders
    /// pixel-identically to the primary — an untouched install cannot tell the fork happened.
    @Test func cameraPoles_defaultToThePrimaryPoles() {
        let tuning = GradientTuning.default
        let primary = tuning.polesRGB(at: 1.7)
        let camera = tuning.polesRGB(at: 1.7, role: .camera)
        #expect(primary.light == camera.light)
        #expect(primary.mid == camera.mid)
        #expect(primary.dark == camera.dark)
    }

    /// The feature itself: each role reads its own poles, and touching one leaves the other alone.
    @Test func poles_followTheirRole() {
        var tuning = GradientTuning.default
        let red = RGBColor(r: 1, g: 0, b: 0)
        tuning.cameraPoleLightA = red
        tuning.cameraPoleLightB = red

        #expect(tuning.polesRGB(at: 0, role: .camera).light == red)
        // The primary is untouched, so it must still lerp exactly as the stock tuning does —
        // compared against the same instant, since t=0 already sits mid-pulse.
        #expect(tuning.polesRGB(at: 0, role: .primary).light == GradientTuning.default.polesRGB(at: 0).light)
    }

    /// The camera icon is a glyph on a ground like any other: its colour must answer to the
    /// camera poles, not to whatever the primary button happens to be wearing.
    @Test func labelColor_auto_readsTheCameraGroundForTheCameraRole() {
        var tuning = GradientTuning.default
        let nearBlack = RGBColor(r: 0.08, g: 0.05, b: 0.14)
        tuning.cameraPoleLightA = nearBlack; tuning.cameraPoleLightB = nearBlack
        tuning.cameraPoleDarkA = nearBlack; tuning.cameraPoleDarkB = nearBlack

        #expect(tuning.labelColor(at: 0, role: .camera) == .white)
        #expect(tuning.labelColor(at: 0) == .black)
    }

    /// A blob from before the fork carries tuned primary poles and no camera keys. The camera
    /// poles must inherit the *stored* primary values — falling back to the stock defaults would
    /// snap the camera button to stock greens while every other button kept the user's palette.
    @Test func decoding_fillsMissingCameraPolesFromTheStoredPrimary() throws {
        let legacy = """
        {"poleLightA":{"r":0.1,"g":0.2,"b":0.3},
         "poleDarkA":{"r":0.4,"g":0.5,"b":0.6},
         "poleLightB":{"r":0.15,"g":0.25,"b":0.35},
         "poleDarkB":{"r":0.45,"g":0.55,"b":0.65},
         "cellSize":5}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(GradientTuning.self, from: legacy)
        #expect(decoded.cameraPoleLightA == RGBColor(r: 0.1, g: 0.2, b: 0.3))
        #expect(decoded.cameraPoleDarkA == RGBColor(r: 0.4, g: 0.5, b: 0.6))
        #expect(decoded.cameraPoleLightB == RGBColor(r: 0.15, g: 0.25, b: 0.35))
        #expect(decoded.cameraPoleDarkB == RGBColor(r: 0.45, g: 0.55, b: 0.65))
        // Mid poles were absent too, so they inherit the (defaulted) primary mids.
        #expect(decoded.cameraPoleMidA == decoded.poleMidA)
    }

    /// A camera key that *is* stored wins over the inheritance.
    @Test func decoding_storedCameraPolesBeatTheInheritance() throws {
        var tuning = GradientTuning.default
        tuning.poleLightA = RGBColor(r: 0.1, g: 0.2, b: 0.3)
        tuning.cameraPoleLightA = RGBColor(r: 0.9, g: 0.1, b: 0.1)

        let data = try JSONEncoder().encode(tuning)
        let decoded = try JSONDecoder().decode(GradientTuning.self, from: data)
        #expect(decoded.cameraPoleLightA == RGBColor(r: 0.9, g: 0.1, b: 0.1))
        #expect(decoded == tuning)
    }

    @Test func swiftSnippet_carriesTheCameraValues() {
        var tuning = GradientTuning.default
        tuning.cameraPoleDarkB = RGBColor(r: 0.625, g: 0.125, b: 0.25)

        #expect(tuning.swiftSnippet.contains("cameraPoleDarkB: RGBColor(r: 0.625, g: 0.125, b: 0.250)"))
    }

    // MARK: - Colour bridging

    /// `ColorPicker` can hand back Display P3 components outside 0–1, which reach a shader as
    /// out-of-gamut garbage unless they are clamped on the way in.
    @Test func rgbColor_clampsOutOfGamutComponents() {
        let wide = Color(.displayP3, red: 1.0, green: 0.0, blue: 0.0)
        let stored = RGBColor(wide)
        #expect((0...1).contains(stored.r))
        #expect((0...1).contains(stored.g))
        #expect((0...1).contains(stored.b))
    }

    @Test func rgbColor_lerpIsClampedAtBothEnds() {
        let a = RGBColor(r: 0, g: 0, b: 0)
        let b = RGBColor(r: 1, g: 1, b: 1)
        #expect(a.lerp(to: b, t: -1) == a)
        #expect(a.lerp(to: b, t: 2) == b)
        #expect(a.lerp(to: b, t: 0.5) == RGBColor(r: 0.5, g: 0.5, b: 0.5))
    }
}
