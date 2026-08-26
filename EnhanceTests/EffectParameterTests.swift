import Testing
import SwiftUI
@testable import Enhance

/// Pins the declarative parameter model against the hand-written label switches it
/// replaces, and guards the invariants the effect detail panel relies on.
struct EffectParameterTests {

    // MARK: - Label parity

    /// Every face filter's expected (primary, secondary) control labels, written out
    /// literally rather than derived, so this is a genuine pin rather than a tautology.
    /// Captured from the original `sliderLabel` / `secondSliderLabel` switches before
    /// they were moved behind `parameters`.
    private static let expectedFaceLabels: [FaceFilterType: (primary: String, secondary: String?)] = [
        .lazerEyes:     ("INTENSITY", "SIZE"),
        .googlyEyes:    ("SIZE", "SPEED"),
        .squeeze:       ("INTENSITY", nil),
        .handsome:      ("HANDSOMENESS", nil),
        .heartVignette: ("INTENSITY", "SIZE"),
        .heartEyes:     ("SIZE", "SPEED"),
        .thirdEye:      ("SIZE", "INTENSITY"),
        .fisheye:       ("INTENSITY", "SIZE"),
        .swirl:         ("INTENSITY", nil),
        .pixelate:      ("INTENSITY", nil),
        .ripple:        ("REDNESS", nil),
        .fadeToBW:      ("INTENSITY", nil),
        .chromaShift:   ("INTENSITY", nil),
        .rainbow:       ("INTENSITY", "SPEED"),
        .lensDistortion: ("INTENSITY", "REACH"),
        .bigHead:        ("INTENSITY", "VERTICAL POSITION")
    ]

    /// The table above must cover the enum — otherwise adding a case would silently
    /// escape every parity assertion below.
    @Test func expectedFaceLabels_coversEveryCase() {
        #expect(Self.expectedFaceLabels.count == FaceFilterType.allCases.count)
        for type in FaceFilterType.allCases {
            #expect(Self.expectedFaceLabels[type] != nil, "no expectation for \(type.rawValue)")
        }
    }

    /// The declarative list must produce exactly the labels captured in the table above,
    /// which is what makes the migration off the old switches provably label-for-label
    /// identical rather than merely plausible.
    @Test func faceFilter_parametersMatchTable() {
        for type in FaceFilterType.allCases {
            guard let expected = Self.expectedFaceLabels[type] else { continue }
            let params = type.parameters

            // COLOR leads when the filter has one; the first *slider* is still the primary.
            if let colorPicker = params.first(where: { $0.kind == .tintColor || $0.kind == .gradientStops }) {
                #expect(params.first?.id == colorPicker.id, "\(type.rawValue) must lead with COLOR")
            }
            let firstSlider = params.first { $0.kind == .slider }
            #expect(firstSlider?.id == EffectParameter.intensityID, "\(type.rawValue) must lead its sliders with intensity")
            #expect(firstSlider?.label == expected.primary, "\(type.rawValue) primary")

            let secondary = params.first { $0.id == EffectParameter.secondaryID }
            #expect(secondary?.label == expected.secondary, "\(type.rawValue) secondary")
        }
    }

    /// The face and visual second slots must use different ids — `sizeID` maps to
    /// `EffectOptions.size`, which face filters do not use.
    @Test func faceFilter_secondSlotUsesSecondaryIdNotSize() {
        let withSecond = FaceFilterType.allCases.filter { type in
            type.parameters.contains { $0.id == EffectParameter.secondaryID }
        }
        #expect(!withSecond.isEmpty)
        for type in withSecond {
            let ids = type.parameters.map(\.id)
            #expect(ids.contains(EffectParameter.secondaryID), "\(type.rawValue) missing secondary")
            #expect(!ids.contains(EffectParameter.sizeID), "\(type.rawValue) must not use sizeID")
        }
    }

    @Test func faceFilter_parameterDeclarationsAreWellFormed() {
        for type in FaceFilterType.allCases {
            let params = type.parameters
            #expect(!params.isEmpty, "\(type.rawValue) declares no parameters")
            #expect(params.count <= 5, "\(type.rawValue) declares \(params.count) parameters")

            let ids = params.map(\.id)
            #expect(Set(ids).count == ids.count, "\(type.rawValue) has duplicate parameter ids")

            let pickers = params.filter { $0.kind != .slider }
            #expect(pickers.count <= 1, "\(type.rawValue) declares more than one picker")
        }
    }

