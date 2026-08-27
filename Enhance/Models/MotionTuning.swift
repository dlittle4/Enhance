import SwiftUI

/// What plays over the canvas while a GIF is being generated.
///
/// Four concepts rather than one setting, because "indicate that work is happening" has no
/// single right answer and they can only be told apart by watching them *(user's call,
/// 2026-08-15)*. All three pixel styles reuse the gallery's `PixelReveal.metal` and
/// `Pixellate.metal` rather than inventing a fourth pixel treatment — the app already has a
/// pixel vocabulary and the generating moment should speak it.
enum GeneratingStyle: String, Codable, CaseIterable, Identifiable, Equatable {
    /// Today's plain `ProgressView`. The baseline every other option is judged against.
    case spinner = "SPIN"
    /// Blocks assemble the photo over and over, the same build the gallery plays on save.
    case build = "BUILD"
    /// The photo sits coarsely pixelated and sharpens, repeatedly — the app's own name as a
    /// loading state.
    case resolve = "ENHANCE"
    /// Blocks flicker in and out on a re-rolled scatter each pass, so the image never settles.
    case scramble = "SCRAMBLE"

    var id: String { rawValue }

    /// Whether this style draws the pixel overlay at all. `spinner` does not, which is what
    /// keeps the shipped behaviour reachable from the picker.
    var usesPixels: Bool { self != .spinner }
}

/// A spring, editable and drawable as a curve rather than as two abstract numbers.
///
/// Deliberately still a *spring* — `response` + `dampingFraction` — rather than a cubic-bezier
/// timing curve alongside it. `Design/Motion.swift` already made this call once, for chrome:
/// "the app's chrome moves on one curve... Three different springs used to do that job for no
/// reason anyone could name." A bezier would be more directly draggable as a shape, but it would
/// be a second animation vocabulary next to call sites that say `.spring(...)` everywhere else.
struct MotionCurve: Codable, Equatable {

    /// Roughly the time to the first settle, in seconds. SwiftUI's own parameter, passed through.
    var response: Double

    /// 1 is critically damped — no overshoot. Below 1 overshoots and rings; that ring is what
    /// "bouncy" means, and it is the whole reason the tile press wants its own curve.
    var dampingFraction: Double

    /// The animation these numbers actually describe. Every real call site uses this rather than
    /// re-deriving a spring from the components, so the lab and the app cannot disagree.
    var animation: Animation {
        .spring(response: max(0.01, response), dampingFraction: max(0, dampingFraction))
    }

    // MARK: - Sampling, for the graph

    /// Position at `seconds`, where 0 is the start and 1 is the settled value.
    ///
    /// A closed-form damped harmonic oscillator — the standard model a spring animation follows,
    /// solved for a unit step from rest. **This is not a verified reproduction of SwiftUI's own
    /// internal curve**, which is not public: it is good for comparing two settings against each
    /// other, and should not be trusted to predict exact on-device frame timing. That is why
    /// `MotionCurveGraphView` draws a dot animated with the *real* `animation` beside the plotted
    /// line — when the two disagree, the dot is right.
    ///
    /// The three branches are the three genuinely different behaviours of the underlying ODE, not
    /// three approximations of one: below critical damping the system rings, at critical damping
    /// it returns fastest without ringing, and above it crawls in from two decaying exponentials.
    /// Collapsing them into one formula divides by zero at ζ = 1.
    func displacement(atTime seconds: Double) -> Double {
        let omega = 2 * Double.pi / max(0.01, response)
        let zeta = max(0, dampingFraction)
        let t = max(0, seconds)

        if zeta < 1 {
            let damped = omega * (1 - zeta * zeta).squareRoot()
            let decay = exp(-zeta * omega * t)
            return 1 - decay * (cos(damped * t) + (zeta * omega / damped) * sin(damped * t))
        } else if zeta == 1 {
            return 1 - exp(-omega * t) * (1 + omega * t)
        } else {
            let root = omega * (zeta * zeta - 1).squareRoot()
            let slow = -zeta * omega + root
            let fast = -zeta * omega - root
            // Coefficients that satisfy x(0) = 0 and x'(0) = 0 for a unit step.
            return 1 - (fast * exp(slow * t) - slow * exp(fast * t)) / (fast - slow)
        }
    }

