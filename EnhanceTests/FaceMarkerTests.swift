import Testing
import CoreGraphics
import Foundation
@testable import Enhance

/// The face-marker experiments' rules and persistence.
///
/// Everything here is about *decisions* — whether a marker exists, which face the spotlight cuts
/// around, whether stored tuning survives a new knob — because those are the parts a screenshot
/// cannot check and the parts that were wrong in the overlay this replaces.
struct FaceMarkerTests {

    private func faces(_ count: Int) -> [(id: UUID, rect: CGRect)] {
        (0..<count).map { index in
            (id: UUID(), rect: CGRect(x: 0.1 * Double(index), y: 0.4, width: 0.2, height: 0.2))
        }
    }

    // MARK: - The legacy path is genuinely unchanged

    /// The A/B is only fair if "all flags off" is the old behaviour exactly. The old overlay
    /// treated *no selection* as every face selected, and that is preserved deliberately — it is
    /// the thing being compared against, not a bug to fix on the legacy side.
    @Test func legacyOptions_withNoSelection_markEveryFaceAsTarget() {
        let markers = FaceMarkerPlan.markers(for: faces(3), selectedIndex: nil, options: .legacy)

        // Hoisted out of `#expect` because `allSatisfy` is `rethrows`, which the macro expansion
        // cannot prove non-throwing.
        let allTargets = markers.allSatisfy(\.isTarget)
        let allLegacySelected = markers.allSatisfy(\.legacyIsSelected)
        let noneSoloed = markers.allSatisfy { !$0.isSoloed }

        #expect(markers.count == 3)
        #expect(allTargets)
        #expect(allLegacySelected)
        #expect(noneSoloed)
    }

    /// Legacy draws a box over a lone face — the behaviour CALM removes.
    @Test func legacyOptions_withASingleFace_stillDrawsAMarker() {
        let markers = FaceMarkerPlan.markers(for: faces(1), selectedIndex: nil, options: .legacy)
        #expect(markers.count == 1)
    }

    // MARK: - Calm

    /// Most photos have one face, and one face is not a choice. The effect still targets it —
    /// `activeFaces` returns the lone face whether or not it was tapped — so this removes chrome
    /// without removing capability.
    @Test func calm_withASingleFace_drawsNothing() {
        let options = FaceMarkerOptions(calm: true)
        #expect(FaceMarkerPlan.markers(for: faces(1), selectedIndex: nil, options: options).isEmpty)
        #expect(FaceMarkerPlan.markers(for: faces(1), selectedIndex: 0, options: options).isEmpty)
    }

    @Test func calm_withNoFaces_drawsNothing() {
        let options = FaceMarkerOptions(calm: true)
        #expect(FaceMarkerPlan.markers(for: faces(0), selectedIndex: nil, options: options).isEmpty)
    }

    /// Two faces *is* a choice, so the markers come back.
    @Test func calm_withTwoFaces_drawsBoth() {
        let options = FaceMarkerOptions(calm: true)
        #expect(FaceMarkerPlan.markers(for: faces(2), selectedIndex: nil, options: options).count == 2)
    }

    // MARK: - Target vs soloed

    /// The distinction the old tuple could not express: with one face soloed, the others are
    /// neither targets nor soloed, and previously all three would have drawn identically.
    @Test func soloingAFace_marksOnlyThatOneAsTargetAndSoloed() {
        let markers = FaceMarkerPlan.markers(for: faces(3), selectedIndex: 1, options: .legacy)

        #expect(markers[0].isTarget == false)
        #expect(markers[1].isTarget == true)
        #expect(markers[2].isTarget == false)

        #expect(markers.filter(\.isSoloed).map(\.index) == [1])
    }

    @Test func markerIndices_followDetectionOrder() {
        let markers = FaceMarkerPlan.markers(for: faces(4), selectedIndex: nil, options: .legacy)
        #expect(markers.map(\.index) == [0, 1, 2, 3])
    }

