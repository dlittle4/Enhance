import Testing
import Foundation
@testable import Enhance

/// Contract tests for `HeadMaskTuning` and its store.
///
/// The load-bearing claim is the first one: **`.default` is the shipped baseline.** The lab
/// writes whatever it writes, but a fresh install must render exactly as the approved ea96ce3
/// geometry plus the chin cut did — these pins are what turns "should" into a test failure when
/// someone nudges a default while tuning.
struct HeadMaskTuningTests {

    @Test func defaultTuning_isTheApprovedBaseline() {
        let d = HeadMaskTuning.default
        // ea96ce3's effective ellipse at the slider midpoint: coverage 1.525 applied as a
        // half-extent → 3.05 face-widths full span.
        #expect(d.ellipseWidth == 3.05)
        #expect(d.ellipseHeight == 3.05)
        #expect(d.centerYOffset == 0)
        #expect(d.feather == 0.35)
        // The approved chin cut: face-box bottom edge, fading over a third of a face-height.
        #expect(d.chinCutOffset == -0.5)
        #expect(d.chinFade == 0.35)
        // The jaw approach's own numbers, matching what was hardcoded before they were exposed.
        #expect(d.jawDrop == 0.12)
        #expect(d.jawFeather == 0.08)
        // ea96ce3's growth ceiling and pivot.
        #expect(d.growthMax == 0.55)
        #expect(d.pivotY == 0.30)
    }

    @Test func store_roundTripsThroughDefaults() {
        let suite = UserDefaults(suiteName: "headMaskTuningTests")!
        suite.removePersistentDomain(forName: "headMaskTuningTests")

        let store = HeadMaskTuningStore(defaults: suite)
        store.tuning.ellipseWidth = 2.2
        store.tuning.chinCutOffset = -0.8

        let reloaded = HeadMaskTuningStore(defaults: suite)
        #expect(reloaded.tuning.ellipseWidth == 2.2)
        #expect(reloaded.tuning.chinCutOffset == -0.8)
    }

    @Test func reset_returnsToDefaultAndClearsStorage() {
        let suite = UserDefaults(suiteName: "headMaskTuningTests.reset")!
        suite.removePersistentDomain(forName: "headMaskTuningTests.reset")

        let store = HeadMaskTuningStore(defaults: suite)
        store.tuning.feather = 0.9
        store.reset()

        #expect(store.tuning == .default)
        #expect(suite.data(forKey: HeadMaskTuningStore.storageKey) == nil)
    }
}
