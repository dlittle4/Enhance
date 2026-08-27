import Foundation
import Testing
@testable import Enhance

/// Guards the parts of BUTTON TEXT LAB a preview cannot show you: that the rotation's clock is
/// pure and lands where the labels say it does, that a stored tuning survives the lab growing new
/// fields, and that the export snippet round-trips what was tuned.
struct ButtonLabelTuningTests {

    /// A fixed rhythm the arithmetic below is easy to read against: 1s entrance, 2s hold,
    /// three phrases, so one full rotation is 9s.
    private var tuning: ButtonLabelTuning {
        var t = ButtonLabelTuning.default
        t.phrases = ["MAKE A GIF", "PICK A PHOTO", "MAKE IT MOVE"]
        t.entranceDuration = 1.0
        t.holdDuration = 2.0
        return t
    }

    // MARK: - The clock

    /// ENTRANCE means seconds. The presets finish entering at `entranceWindow` (0.7) of their
    /// progress, so one entrance-duration of elapsed time must land exactly there — scaling by
    /// anything else would make the slider lie by a factor of 0.7.
    @Test
    func phase_entranceDurationLandsOnTheEntranceWindow() {
        let mid = tuning.phase(at: 0.5)
        #expect(mid.phraseIndex == 0)
        #expect(abs(mid.progress - 0.35) < 1e-9)
        #expect(mid.alpha == 1)

        let settled = tuning.phase(at: 1.0)
        #expect(abs(settled.progress - TextAnimationType.entranceWindow) < 1e-9)
    }

    /// The rotation advances one phrase per cycle and wraps, and the settled text fades at the
    /// very end of each cycle so the swap is a beat rather than a cut.
    @Test
    func phase_rotatesThroughPhrasesAndFadesBeforeTheSwap() {
        #expect(tuning.phase(at: 3.5).phraseIndex == 1)
        #expect(tuning.phase(at: 6.5).phraseIndex == 2)
        #expect(tuning.phase(at: 9.5).phraseIndex == 0)

        // 0.1s before the swap to phrase 1: inside the 0.35s fade window.
        let fading = tuning.phase(at: 2.9)
        #expect(fading.phraseIndex == 0)
        #expect(fading.alpha < 1)
        #expect(fading.alpha > 0)

        // Mid-hold, the text must be fully present — a fade that leaks into the hold would make
        // every phrase read as translucent.
        #expect(tuning.phase(at: 2.0).alpha == 1)
    }

    /// `timeIntervalSinceReferenceDate` is the clock, and nothing guarantees a caller never hands
    /// this a time before the epoch — the maths must stay in range rather than mirroring.
    @Test
    func phase_negativeTimeStaysInRange() {
        let phase = tuning.phase(at: -0.25)
        #expect((0..<3).contains(phase.phraseIndex))
        #expect((0...1).contains(phase.progress))
        #expect((0...1).contains(phase.alpha))
    }

    /// Blank rows are storage, not content: they survive persistence so a half-typed row is not
    /// lost, but the clock must never allot them a beat of empty button.
    @Test
    func activePhrases_skipsBlankRowsAndTheClockFollows() {
        var t = tuning
        t.phrases = ["  ", "GO", "", "\n"]

        #expect(t.activePhrases == ["GO"])
        // One active phrase: every instant belongs to index 0.
        #expect(t.phase(at: 7.7).phraseIndex == 0)
    }

    /// Zero durations must not divide the clock by zero — the floors keep the maths finite even
    /// when a decoded blob carries garbage.
    @Test
    func phase_zeroDurationsAreFloored()  {
        var t = tuning
        t.entranceDuration = 0
        t.holdDuration = 0

        let phase = t.phase(at: 1.0)
        #expect((0...1).contains(phase.progress))
        #expect((0...1).contains(phase.alpha))
    }

    // MARK: - Tolerant decoding

    /// The lab is expected to gain parameters mid-experiment. A blob written before a field
    /// existed must still decode, or an evening's phrase-smithing reverts to stock on the next
    /// launch.
    @Test
    func decode_sparseBlobFallsBackToDefaults() throws {
        let sparse = Data(#"{"animation":"SPIN","holdDuration":4.5}"#.utf8)

        let decoded = try JSONDecoder().decode(ButtonLabelTuning.self, from: sparse)

        #expect(decoded.animation == .spin)
        #expect(decoded.holdDuration == 4.5)
        #expect(decoded.phrases == ButtonLabelTuning.default.phrases)
        #expect(decoded.entranceDuration == ButtonLabelTuning.default.entranceDuration)
        #expect(decoded.slideDirection == ButtonLabelTuning.default.slideDirection)
    }

    @Test
    func codable_roundTripsEverything() throws {
        var t = tuning
        t.animation = .ticker
        t.parameter = 0.85
        t.slideDirection = .down
        t.gridOrigin = .center

        let decoded = try JSONDecoder().decode(ButtonLabelTuning.self,
                                               from: JSONEncoder().encode(t))
        #expect(decoded == t)
    }

    // MARK: - Store

    /// The store persists as one blob under one key, against an injected scratch suite so this
    /// test cannot leak a tuned rotation into the app's own defaults.
    @Test
    func store_persistsAndResets() throws {
        let suiteName = "ButtonLabelTuningTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ButtonLabelTuningStore(defaults: defaults)
        store.tuning.animation = .flicker
        store.tuning.phrases = ["ONE", "TWO"]

        let reloaded = ButtonLabelTuningStore(defaults: defaults)
        #expect(reloaded.tuning.animation == .flicker)
        #expect(reloaded.tuning.phrases == ["ONE", "TWO"])

        reloaded.reset()
        #expect(reloaded.tuning == .default)
        #expect(defaults.data(forKey: ButtonLabelTuningStore.storageKey) == nil)
    }

    // MARK: - Export

    /// The snippet is the lab's deliverable: it must name the tuned values in compilable Swift,
    /// including a phrase that would otherwise break the string literal.
    @Test
    func swiftSnippet_carriesValuesAndEscapesPhrases() {
        var t = tuning
        t.animation = .typewriter
        t.phrases = ["SAY \"CHEESE\""]

        let snippet = t.swiftSnippet
        #expect(snippet.contains("animation: .typewriter"))
        #expect(snippet.contains(#""SAY \"CHEESE\"""#))
        #expect(snippet.contains("entranceDuration: 1.000"))
        #expect(snippet.contains("holdDuration: 2.000"))
    }
}