    // MARK: - Spotlight

    @Test func spotlight_withNothingSoloed_doesNotDraw() {
        let options = FaceMarkerOptions(spotlight: true)
        let markers = FaceMarkerPlan.markers(for: faces(3), selectedIndex: nil, options: options)
        #expect(FaceMarkerPlan.spotlightRect(in: markers, options: options) == nil)
    }

    @Test func spotlight_whenOff_doesNotDrawEvenWithASoloedFace() {
        let markers = FaceMarkerPlan.markers(for: faces(3), selectedIndex: 2, options: .legacy)
        #expect(FaceMarkerPlan.spotlightRect(in: markers, options: .legacy) == nil)
    }

    @Test func spotlight_withASoloedFace_cutsAroundThatFace() {
        let options = FaceMarkerOptions(spotlight: true)
        let input = faces(3)
        let markers = FaceMarkerPlan.markers(for: input, selectedIndex: 2, options: options)

        #expect(FaceMarkerPlan.spotlightRect(in: markers, options: options) == input[2].rect)
    }

    /// CALM hiding a lone face's marker must also take the spotlight with it — otherwise the photo
    /// dims around a face the user never chose, with no visible control to undo it.
    @Test func spotlight_underCalmWithASingleFace_doesNotDraw() {
        let options = FaceMarkerOptions(calm: true, spotlight: true)
        let markers = FaceMarkerPlan.markers(for: faces(1), selectedIndex: 0, options: options)
        #expect(FaceMarkerPlan.spotlightRect(in: markers, options: options) == nil)
    }

    // MARK: - Options

    @Test func legacyOptions_areAllOff() {
        #expect(FaceMarkerOptions.legacy.isLegacy)
        #expect(FaceMarkerOptions(calm: true).isLegacy == false)
    }

    // MARK: - DEFAULT as a control

    /// The state the row exists to name: before it was listed, "every flag off" silently *was* the
    /// current approach and nothing in the UI said so.
    @Test func defaultRow_isCheckedOnlyWhenNoVariantIsOn() {
        #expect(FaceMarkerOptions.legacy.isDefault)
        #expect(FaceMarkerOptions(calm: true).isDefault == false)
        #expect(FaceMarkerOptions(reticle: true).isDefault == false)
        #expect(FaceMarkerOptions(spotlight: true).isDefault == false)
        #expect(FaceMarkerOptions(scanline: true).isDefault == false)
        #expect(FaceMarkerOptions(hidden: true).isDefault == false)
    }

    /// Unchecking DEFAULT turns the current approach *off* rather than snapping back to it
    /// *(user's call)* — which is what makes it a control instead of a label.
    @Test func uncheckingDefault_hidesTheMarkersEntirely() {
        var options = FaceMarkerOptions.legacy
        options.toggleDefault()

        #expect(options.hidden)
        #expect(options.isDefault == false)
        #expect(FaceMarkerPlan.markers(for: faces(3), selectedIndex: nil, options: options).isEmpty)
    }

    @Test func checkingDefault_clearsEveryVariant() {
        var options = FaceMarkerOptions(calm: true, reticle: true, spotlight: true, scanline: true)
        options.toggleDefault()

        #expect(options.isDefault)
        #expect(options == .legacy)
    }

    /// Coming back from the hidden state via DEFAULT rather than via a variant.
    @Test func checkingDefault_whileHidden_returnsToTheCurrentApproach() {
        var options = FaceMarkerOptions(hidden: true)
        options.toggleDefault()

        #expect(options.isDefault)
        #expect(options.hidden == false)
    }

    /// Turning a variant on has to leave the hidden state, or the row would appear checked while
    /// drawing nothing — indistinguishable from being ignored.
    @Test func checkingAVariant_whileHidden_stopsHiding() {
        var options = FaceMarkerOptions(hidden: true)
        options.toggle(\.reticle)

        #expect(options.reticle)
        #expect(options.hidden == false)
        #expect(options.isDefault == false)
    }