    /// LAZER EYES and THIRD EYE (both color-swatch pickers) are the only filters with a
    /// picker row; this fails loudly if another filter claims one without the panel gaining
    /// a matching row and a height budget for it.
    @Test func onlyLazerEyesAndThirdEyeDeclareAPicker() {
        let expectedPickerOwners: Set<FaceFilterType> = [.lazerEyes, .thirdEye]
        for type in FaceFilterType.allCases {
            let hasPicker = type.parameters.contains { $0.kind != .slider }
            #expect(hasPicker == expectedPickerOwners.contains(type), "\(type.rawValue) picker unexpected")
        }
    }

    /// THIRD EYE has three rows — a COLOR swatch picker, then SIZE and INTENSITY (ray count).
    /// COLOR is first as of 2026-08-13; the sliders keep their own order behind it.
    @Test func thirdEyeDeclaresColorSizeAndIntensity() {
        let params = FaceFilterType.thirdEye.parameters
        #expect(params.count == 3)
        #expect(params.first?.kind == .tintColor, "COLOR must lead")
        #expect(params.first?.label == "COLOR")
        let firstSlider = params.first { $0.kind == .slider }
        #expect(firstSlider?.id == EffectParameter.intensityID)
        #expect(firstSlider?.label == "SIZE")
        #expect(params.contains { $0.id == EffectParameter.secondaryID && $0.label == "INTENSITY" })
        let picker = params.first { $0.kind != .slider }
        #expect(picker?.kind == .tintColor)
        #expect(picker?.label == "COLOR")
    }

    // MARK: - Storage keys

    /// The namespace exists to stop two effect families colliding. `VisualEffectType`
    /// and `FaceFilterType` both have a `fisheye` case with rawValue "FISHEYE", and both
    /// declare a second control slot — so without namespacing their values would share a
    /// key and cross-wire, with no compile error and no obvious symptom.
    @Test func parameterKeys_areNamespacedPerEffectFamily() {
        // The collision this guards against is real, not hypothetical.
        #expect(VisualEffectType.fisheye.rawValue == FaceFilterType.fisheye.rawValue)

        let visual = EffectParameter.key(EffectParameter.intensityID, for: VisualEffectType.fisheye)
        let face = EffectParameter.key(EffectParameter.intensityID, for: FaceFilterType.fisheye)
        #expect(visual != face)

        #expect(VisualEffectType.parameterNamespace != FaceFilterType.parameterNamespace)
    }

    @Test func parameterKeys_differPerEffectAndPerParameter() {
        let fisheyeIntensity = EffectParameter.key(EffectParameter.intensityID, for: VisualEffectType.fisheye)
        let ditherIntensity = EffectParameter.key(EffectParameter.intensityID, for: VisualEffectType.dither)
        let fisheyeSize = EffectParameter.key(EffectParameter.sizeID, for: VisualEffectType.fisheye)

        #expect(fisheyeIntensity != ditherIntensity)
        #expect(fisheyeIntensity != fisheyeSize)
    }

    // MARK: - displayValue

    @Test func displayValue_mapsUnitRangeToDotCount() {
        #expect(EffectParameter.displayValue(0.0) == 0)
        #expect(EffectParameter.displayValue(0.05) == 1)
        #expect(EffectParameter.displayValue(0.5) == 10)
        #expect(EffectParameter.displayValue(1.0) == 20)
    }

    @Test func displayValue_clampsOutsideUnitRange() {
        #expect(EffectParameter.displayValue(-3.0) == 0)
        #expect(EffectParameter.displayValue(9.0) == EffectParameter.sliderSteps)
    }

    // MARK: - Slider quantisation