    /// How long the graph should plot, in seconds.
    ///
    /// Fixed rather than scaled per curve, so two curves on shared axes can be *compared*: a
    /// slower response has to visibly lag, which it cannot do if each curve is normalised to fill
    /// the same width. Long enough that a 0.6s response still settles inside it.
    static let graphWindow: Double = 1.4

    var swiftLiteral: String {
        String(format: "MotionCurve(response: %.3f, dampingFraction: %.3f)", response, dampingFraction)
    }
}

/// Every knob on the view-transition animations, in one value.
///
/// This exists for the same reason `GradientTuning` does: the right stagger, scale and springiness
/// are not knowable from a spec — they have to be found by dragging a control and watching the
/// result. So the values move here, MOTION LAB edits them live, and `swiftSnippet` hands back a
/// paste-ready block of Swift once a feel is settled.
///
/// **This type is scaffolding.** When an animation graduates, its snippet becomes the literal in
/// `EditorView` / `EffectCardView` / `Design/Motion.swift` and this file, `MotionTuningStore` and
/// `MotionLabView` all go — which is why it is one struct behind one `UserDefaults` key.
///
/// ## The global curve, and nudging away from it
///
/// One `globalCurve` is the default every animation rides. Each animation may override it, and an
/// override is a **full frozen `MotionCurve`, not a delta**. A delta would keep moving every time
/// the global was retuned, silently, after that animation had already been judged and settled —
/// the opposite of what a micro-adjustment should mean. `nil` (inherit) is what makes the global
/// cascade; a set value is a decision that retuning the global must not disturb.
struct MotionTuning: Codable, Equatable {

    /// The curve every animation below uses until it is explicitly overridden.
    ///
    /// Seeded from `Motion.panel` — today's one shared chrome curve — so a lab session that
    /// touches nothing changes nothing.
    var globalCurve: MotionCurve

    // MARK: - Editor entrance (Idea 1)

    /// Seconds between one chrome element starting and the next.
    var entranceStagger: Double

    /// Scale each chrome element starts from. 1 is no scale.
    var entranceScale: Double

    /// Points below its final position each chrome element starts at. 0 is no movement.
    var entranceOffsetY: Double

    /// `nil` inherits `globalCurve`.
    var entranceCurve: MotionCurve?

    /// Whether the photo builds itself out of pixel blocks as the editor opens, instead of
    /// simply fading in with the rest of the chrome *(user's call, 2026-08-15)*.
    ///
    /// The canvas is a `UIViewRepresentable` around a `UIScrollView`, and SwiftUI's Metal
    /// renderer cannot sample UIKit-backed content — so this is not a `layerEffect` on the
    /// canvas but an opaque `PixelBuildOverlay` drawn over it and removed when it completes.
    /// See that view for why that is the only shape this can take.
    var canvasPixelEntrance: Bool

    /// Block edge in points for the canvas build. Larger than the gallery's, because the canvas
    /// is 325pt against a 114pt thumbnail and the same cell reads as noise at that size.
    var canvasRevealCell: Double

    /// Seconds for the canvas to finish building in.
    var canvasRevealTime: Double

    // MARK: - Gallery zoom (Idea 1's flight)

    /// The flight of a tapped gallery cell's picture into the canvas — the pace
    /// `GalleryView.ZoomFlight` interpolates its measured rects on.
    ///
    /// `nil` inherits `globalCurve`, but the default freezes its own: the flight shipped on the
    /// chrome's 0.3s spring and read as an instant appear on device *(user's call, 2026-08-26)* —
    /// 90% of that spring's travel is over in ~130ms. A hero transition needs to be *watched*,
    /// not just not-noticed, which is the opposite of what chrome timing optimises for.
    var zoomFlightCurve: MotionCurve?