    /// Undoing the last experiment goes back to what shipped, not to nothing — that is the
    /// direction the user is heading when they untick it.
    @Test func uncheckingTheLastVariant_fallsBackToDefault() {
        var options = FaceMarkerOptions(calm: true)
        options.toggle(\.calm)

        #expect(options.isDefault)
        #expect(options.hidden == false)
    }

    /// Hiding beats every other rule, including the ones that would otherwise draw.
    @Test func hidden_suppressesMarkersInEveryCombination() {
        for calm in [false, true] {
            for reticle in [false, true] {
                for spotlight in [false, true] {
                    let options = FaceMarkerOptions(
                        calm: calm, reticle: reticle, spotlight: spotlight, hidden: true
                    )
                    let markers = FaceMarkerPlan.markers(for: faces(3), selectedIndex: 1, options: options)
                    #expect(markers.isEmpty, "combination \(options) drew a marker while hidden")
                    #expect(FaceMarkerPlan.spotlightRect(in: markers, options: options) == nil)
                }
            }
        }
    }

    /// All eight combinations are legal — the variants compose rather than exclude, and nothing in
    /// the plan should start rejecting one of them silently.
    @Test func everyCombinationOfVariants_producesMarkers() {
        for calm in [false, true] {
            for reticle in [false, true] {
                for spotlight in [false, true] {
                    let options = FaceMarkerOptions(calm: calm, reticle: reticle, spotlight: spotlight)
                    let markers = FaceMarkerPlan.markers(for: faces(2), selectedIndex: 0, options: options)
                    #expect(markers.count == 2, "combination \(options) dropped a marker")
                }
            }
        }
    }

    // MARK: - Tuning geometry

    @Test func markerRect_atUnitScale_isTheInputRect() {
        var tuning = FaceMarkerTuning.default
        tuning.markerScale = 1.0
        let rect = CGRect(x: 10, y: 20, width: 100, height: 200)
        #expect(tuning.markerRect(for: rect) == rect)
    }

    /// Inflation is about the centre, so the marker stays on the face rather than sliding off it.
    @Test func markerRect_inflatesAboutTheCentre() {
        var tuning = FaceMarkerTuning.default
        tuning.markerScale = 1.5
        let rect = CGRect(x: 10, y: 20, width: 100, height: 200)
        let inflated = tuning.markerRect(for: rect)

        #expect(abs(inflated.midX - rect.midX) < 0.001)
        #expect(abs(inflated.midY - rect.midY) < 0.001)
        #expect(abs(inflated.width - 150) < 0.001)
        #expect(abs(inflated.height - 300) < 0.001)
    }

    /// A tiny face still shows a corner rather than a dot.
    @Test func bracketArm_hasAFloor() {
        let tuning = FaceMarkerTuning.default
        #expect(tuning.bracketArm(forSide: 1) >= 4)
    }

    @Test func bracketArm_isClampedToHalfTheSide() {
        var tuning = FaceMarkerTuning.default
        tuning.bracketLength = 5.0     // past the point where four brackets become a rectangle
        #expect(tuning.bracketArm(forSide: 100) <= 50)
    }

    // MARK: - Entrance choreography

    private func sequenced(
        _ order: FaceMarkerTuning.EntranceOrder,
        passes: Double = 2,
        stagger: Double = 0,
        repeats: Bool = true
    ) -> FaceMarkerTuning {
        var tuning = FaceMarkerTuning.default
        tuning.entranceOrder = order
        tuning.entranceScanPasses = passes
        tuning.entranceStagger = stagger
        tuning.scanRepeats = repeats
        tuning.scanlineDuration = 1.0
        tuning.lockOnDuration = 0.25
        return tuning
    }

