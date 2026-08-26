import Testing
import Foundation
@testable import Enhance

/// Guards the parts of MOTION LAB that a preview cannot show you: that a stored tuning survives
/// the lab growing new fields, and that "inherit the global" stays genuinely live rather than
/// quietly freezing into a copy.
struct MotionTuningTests {

    // MARK: - Inherit vs. frozen

    /// The distinction the whole global-curve design rests on. An inheriting animation must track
    /// the global *after* the global moves; an overridden one must not.
    @Test
    func effectiveCurve_nilInherits_andSetValueDoesNot() {
        var tuning = MotionTuning.default
        tuning.entranceCurve = nil
        tuning.tabCurve = MotionCurve(response: 0.1, dampingFraction: 0.4)

        tuning.globalCurve = MotionCurve(response: 0.55, dampingFraction: 0.9)

        #expect(tuning.entranceEffective == tuning.globalCurve)
        #expect(tuning.tabEffective == MotionCurve(response: 0.1, dampingFraction: 0.4))
    }

    /// A preset captured while an animation was inheriting must still be inheriting when it is
    /// loaded back — if `nil` were resolved on save, every preset would silently convert four
    /// inheriting animations into four frozen ones and the global would stop reaching them.
    @Test
    func preset_roundTrip_preservesInheritance() throws {
        var tuning = MotionTuning.default
        tuning.globalCurve = MotionCurve(response: 0.4, dampingFraction: 0.7)
        tuning.categorySwitchCurve = MotionCurve(response: 0.2, dampingFraction: 0.5)

        let preset = MotionPreset(id: UUID(), tuning: tuning)
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(MotionPreset.self, from: data)

        #expect(decoded.tuning.entranceCurve == nil)
        #expect(decoded.tuning.categorySwitchCurve == MotionCurve(response: 0.2, dampingFraction: 0.5))
        #expect(decoded.tuning == tuning)
    }

    // MARK: - Tolerant decoding