    // MARK: - Category switch (Idea 4)

    /// Scale the incoming card gallery grows from. 1 is a plain cross-fade.
    var categorySwitchScale: Double

    var categorySwitchCurve: MotionCurve?

    /// Seconds between one effect card starting its entrance and the next, when a carousel
    /// arrives. 0 is inert — every card lands at once, which is the shipped behaviour.
    var cascadeStagger: Double

    // MARK: - Tab selection (Idea 5)

    /// Scale the selected tab's capsule grows from. 1 is a plain colour cross-fade.
    var tabScaleFrom: Double

    var tabCurve: MotionCurve?

    // MARK: - Effect tile press (Idea 6)

    /// Scale an effect card shrinks to while held. 1 is no press feedback.
    var tilePressScale: Double

    /// Brightness shift while held. Negative dims. 0 is no dimming.
    var tileBrightnessDelta: Double

    /// Expected to end up below the global's damping — that ring *is* the bounce.
    var tilePressCurve: MotionCurve?

    // MARK: - Generating (Idea 7)

    /// Which animation plays over the canvas while a GIF is being generated.
    var generatingStyle: GeneratingStyle

    /// Block edge in points for the generating animation.
    var generatingCell: Double

    /// Seconds for one pass of the generating animation. It loops until generation finishes,
    /// which takes as long as it takes — so this is the *cadence*, not the total.
    var generatingCycle: Double

    // MARK: - Save reveal (Idea 2)

    /// Cell edge in points for the pixel-dissolve. Blocky rather than literal pixels *(user's
    /// call)* — see `PixelReveal.metal` for why single pixels read as static at thumbnail size.
    var revealCellSize: Double

    /// Seconds for the grid cell to finish building in.
    var revealDuration: Double

    /// Seconds the empty placeholder box holds on screen before the pixels start filling in.
    /// The beat between "a new cell arrived" and "this is what's in it" — without it the two
    /// phases read as one event and the arrival is missed.
    var revealDelay: Double

    // MARK: - Gallery ambience (Idea 3)

    /// The *deepest* cell's tilt drift, in points. 0 disables the parallax entirely.
    ///
    /// Applied per cell *(user's call, 2026-08-14)*: each GIF gets a stable fraction of this
    /// derived from its identity (`GalleryView.cellDepth`), so neighbours separate under tilt
    /// and the grid reads as a stack of cards at different depths.
    var parallaxMagnitude: Double

    /// How heavily raw device motion is smoothed, 0…1 — higher is calmer.
    ///
    /// Accelerometer output is noisy enough that feeding it straight to a transform makes the
    /// grid twitch. This is the weight kept from the previous sample each tick.
    var parallaxSmoothing: Double

    // MARK: - Camera launch (IN-APP CAMERA experiment)

    /// Scale the viewfinder card grows from when the camera opens. The transition is anchored
    /// on the camera button's spot (`CameraOverlayView.launchAnchor`), so this is how small the
    /// card starts inside the button. 1 is a plain fade with no growth.
    ///
    /// **Live by default, unlike the editor knobs above.** The camera is itself an experiment
    /// behind `FeatureFlags.cameraCapture` — the flag is what keeps the app unchanged, so these
    /// follow the ambient-effects precedent: the default is the shape the transition should
    /// take the first time someone turns the camera on.
    var cameraScaleFrom: Double

    /// `nil` inherits `globalCurve`.
    var cameraCurve: MotionCurve?

    /// Points between the viewfinder card's bottom edge and the physical bottom of the
    /// screen — where the card comes to rest. The Figma spec sits it 18pt off the hardware
    /// edge, below the safe area.
    var cameraBottomPadding: Double

    /// Block edge in points the camera feed's resolve starts at. The feed's first frames are
    /// drawn through `Pixellate.metal` at this cell size and swept to sharp — the ENHANCE
    /// treatment as the camera's own loading state. Bolder than the canvas's 18 because the
    /// viewfinder is a full-width card and coarse blocks are the whole read.
    var cameraRevealCell: Double

