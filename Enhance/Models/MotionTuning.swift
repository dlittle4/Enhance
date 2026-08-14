import SwiftUI

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

    // MARK: - Category switch (Idea 4)

    /// Scale the incoming card gallery grows from. 1 is a plain cross-fade.
    var categorySwitchScale: Double

    var categorySwitchCurve: MotionCurve?

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

    // MARK: - Defaults

    /// **Today's behaviour, exactly.** Every geometry knob is its inert value — no stagger, no
    /// scale, no press feedback — because that is what the app does now, and a default that
    /// quietly introduced motion would break the "flags off changes nothing" contract that makes
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
        entranceStagger: 0,
        entranceScale: 1,
        entranceOffsetY: 0,
        entranceCurve: nil,
        categorySwitchScale: 1,
        categorySwitchCurve: nil,
        tabScaleFrom: 1,
        tabCurve: nil,
        tilePressScale: 1,
        tileBrightnessDelta: 0,
        tilePressCurve: nil
    )

    /// The plan's proposed starting point — what the ideas describe, before anyone has judged
    /// them on a device. Not the default, because it is a proposal rather than current behaviour.
    static let suggested = MotionTuning(
        globalCurve: MotionCurve(response: 0.3, dampingFraction: 0.6),
        entranceStagger: 0.05,
        entranceScale: 0.92,
        entranceOffsetY: 12,
        entranceCurve: nil,
        categorySwitchScale: 0.96,
        categorySwitchCurve: MotionCurve(response: 0.22, dampingFraction: 0.82),
        tabScaleFrom: 0.7,
        tabCurve: MotionCurve(response: 0.22, dampingFraction: 0.6),
        tilePressScale: 0.95,
        tileBrightnessDelta: -0.05,
        tilePressCurve: MotionCurve(response: 0.25, dampingFraction: 0.45)
    )

    // MARK: - Derived

    /// The curve an animation actually runs on: its own if it has one, the global otherwise.
    func effectiveCurve(_ override: MotionCurve?) -> MotionCurve { override ?? globalCurve }

    var entranceEffective: MotionCurve { effectiveCurve(entranceCurve) }
    var categorySwitchEffective: MotionCurve { effectiveCurve(categorySwitchCurve) }
    var tabEffective: MotionCurve { effectiveCurve(tabCurve) }
    var tilePressEffective: MotionCurve { effectiveCurve(tilePressCurve) }

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
            categorySwitchScale: \(Self.number(categorySwitchScale)),
            categorySwitchCurve: \(Self.curve(categorySwitchCurve)),
            tabScaleFrom: \(Self.number(tabScaleFrom)),
            tabCurve: \(Self.curve(tabCurve)),
            tilePressScale: \(Self.number(tilePressScale)),
            tileBrightnessDelta: \(Self.number(tileBrightnessDelta)),
            tilePressCurve: \(Self.curve(tilePressCurve))
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
            categorySwitchScale: number(.categorySwitchScale, fallback.categorySwitchScale),
            categorySwitchCurve: curve(.categorySwitchCurve),
            tabScaleFrom: number(.tabScaleFrom, fallback.tabScaleFrom),
            tabCurve: curve(.tabCurve),
            tilePressScale: number(.tilePressScale, fallback.tilePressScale),
            tileBrightnessDelta: number(.tileBrightnessDelta, fallback.tileBrightnessDelta),
            tilePressCurve: curve(.tilePressCurve)
        )
    }
}