    /// Values snap to the dot lattice so the knob's integer is honest — a continuous
    /// value would read "10" across a range of knob positions. This is a real behaviour
    /// change from the old continuous sliders.
    @Test func quantise_snapsToDotPositions() {
        let steps = Double(EffectParameter.sliderSteps)
        for step in 1...EffectParameter.sliderSteps {
            let exact = Double(step) / steps
            #expect(ParameterSliderRow.quantise(exact) == exact, "step \(step) should be stable")
            // Nudging either side of a dot must land back on it.
            #expect(ParameterSliderRow.quantise(exact - 0.01) == exact, "step \(step) from below")
            #expect(ParameterSliderRow.quantise(exact + 0.01) == exact, "step \(step) from above")
        }
    }

    /// The floor is one step, not zero: effects treat a zero strength as "off", and the
    /// old sliders clamped to 0.05 for the same reason. 0.05 is exactly 1/20, so the
    /// lowest reachable value displays as "1".
    @Test func quantise_flooredAtOneStepNotZero() {
        let oneStep = 1.0 / Double(EffectParameter.sliderSteps)
        #expect(ParameterSliderRow.quantise(0.0) == oneStep)
        #expect(ParameterSliderRow.quantise(-5.0) == oneStep)
        #expect(EffectParameter.displayValue(ParameterSliderRow.quantise(0.0)) == 1)
    }

    /// The opposite floor, for rows whose zero is a real setting rather than "off" —
    /// a 0s pause is meaningful, an effect at zero strength is just disabled. The two
    /// floors are deliberate opposites, not an inconsistency.
    @Test func quantise_allowingZero_reachesZero() {
        #expect(ParameterSliderRow.quantise(0.0, allowingZero: true) == 0.0)
        #expect(ParameterSliderRow.quantise(-5.0, allowingZero: true) == 0.0)
        #expect(ParameterSliderRow.quantise(1.0, allowingZero: true) == 1.0)
    }

    @Test func quantise_clampsAboveOne() {
        #expect(ParameterSliderRow.quantise(1.0) == 1.0)
        #expect(ParameterSliderRow.quantise(7.5) == 1.0)
        #expect(EffectParameter.displayValue(ParameterSliderRow.quantise(9.0)) == EffectParameter.sliderSteps)
    }

    /// Every quantised value must round-trip through `displayValue` to a distinct
    /// integer, otherwise two knob positions would show the same number.
    @Test func quantise_producesDistinctDisplayValues() {
        let displayed = (1...EffectParameter.sliderSteps).map {
            EffectParameter.displayValue(ParameterSliderRow.quantise(Double($0) / Double(EffectParameter.sliderSteps)))
        }
        #expect(Set(displayed).count == displayed.count)
    }

    // MARK: - Declaration shape

    /// Invariants the detail panel depends on.
    ///
    /// The cap was 5, guarding "the panel's vertical budget against a future effect quietly
    /// overflowing". **Raised to 6 on 2026-08-12** for RISO, which has four genuinely
    /// independent scalars plus its spot colours. The budget it was guarding turned out to be
    /// elastic: ROADMAP §1a verified four rows on an SE 3 and the panel's scroll is accepted,
    /// so the cap now exists to force the *question* — does this effect really have six
    /// independent qualities? — rather than to describe a rendering limit.
    ///
    /// Note face filters are still capped at 5 above; nothing has needed to move that.
    @Test func visualEffect_parameterDeclarationsAreWellFormed() {
        for type in VisualEffectType.allCases {
            let params = type.parameters
            #expect(!params.isEmpty, "\(type.rawValue) declares no parameters")
            // 7 since 2026-08-18: BACKGROUND ONLY is appended to every selectable effect, which
            // takes RISO — already the widest panel — from six rows to seven. The scroll is
            // accepted (§1a, user's call 2026-08-12); what this cap guards is an effect quietly
            // growing *controls*, and the toggle is a modifier rather than a quality of the
            // effect, so it is the one row that is not evidence of that.
            #expect(params.count <= 7, "\(type.rawValue) declares \(params.count) parameters")
            // COLOR leads when the effect has one, and the first slider is always intensity.
            //
            // Specifically a *colour* picker. PIXELATE's `.pixelShape` is a picker row that is
            // not a colour, and it keeps its declared position among the sliders — the rule the
            // user set is about colour, not about pickers in general.
            if let colorPicker = params.first(where: { $0.kind == .tintColor || $0.kind == .gradientStops }) {
                #expect(params.first?.id == colorPicker.id, "\(type.rawValue) must lead with COLOR")
            }
            #expect(params.first { $0.kind == .slider }?.id == EffectParameter.intensityID,
                    "\(type.rawValue) must lead its sliders with intensity")

            let ids = params.map(\.id)
            #expect(Set(ids).count == ids.count, "\(type.rawValue) has duplicate parameter ids")

            // A toggle is not a picker. The rule being enforced is that at most one row opens a
            // *choice* of value — swatches, stops, a shape — because those are the tall rows.
            // A switch is a single fixed-size control and does not compete for that budget.
            let pickers = params.filter { $0.kind != .slider && $0.kind != .toggle }
            #expect(pickers.count <= 1, "\(type.rawValue) declares more than one picker")

            // BACKGROUND ONLY modifies everything above it, so it reads wrong interleaved with
            // the effect's own controls — it must come last, and there is only ever one.
            if params.contains(where: { $0.kind == .toggle }) {
                #expect(params.last?.kind == .toggle, "\(type.rawValue) must end with its toggle")
                #expect(params.filter { $0.kind == .toggle }.count == 1,
                        "\(type.rawValue) declares more than one toggle")
            }