    /// Seconds for the feed to sweep from `cameraRevealCell` to sharp. 0 turns the resolve
    /// off entirely — the feed fades in plainly, exactly the pre-resolve behaviour.
    var cameraRevealTime: Double

    // MARK: - Defaults

    /// **The adopted profile** *(user's call, 2026-08-26)*: the values dialled in on device and
    /// pulled from its defaults, replacing the original inert baseline. The flags are still what
    /// keep the app unchanged when off — a default carrying motion never plays until its flag
    /// says so, which is the contract that makes
    /// these experiments safe to leave in.
    ///
    /// The one honest asterisk: with a flag *on* and these defaults, timing moves from the current
    /// `easeInOut` to `globalCurve`'s spring. That is a deliberate part of Idea 4 rather than an
    /// accident — a spring is what the plan is testing — and it is why the flags exist.
    ///
    /// `MotionPreset.suggested` carries the plan's proposed starting values, one tap away, so
    /// nobody has to dial them in from zero to see the intended effect.
    static let `default` = MotionTuning(
        globalCurve: MotionCurve(response: 0.3, dampingFraction: 0.6),
        entranceStagger: 0.05,
        entranceScale: 0.92,
        entranceOffsetY: 12,
        entranceCurve: nil,
        canvasPixelEntrance: false,
        canvasRevealCell: 18,
        canvasRevealTime: 1.2,
        zoomFlightCurve: MotionCurve(response: 0.5, dampingFraction: 0.8),
        categorySwitchScale: 1,
        categorySwitchCurve: MotionCurve(response: 0.22, dampingFraction: 0.82),
        cascadeStagger: 0.06,
        tabScaleFrom: 0.7,
        tabCurve: MotionCurve(response: 0.22, dampingFraction: 0.6),
        tilePressScale: 0.95,
        tileBrightnessDelta: 0,
        tilePressCurve: MotionCurve(response: 0.25, dampingFraction: 0.45),
        generatingStyle: .build,
        generatingCell: 22,
        generatingCycle: 1.1,
        revealCellSize: 6,
        revealDuration: 1.6,
        revealDelay: 0.35,
        parallaxMagnitude: 4,
        parallaxSmoothing: 0.882,
        cameraScaleFrom: 0.461,
        cameraCurve: MotionCurve(response: 0.385, dampingFraction: 0.595),
        cameraBottomPadding: 48,
        cameraRevealCell: 40,
        cameraRevealTime: 0.9
    )

    /// The plan's proposed starting point — what the ideas describe, before anyone has judged
    /// them on a device. Not the default, because it is a proposal rather than current behaviour.
    static let suggested = MotionTuning(
        globalCurve: MotionCurve(response: 0.3, dampingFraction: 0.6),
        entranceStagger: 0.05,
        entranceScale: 0.92,
        entranceOffsetY: 12,
        entranceCurve: nil,
        canvasPixelEntrance: true,
        canvasRevealCell: 18,
        canvasRevealTime: 1.2,
        zoomFlightCurve: MotionCurve(response: 0.5, dampingFraction: 0.8),
        categorySwitchScale: 0.96,
        categorySwitchCurve: MotionCurve(response: 0.22, dampingFraction: 0.82),
        cascadeStagger: 0.06,
        tabScaleFrom: 0.7,
        tabCurve: MotionCurve(response: 0.22, dampingFraction: 0.6),
        tilePressScale: 0.95,
        tileBrightnessDelta: -0.05,
        tilePressCurve: MotionCurve(response: 0.25, dampingFraction: 0.45),
        generatingStyle: .build,
        generatingCell: 22,
        generatingCycle: 1.1,
        revealCellSize: 6,
        revealDuration: 1.6,
        revealDelay: 0.35,
        parallaxMagnitude: 4,
        parallaxSmoothing: 0.9,
        cameraScaleFrom: 0.05,
        cameraCurve: MotionCurve(response: 0.38, dampingFraction: 0.8),
        cameraBottomPadding: 18,
        cameraRevealCell: 40,
        cameraRevealTime: 0.9
    )

