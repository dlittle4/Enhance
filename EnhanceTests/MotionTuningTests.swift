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
        // The resolve intro arrived after the launch knobs; a pre-resolve blob keeps the
        // designed sweep rather than losing it to a decode failure.
        #expect(decoded.cameraRevealCell == MotionTuning.default.cameraRevealCell)
        #expect(decoded.cameraRevealTime == MotionTuning.default.cameraRevealTime)
        // The zoom flight follows the camera's rule: a blob from before the flight had its own
        // pacing must pick up the frozen default, not fall back to the fast chrome spring the
        // knob exists to escape.
        #expect(decoded.zoomFlightCurve == MotionTuning.default.zoomFlightCurve)
    }

    /// A stored blob with no curve keys decodes those curves as *inherit*, not as the
    /// default's frozen overrides — a user who set an animation back to USE GLOBAL encodes
    /// `nil` as an absent key, and resurrecting the adopted profile's frozen curve there
    /// would undo their choice on every launch. Everything else falls back to the default.
    /// (A fresh install never decodes at all: the store hands out `.default` directly, frozen
    /// curves included — the reset test below pins that.)
    @Test
    func decode_emptyObject_isTheDefaultWithInheritedEditorCurves() throws {
        let decoded = try JSONDecoder().decode(MotionTuning.self, from: Data("{}".utf8))

        var expected = MotionTuning.default
        expected.entranceCurve = nil
        expected.categorySwitchCurve = nil
        expected.tabCurve = nil
        expected.tilePressCurve = nil
        #expect(decoded == expected)
    }

    // MARK: - Defaults

    /// The default is no longer inert: it is the adopted on-device profile *(user's call,
    /// 2026-08-26)*. The flags remain the off-switch — a tuned default never plays until its
    /// flag says so — and what this pins is that the adopted numbers do not drift by accident.
    @Test
    func defaultTuning_isTheAdoptedProfile() {
        let tuning = MotionTuning.default
        #expect(tuning.entranceStagger == 0.05)
        #expect(tuning.entranceScale == 0.92)
        #expect(tuning.entranceOffsetY == 12)
        #expect(tuning.tabScaleFrom == 0.7)
        #expect(tuning.tilePressScale == 0.95)
        #expect(tuning.cameraScaleFrom == 0.461)
        #expect(tuning.cameraBottomPadding == 48)
    }

    /// `.default` is seeded from `Motion.panel`, the app's one shared chrome curve. If that
    /// constant moves, this should fail and force a deliberate decision rather than leaving the
    /// lab quietly seeded from a value the app no longer uses.
    @Test
    func defaultGlobalCurve_matchesTheAppsChromeCurve() {
        #expect(MotionTuning.default.globalCurve == MotionCurve(response: 0.3, dampingFraction: 0.6))
    }

    /// The flight's default is frozen, and *slower* than the chrome — on the chrome's spring the
    /// zoom finished its travel in ~130ms and read as the editor simply appearing *(user's device
    /// pass, 2026-08-26)*. Inheriting the global, or drifting back under it, would re-create
    /// exactly that.
    @Test
    func defaultZoomFlight_isFrozenAndSlowerThanTheChrome() throws {
        let tuning = MotionTuning.default
        let flight = try #require(tuning.zoomFlightCurve)
        #expect(flight.response > tuning.globalCurve.response)
        #expect(tuning.zoomFlightEffective == flight)
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
        // The camera resolve's cell must stay a visible block; its time may legally be 0 —
        // that is the knob's own OFF — but never negative.
        #expect(tuning.cameraRevealCell >= 2)
        #expect(tuning.cameraRevealTime >= 0)
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