    @Test func together_startsEverythingAtOnce() {
        let timeline = sequenced(.together).entranceTimeline(faceIndex: 0)

        #expect(timeline.scanStart == 0)
        #expect(timeline.reticleStart == 0)
    }

    /// **The sequence the whole feature was asked for**: sweep the face twice, then lock on.
    @Test func scanFirst_holdsTheReticleUntilThePassesAreDone() {
        let timeline = sequenced(.scanFirst, passes: 2).entranceTimeline(faceIndex: 0)

        #expect(timeline.scanStart == 0)
        // Two passes at a 1s pass duration.
        #expect(abs(timeline.reticleStart - 2.0) < 0.0001)
    }

    @Test func scanFirst_passCountMovesTheLock() {
        let two = sequenced(.scanFirst, passes: 2).entranceTimeline(faceIndex: 0)
        let four = sequenced(.scanFirst, passes: 4).entranceTimeline(faceIndex: 0)

        #expect(four.reticleStart > two.reticleStart)
        #expect(abs(four.reticleStart - 4.0) < 0.0001)
    }

    /// The two must never overlap under this order — that is what `together` is for.
    @Test func reticleFirst_startsTheScanOnlyOnceTheLockHasSettled() {
        let timeline = sequenced(.reticleFirst).entranceTimeline(faceIndex: 0)

        #expect(timeline.reticleStart == 0)
        #expect(abs(timeline.scanStart - 0.25) < 0.0001)
        #expect(timeline.scanStart > timeline.reticleStart)
    }

    /// A reticle that arrives before the scan it was meant to follow is invisible in a screenshot
    /// and obvious here, which is the reason this arithmetic is a pure function.
    @Test func scanFirst_neverLocksOnBeforeItHasScanned() {
        for passes in stride(from: 1.0, through: 6.0, by: 1.0) {
            let timeline = sequenced(.scanFirst, passes: passes).entranceTimeline(faceIndex: 0)
            #expect(timeline.reticleStart > timeline.scanStart, "passes \(passes) locked on too early")
        }
    }

    @Test func stagger_offsetsEachFaceInTurn() {
        let tuning = sequenced(.scanFirst, stagger: 0.2)

        let first = tuning.entranceTimeline(faceIndex: 0)
        let second = tuning.entranceTimeline(faceIndex: 1)
        let third = tuning.entranceTimeline(faceIndex: 2)

        #expect(first.scanStart == 0)
        #expect(abs(second.scanStart - 0.2) < 0.0001)
        #expect(abs(third.scanStart - 0.4) < 0.0001)
        // The whole sequence shifts, not just its first beat.
        #expect(abs(third.reticleStart - second.reticleStart - 0.2) < 0.0001)
    }

    @Test func zeroStagger_startsEveryFaceTogether() {
        let tuning = sequenced(.scanFirst, stagger: 0)
        #expect(tuning.entranceTimeline(faceIndex: 0) == tuning.entranceTimeline(faceIndex: 3))
    }

    @Test func repeatingScan_neverStops() {
        #expect(sequenced(.scanFirst, repeats: true).entranceTimeline(faceIndex: 0).scanStop == nil)
    }

    /// An entrance-only scan runs exactly the passes it was given, then stops.
    @Test func nonRepeatingScan_stopsAfterItsPasses() {
        let timeline = sequenced(.scanFirst, passes: 3, repeats: false).entranceTimeline(faceIndex: 0)
        #expect(timeline.scanStop.map { abs($0 - 3.0) < 0.0001 } == true)
    }

    /// Under LOCK FIRST the stop has to be measured from when the scan actually began, not from
    /// zero, or an entrance-only sweep is cut short by the lock-on delay.
    @Test func nonRepeatingScan_underReticleFirst_measuresFromItsOwnStart() {
        let timeline = sequenced(.reticleFirst, passes: 2, repeats: false).entranceTimeline(faceIndex: 0)
        #expect(timeline.scanStop.map { abs($0 - (0.25 + 2.0)) < 0.0001 } == true)
    }

