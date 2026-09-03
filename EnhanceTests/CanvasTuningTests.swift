import Testing
import Foundation
@testable import Enhance

/// CANVAS LAB's tuning: the store round-trips, the scrub arithmetic wraps the right way, and
/// overdrive reaches the effects only while its flag is on.
struct CanvasTuningTests {

    private func scratchDefaults() -> UserDefaults {
        let suite = "CanvasTuningTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - Store

    @Test func storeOpensOnDefaultsAndRoundTrips() {
        let defaults = scratchDefaults()
        let store = CanvasTuningStore(defaults: defaults)
        #expect(store.tuning == .default)

        store.tuning.scrubSpan = 420
        store.tuning.overdriveMax = 2.0
        let reopened = CanvasTuningStore(defaults: defaults)
        #expect(reopened.tuning.scrubSpan == 420)
        #expect(reopened.tuning.overdriveMax == 2.0)

        reopened.reset()
        #expect(reopened.tuning == .default)
        #expect(defaults.data(forKey: CanvasTuningStore.storageKey) == nil)
    }

    @Test func snippetNamesEveryKnob() {
        let snippet = CanvasTuning.default.swiftSnippet
        for name in ["scrubSpan", "scrubTickEvery", "overdriveMax", "overdriveGain", "overdriveGlitchRate"] {
            #expect(snippet.contains(name), Comment(rawValue: name))
        }
    }

    // MARK: - Scrub

    @Test func dragRightAdvancesAndLeftRewinds() {
        // 300pt per 30 frames: 10pt per frame.
        #expect(CanvasTuning.scrubbedFrame(from: 5, dragX: 40, span: 300, frameCount: 30) == 9)
        #expect(CanvasTuning.scrubbedFrame(from: 5, dragX: -20, span: 300, frameCount: 30) == 3)
    }

    @Test func scrubWrapsAtBothEnds() {
        #expect(CanvasTuning.scrubbedFrame(from: 28, dragX: 50, span: 300, frameCount: 30) == 3)
        #expect(CanvasTuning.scrubbedFrame(from: 2, dragX: -50, span: 300, frameCount: 30) == 27)
        // A whole loop lands back where it started.
        #expect(CanvasTuning.scrubbedFrame(from: 7, dragX: 300, span: 300, frameCount: 30) == 7)
    }

    @Test func scrubToleratesEmptyAndDegenerate() {
        #expect(CanvasTuning.scrubbedFrame(from: 0, dragX: 100, span: 300, frameCount: 0) == 0)
        #expect(CanvasTuning.scrubbedFrame(from: 0, dragX: 100, span: 0, frameCount: 10) == 0)
    }

    // MARK: - Overdrive

    @Test func quantiseHonoursTheCeiling() {
        #expect(ParameterSliderRow.quantise(1.4) == 1.0)
        #expect(ParameterSliderRow.quantise(1.4, ceiling: 1.5) == 1.4)
        #expect(ParameterSliderRow.quantise(9.0, ceiling: 1.5) == 1.5)
        // Still on the 1/20 lattice past the end.
        #expect(ParameterSliderRow.quantise(1.23, ceiling: 2) == 1.25)
    }

    @Test func overdriveGainOnlyAppliesPastTheEnd() {
        #expect(ParameterSliderRow.overdriven(0.5, gain: 4) == 0.5)
        #expect(ParameterSliderRow.overdriven(1.0, gain: 4) == 1.0)
        #expect(abs(ParameterSliderRow.overdriven(1.1, gain: 4) - 1.4) < 1e-9)
    }

    @Test func stepCountsPastTheLastDotUnderOverdrive() {
        #expect(ParameterSliderRow.step(of: 1.4, steps: 20) == 20)
        #expect(ParameterSliderRow.step(of: 1.4, steps: 20, ceiling: 1.5) == 28)
    }

    @Test func glitchIsDeterministicAndKeepsLength() {
        let a = ParameterSliderRow.glitched("24", rate: 1, seed: 12345)
        let b = ParameterSliderRow.glitched("24", rate: 1, seed: 12345)
        #expect(a == b)
        #expect(a.count == 2)
        #expect(a != "24")
        #expect(ParameterSliderRow.glitched("24", rate: 0, seed: 12345) == "24")
    }

    @Test func windowExtrapolatesAboveOneButNotBelowZero() {
        let window = ParameterWindow(min: 0.2, max: 0.6, defaultValue: 0.4)
        #expect(abs(window.remapAllowingOverdrive(1.0) - 0.6) < 1e-9)
        #expect(abs(window.remapAllowingOverdrive(1.5) - 0.8) < 1e-9)
        #expect(abs(window.remapAllowingOverdrive(-1) - 0.2) < 1e-9)
        // The plain remap keeps its clamp — the effects lab's own contract.
        #expect(abs(window.remap(1.5) - 0.6) < 1e-9)
    }

    @Test func clampSliderCeilingFollowsTheFlag() {
        let key = FeatureFlags.sliderOverdriveKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set(false, forKey: key)
        #expect(EffectParameter.clampSlider(1.4) == 1.0)
        #expect(EffectParameter.clampSlider(-0.2) == 0.0)

        UserDefaults.standard.set(true, forKey: key)
        let ceiling = max(1, CanvasTuningStore.shared.tuning.overdriveMax)
        #expect(EffectParameter.clampSlider(9.0) == ceiling)
        #expect(EffectParameter.clampSlider(0.7) == 0.7)
    }
}