    /// The lab is expected to gain parameters mid-experiment. A blob written before a field
    /// existed must still decode, or an evening's tuning reverts to stock on the next launch.
    @Test
    func decode_blobMissingEveryOptionalField_fallsBackToDefaults() throws {
        let sparse = Data(#"{"entranceStagger": 0.08}"#.utf8)

        let decoded = try JSONDecoder().decode(MotionTuning.self, from: sparse)

        #expect(decoded.entranceStagger == 0.08)
        #expect(decoded.globalCurve == MotionTuning.default.globalCurve)
        #expect(decoded.tilePressScale == MotionTuning.default.tilePressScale)
        #expect(decoded.entranceCurve == nil)
        // The camera fields arrived after the editor ones; a pre-camera blob must keep the
        // launch's designed feel — including its frozen curve, which unlike the editor curves
        // falls back to the default rather than to inherit.
        #expect(decoded.cameraScaleFrom == MotionTuning.default.cameraScaleFrom)
        #expect(decoded.cameraCurve == MotionTuning.default.cameraCurve)
        #expect(decoded.cameraBottomPadding == MotionTuning.default.cameraBottomPadding)
    }

    @Test
    func decode_emptyObject_isExactlyTheDefault() throws {
        let decoded = try JSONDecoder().decode(MotionTuning.self, from: Data("{}".utf8))
        #expect(decoded == MotionTuning.default)
    }

    // MARK: - Defaults

    /// The contract that makes these experiments safe to leave in the build: with every flag on
    /// and nothing tuned, the geometry is inert, so the app looks exactly as it ships.
    @Test
    func defaultTuning_isVisuallyInert() {
        let tuning = MotionTuning.default
        #expect(tuning.entranceStagger == 0)
        #expect(tuning.entranceScale == 1)
        #expect(tuning.entranceOffsetY == 0)
        #expect(tuning.categorySwitchScale == 1)
        #expect(tuning.tabScaleFrom == 1)
        #expect(tuning.tilePressScale == 1)
        #expect(tuning.tileBrightnessDelta == 0)
    }

    /// `.default` is seeded from `Motion.panel`, the app's one shared chrome curve. If that
    /// constant moves, this should fail and force a deliberate decision rather than leaving the
    /// lab quietly seeded from a value the app no longer uses.
    @Test
    func defaultGlobalCurve_matchesTheAppsChromeCurve() {
        #expect(MotionTuning.default.globalCurve == MotionCurve(response: 0.3, dampingFraction: 0.6))
    }

    /// The gallery knobs have no inert value the way a scale of 1 is inert — their flags are what
    /// keep the app unchanged. What they must not be is *degenerate*: a zero-size reveal cell
    /// divides the grid into infinite cells, and a zero duration finishes before it starts.
    @Test
    func galleryDefaults_areUsableRatherThanDegenerate() {
        let tuning = MotionTuning.default
        #expect(tuning.revealCellSize >= 2)
        #expect(tuning.revealDuration > 0)
        #expect(tuning.parallaxSmoothing > 0 && tuning.parallaxSmoothing < 1)
    }

    // MARK: - Reveal identity

    /// The reveal is matched by asset identifier, not by grid index, so a refresh that reorders
    /// the grid cannot leave it building in the wrong GIF. `clearJustSaved` enforces the other
    /// half of that: a stale completion for an identifier that has since been replaced must not
    /// cancel the newer one.
    @Test
    @MainActor
    func clearJustSaved_ignoresAStaleIdentifier() {
        let manager = PhotoManager()
        manager.justSavedIdentifier = "second-save"

        manager.clearJustSaved("first-save")
        #expect(manager.justSavedIdentifier == "second-save")

        manager.clearJustSaved("second-save")
        #expect(manager.justSavedIdentifier == nil)
    }

    // MARK: - Snippet

    /// The snippet has to reproduce the inherit-vs-frozen split, not flatten every animation onto
    /// its resolved numbers — pasting a flattened block would convert inheritance into four
    /// independent curves without saying so.
    @Test
    func swiftSnippet_rendersNilOverridesAsNil() {
        var tuning = MotionTuning.default
        tuning.tilePressCurve = MotionCurve(response: 0.25, dampingFraction: 0.45)

        let snippet = tuning.swiftSnippet

        #expect(snippet.contains("entranceCurve: nil"))
        #expect(snippet.contains("tilePressCurve: MotionCurve(response: 0.250, dampingFraction: 0.450)"))
    }

    // MARK: - Curve sampling

    /// Under-damped curves ring past their target; critically damped ones never do. This is the
    /// property the graph exists to show, so it should be pinned rather than eyeballed.
    @Test
    func displacement_overshootsOnlyBelowCriticalDamping() {
        let bouncy = MotionCurve(response: 0.3, dampingFraction: 0.4)
        let critical = MotionCurve(response: 0.3, dampingFraction: 1.0)

        let samples = stride(from: 0.0, through: MotionCurve.graphWindow, by: 0.01)
        let bouncyPeak = samples.map { bouncy.displacement(atTime: $0) }.max() ?? 0
        let criticalPeak = samples.map { critical.displacement(atTime: $0) }.max() ?? 0

        #expect(bouncyPeak > 1.02)
        #expect(criticalPeak <= 1.0001)
    }

    /// Every branch starts at rest and arrives, including the over-damped one whose coefficients
    /// are the easiest of the three to get subtly wrong.
    @Test
    func displacement_startsAtZeroAndSettlesAtOne() {
        for damping in [0.3, 0.6, 1.0, 1.2] {
            let curve = MotionCurve(response: 0.25, dampingFraction: damping)
            #expect(abs(curve.displacement(atTime: 0)) < 0.0001,
                    "damping \(damping) should start at rest")
            #expect(abs(curve.displacement(atTime: 6) - 1) < 0.01,
                    "damping \(damping) should settle at its target")
        }
    }

    // MARK: - Store

    /// Presets are the reason RESET feels safe to press, so it must not take them with it.
    @Test
    func reset_clearsTuningButKeepsPresets() {
        let defaults = UserDefaults(suiteName: "MotionTuningTests.reset")!
        defaults.removePersistentDomain(forName: "MotionTuningTests.reset")
        let store = MotionTuningStore(defaults: defaults)

        store.tuning.globalCurve = MotionCurve(response: 0.5, dampingFraction: 0.5)
        store.saveCurrentAsPreset()

        store.reset()

        #expect(store.tuning == MotionTuning.default)
        #expect(store.savedPresets.count == 1)
        #expect(store.savedPresets[0].tuning.globalCurve == MotionCurve(response: 0.5, dampingFraction: 0.5))
    }

    /// ORIGINAL and SUGGESTED are the way back and the way in; a stray long-press must not be
    /// able to remove either.
    @Test
    func delete_ignoresBuiltInPresets() {
        let defaults = UserDefaults(suiteName: "MotionTuningTests.delete")!
        defaults.removePersistentDomain(forName: "MotionTuningTests.delete")
        let store = MotionTuningStore(defaults: defaults)

        store.delete(.original)
        store.delete(.suggested)

        #expect(store.presets.contains { $0.title == "ORIGINAL" })
        #expect(store.presets.contains { $0.title == "SUGGESTED" })
    }

    /// A tuned session must survive relaunch, which is the only reason the store persists at all.
    @Test
    func tuning_persistsAcrossStoreInstances() {
        let name = "MotionTuningTests.persist"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let first = MotionTuningStore(defaults: defaults)
        first.tuning.entranceStagger = 0.07

        let second = MotionTuningStore(defaults: defaults)
        #expect(second.tuning.entranceStagger == 0.07)
    }
}