    @Test func entranceOrder_survivesAJSONRoundTrip() throws {
        var tuning = FaceMarkerTuning.default
        tuning.entranceOrder = .reticleFirst
        tuning.scanRepeats = false

        let decoded = try JSONDecoder().decode(
            FaceMarkerTuning.self, from: try JSONEncoder().encode(tuning)
        )
        #expect(decoded.entranceOrder == .reticleFirst)
        #expect(decoded.scanRepeats == false)
    }

    // MARK: - Persistence

    private func scratchDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "FaceMarkerTests-\(UUID().uuidString)")!
        return suite
    }

    @Test func store_withNoStoredTuning_startsAtDefaults() {
        let store = FaceMarkerTuningStore(defaults: scratchDefaults())
        #expect(store.tuning == .default)
    }

    @Test func store_persistsAndReloadsTuning() {
        let defaults = scratchDefaults()
        let store = FaceMarkerTuningStore(defaults: defaults)
        store.tuning.spotlightDimming = 0.8
        store.tuning.bracketLength = 0.42

        let reloaded = FaceMarkerTuningStore(defaults: defaults)
        #expect(abs(reloaded.tuning.spotlightDimming - 0.8) < 0.0001)
        #expect(abs(reloaded.tuning.bracketLength - 0.42) < 0.0001)
    }

    @Test func store_reset_returnsToDefaultsAndClearsStorage() {
        let defaults = scratchDefaults()
        let store = FaceMarkerTuningStore(defaults: defaults)
        store.tuning.spotlightDimming = 0.9
        store.reset()

        #expect(store.tuning == .default)
        #expect(defaults.data(forKey: FaceMarkerTuningStore.storageKey) == nil)
    }

    /// **The reason `init(from:)` is hand-written.** A blob written before a knob existed must
    /// still decode, or every parameter added to the lab silently discards an evening of tuning on
    /// the next launch. A lab exists to grow its fields, so this is the expected path.
    @Test func tuning_decodesABlobMissingNewerKeys() throws {
        let partial = """
        {"autoHideDelay": 4.5, "spotlightDimming": 0.7}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(FaceMarkerTuning.self, from: partial)

        #expect(abs(decoded.autoHideDelay - 4.5) < 0.0001)
        #expect(abs(decoded.spotlightDimming - 0.7) < 0.0001)
        // Everything absent falls back rather than throwing.
        #expect(abs(decoded.bracketLength - FaceMarkerTuning.default.bracketLength) < 0.0001)
        #expect(decoded.showsIndexLabel == FaceMarkerTuning.default.showsIndexLabel)
    }

    @Test func tuning_roundTripsThroughJSON() throws {
        var tuning = FaceMarkerTuning.default
        tuning.lockOnScale = 1.31
        tuning.showsIndexLabel = false

        let data = try JSONEncoder().encode(tuning)
        let decoded = try JSONDecoder().decode(FaceMarkerTuning.self, from: data)

        #expect(decoded == tuning)
    }

    /// The snippet is the graduation path — it must name every field, or a settled look is copied
    /// out incomplete and the missing knobs silently revert to defaults.
    @Test func swiftSnippet_namesEveryTunableField() {
        let snippet = FaceMarkerTuning.default.swiftSnippet
        for field in ["autoHideDelay", "restingOpacity", "flashDuration", "minimumTapTarget",
                      "quietStroke",
                      "bracketLength", "bracketThickness", "markerScale", "lockOnScale",
                      "lockOnDuration", "showsIndexLabel", "labelSize", "unselectedOpacity",
                      "scanlineDuration", "scanlineOpacity", "scanlineHeight",
                      "entranceOrder", "entranceScanPasses", "entranceStagger", "scanRepeats",
                      "spotlightDimming", "spotlightRadiusScale", "spotlightFeather"] {
            #expect(snippet.contains(field), "snippet is missing \(field)")
        }
    }
}