    // MARK: - Derived

    /// The curve an animation actually runs on: its own if it has one, the global otherwise.
    func effectiveCurve(_ override: MotionCurve?) -> MotionCurve { override ?? globalCurve }

    var entranceEffective: MotionCurve { effectiveCurve(entranceCurve) }
    var zoomFlightEffective: MotionCurve { effectiveCurve(zoomFlightCurve) }
    var categorySwitchEffective: MotionCurve { effectiveCurve(categorySwitchCurve) }
    var tabEffective: MotionCurve { effectiveCurve(tabCurve) }
    var tilePressEffective: MotionCurve { effectiveCurve(tilePressCurve) }
    var cameraEffective: MotionCurve { effectiveCurve(cameraCurve) }

    // MARK: - Export

    /// A paste-ready Swift block naming the properties it replaces.
    ///
    /// Renders the overrides **honestly** — `nil` for an inherited curve, a full literal for a set
    /// one — so the pasted snippet reproduces the inherit-vs-frozen split rather than flattening
    /// every animation onto its resolved numbers. Flattening would silently convert four
    /// inheriting animations into four independent ones, and the next global retune would then
    /// reach none of them.
    var swiftSnippet: String {
        """
        // Copied from MOTION LAB.
        static let tuned = MotionTuning(
            globalCurve: \(globalCurve.swiftLiteral),
            entranceStagger: \(Self.number(entranceStagger)),
            entranceScale: \(Self.number(entranceScale)),
            entranceOffsetY: \(Self.number(entranceOffsetY)),
            entranceCurve: \(Self.curve(entranceCurve)),
            canvasPixelEntrance: \(canvasPixelEntrance),
            canvasRevealCell: \(Self.number(canvasRevealCell)),
            canvasRevealTime: \(Self.number(canvasRevealTime)),
            zoomFlightCurve: \(Self.curve(zoomFlightCurve)),
            categorySwitchScale: \(Self.number(categorySwitchScale)),
            categorySwitchCurve: \(Self.curve(categorySwitchCurve)),
            cascadeStagger: \(Self.number(cascadeStagger)),
            tabScaleFrom: \(Self.number(tabScaleFrom)),
            tabCurve: \(Self.curve(tabCurve)),
            tilePressScale: \(Self.number(tilePressScale)),
            tileBrightnessDelta: \(Self.number(tileBrightnessDelta)),
            tilePressCurve: \(Self.curve(tilePressCurve)),
            generatingStyle: .\(generatingStyle),
            generatingCell: \(Self.number(generatingCell)),
            generatingCycle: \(Self.number(generatingCycle)),
            revealCellSize: \(Self.number(revealCellSize)),
            revealDuration: \(Self.number(revealDuration)),
            revealDelay: \(Self.number(revealDelay)),
            parallaxMagnitude: \(Self.number(parallaxMagnitude)),
            parallaxSmoothing: \(Self.number(parallaxSmoothing)),
            cameraScaleFrom: \(Self.number(cameraScaleFrom)),
            cameraCurve: \(Self.curve(cameraCurve)),
            cameraBottomPadding: \(Self.number(cameraBottomPadding)),
            cameraRevealCell: \(Self.number(cameraRevealCell)),
            cameraRevealTime: \(Self.number(cameraRevealTime))
        )
        """
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func curve(_ curve: MotionCurve?) -> String {
        curve?.swiftLiteral ?? "nil"
    }
}

// MARK: - Tolerant decoding

/// Decoding that fills in whatever the stored blob is missing.
///
/// Synthesised `Codable` throws on an absent key, which would mean that every time the lab gains a
/// parameter, the tuning already in `UserDefaults` stops decoding and an evening's work reverts to
/// stock on the next launch. The lab exists *to* grow these fields, so that is the expected path
/// rather than an edge case. Same reasoning, and same shape, as `GradientTuning`'s.
///
/// In an extension rather than the main declaration so the memberwise initialiser survives —
/// `MotionTuning.default` is built with it.
extension MotionTuning {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = MotionTuning.default