            // `supportsColorPicker` is specifically about *colour*, so only the colour kinds
            // may agree with it. PIXELATE's `.pixelShape` is a picker row that is not a
            // colour picker, and conflating the two would either fail here or force
            // `colorPickerKind` to lie about an effect that has no colour.
            let colourPickers = params.filter { $0.kind == .tintColor || $0.kind == .gradientStops }
            #expect((colourPickers.first != nil) == type.supportsColorPicker,
                    "\(type.rawValue) colour picker disagrees with colorPickerKind")
        }
    }

    // MARK: - Panel fit

    /// THIRD EYE's three rows (COLOR + SIZE + INTENSITY) must not floor-and-overflow on the
    /// shortest supported panel, which would re-enable the scroll and let it steal slider
    /// drags. The panel on an iPhone SE 3 is ~190–200pt; at the roomy end a 3-row panel is
    /// not floored, so rows shrink to fit. (True on-device fit is a QA item.)
    @Test func panel_threeRowsFitWithoutScrollingOnShortPanel() {
        typealias L = AppConstants.Layout
        let available: CGFloat = 200
        let h = L.parameterRowHeight(forPanelHeight: available, rowCount: 3)
        // Not clamped to the floor — if it were, the rows would overflow into a scroll.
        #expect(h > L.parameterRowMinHeight, "3 rows floored at \(available)pt re-enables scroll")
        // The header counts as one more unit; the whole stack must fit the available height.
        let stack = CGFloat(3 + 1) * h + AppConstants.Spacing.small * 3 + AppConstants.Spacing.grid * 2
        #expect(stack <= available + 0.5)
    }

    // MARK: - Card sizing

    /// Cards scale with the space available rather than using a fixed constant, because
    /// the browse state has no scroll to fall back on when it overflows.
    @Test func effectCardSize_scalesWithAvailableHeightAndClamps() {
        typealias L = AppConstants.Layout

        // Roomy: capped at the design size, never larger.
        #expect(L.effectCardSize(forControlsHeight: 400) == L.effectCardMaxSize)

        // Cramped: floored, never smaller than legible.
        #expect(L.effectCardSize(forControlsHeight: 60) == L.effectCardMinSize)
        #expect(L.effectCardSize(forControlsHeight: 0) == L.effectCardMinSize)

        // In between: tracks the space, minus the tabs row and the 16pt gap it now holds
        // to the carousel (was `Spacing.small` before the 2026-08-15 margin pass).
        let mid = L.categoryTabsHeight + AppConstants.Spacing.grid + 90
        #expect(L.effectCardSize(forControlsHeight: mid) == 90)
    }

    /// Monotonic — more room never yields a smaller card.
    @Test func effectCardSize_isMonotonicInAvailableHeight() {
        typealias L = AppConstants.Layout
        var previous = L.effectCardSize(forControlsHeight: 0)
        for h in stride(from: CGFloat(0), through: 400, by: 10) {
            let size = L.effectCardSize(forControlsHeight: h)
            #expect(size >= previous)
            #expect(size >= L.effectCardMinSize && size <= L.effectCardMaxSize)
            previous = size
        }
    }
}