        func number(_ key: CodingKeys, _ or: Double) -> Double {
            ((try? container.decodeIfPresent(Double.self, forKey: key)) ?? nil) ?? or
        }

        func flag(_ key: CodingKeys, _ or: Bool) -> Bool {
            ((try? container.decodeIfPresent(Bool.self, forKey: key)) ?? nil) ?? or
        }

        /// Absent and explicitly-null both mean inherit, which is also the honest reading of a
        /// blob written before this field existed.
        func curve(_ key: CodingKeys) -> MotionCurve? {
            ((try? container.decodeIfPresent(MotionCurve.self, forKey: key)) ?? nil)
        }

        self.init(
            globalCurve: curve(.globalCurve) ?? fallback.globalCurve,
            entranceStagger: number(.entranceStagger, fallback.entranceStagger),
            entranceScale: number(.entranceScale, fallback.entranceScale),
            entranceOffsetY: number(.entranceOffsetY, fallback.entranceOffsetY),
            entranceCurve: curve(.entranceCurve),
            canvasPixelEntrance: flag(.canvasPixelEntrance, fallback.canvasPixelEntrance),
            canvasRevealCell: number(.canvasRevealCell, fallback.canvasRevealCell),
            canvasRevealTime: number(.canvasRevealTime, fallback.canvasRevealTime),
            // The camera's rule, not the editor curves': absent means "the default's frozen
            // curve" rather than inherit. A blob written before this field existed predates the
            // flight having any pacing of its own, and reverting those installs to the global
            // chrome spring would re-create the instant-appear this knob was added to fix.
            zoomFlightCurve: curve(.zoomFlightCurve) ?? fallback.zoomFlightCurve,
            categorySwitchScale: number(.categorySwitchScale, fallback.categorySwitchScale),
            categorySwitchCurve: curve(.categorySwitchCurve),
            cascadeStagger: number(.cascadeStagger, fallback.cascadeStagger),
            tabScaleFrom: number(.tabScaleFrom, fallback.tabScaleFrom),
            tabCurve: curve(.tabCurve),
            tilePressScale: number(.tilePressScale, fallback.tilePressScale),
            tileBrightnessDelta: number(.tileBrightnessDelta, fallback.tileBrightnessDelta),
            tilePressCurve: curve(.tilePressCurve),
            generatingStyle: ((try? container.decodeIfPresent(GeneratingStyle.self, forKey: .generatingStyle)) ?? nil) ?? fallback.generatingStyle,
            generatingCell: number(.generatingCell, fallback.generatingCell),
            generatingCycle: number(.generatingCycle, fallback.generatingCycle),
            revealCellSize: number(.revealCellSize, fallback.revealCellSize),
            revealDuration: number(.revealDuration, fallback.revealDuration),
            revealDelay: number(.revealDelay, fallback.revealDelay),
            parallaxMagnitude: number(.parallaxMagnitude, fallback.parallaxMagnitude),
            parallaxSmoothing: number(.parallaxSmoothing, fallback.parallaxSmoothing),
            cameraScaleFrom: number(.cameraScaleFrom, fallback.cameraScaleFrom),
            // Unlike the editor curves, absent means "the default's frozen curve" rather than
            // inherit — a blob written before this field existed should keep the camera's
            // designed feel, not pick up whatever the global happens to be.
            cameraCurve: curve(.cameraCurve) ?? fallback.cameraCurve,
            cameraBottomPadding: number(.cameraBottomPadding, fallback.cameraBottomPadding),
            cameraRevealCell: number(.cameraRevealCell, fallback.cameraRevealCell),
            cameraRevealTime: number(.cameraRevealTime, fallback.cameraRevealTime)
        )
    }
}
