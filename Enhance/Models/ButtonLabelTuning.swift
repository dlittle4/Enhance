import CoreGraphics
import Foundation

/// Every knob on the MAKE A GIF button's animated label, in one value.
///
/// The experiment: the primary CTA's text plays one of the photo text-effect entrances
/// (`TextAnimationType`) and rotates through a set of phrases. Which preset, which phrases and
/// what rhythm cannot be specified in advance — they have to be typed in and watched — so the
/// values live here, BUTTON TEXT LAB edits them live, and `swiftSnippet` hands back paste-ready
/// Swift once a look is settled.
///
/// **This type is scaffolding.** When the experiment graduates, its snippet becomes constants on
/// the button, and this file, `ButtonLabelTuningStore` and `ButtonTextLabView` all go — the same
/// contract `GradientTuning` states. Colour is deliberately *not* here: the label wears whatever
/// `GradientTuning.labelColor` measures against the button's own gradient, so the one contrast
/// answer serves both the plain and the animated label *(user's call, 2026-08-26)*.
struct ButtonLabelTuning: Codable, Equatable {

    // MARK: - Content

    /// The rotation, in play order. Edited as free text in the lab; entries that trim to nothing
    /// are kept in storage (half-typed rows must survive a relaunch) but skipped by `activePhrases`.
    var phrases: [String]

    /// Which photo text-effect entrance the label plays. The presets are reused wholesale —
    /// same evaluator, same tiles — so a preset tuned here is exactly the preset users see on
    /// their GIFs.
    var animation: TextAnimationType

    /// The preset's single tunable, `0…1` — BOUNCE, STAGGER, SPEED… depending on `animation`,
    /// exactly as `TextOverlay.tuning` carries it for the photo pipeline.
    var parameter: Double

    /// SLIDE's entry edge. Stored even while another preset is active so switching away and back
    /// remembers the choice, mirroring `TextOverlay.slideDirection`.
    var slideDirection: TextSlideDirection

    /// GRID's fill origin, kept on the same terms as `slideDirection`.
    var gridOrigin: TextGridOrigin

    // MARK: - Rhythm

    /// Seconds the entrance takes to play. This maps onto the preset's own clock: presets finish
    /// entering at `TextAnimationType.entranceWindow` of their progress, and `phase(at:)` scales
    /// so that moment lands exactly here.
    var entranceDuration: Double

    /// Seconds the settled phrase stays before the next one enters. The tail of the hold is spent
    /// fading out — see `phase(at:)` — so the swap reads as a beat rather than a hard cut.
    var holdDuration: Double

    // MARK: - Defaults

    /// A starting point, not a verdict: TYPEWRITER because a message being typed is the most
    /// legible way to say "this text is alive" at 16pt, and phrases that keep MAKE A GIF first so
    /// the button leads with its actual job.
    static let `default` = ButtonLabelTuning(
        phrases: ["MAKE A GIF", "PICK A PHOTO", "MAKE IT MOVE"],
        animation: .typewriter,
        parameter: 0.5,
        slideDirection: .up,
        gridOrigin: .top,
        entranceDuration: 1.1,
        holdDuration: 2.4
    )

    // MARK: - Derived

    /// The phrases that actually render, trimmed. A whitespace-only entry is not a phrase — the
    /// rasterizer would return nil for it and the rotation would show a blank beat.
    var activePhrases: [String] {
        phrases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Floors that keep the maths finite rather than opinions about taste: a zero entrance would
    /// divide by zero, and a zero hold would fade out a phrase that never settled.
    var effectiveEntrance: Double { max(0.2, entranceDuration) }
    var effectiveHold: Double { max(0.3, holdDuration) }

    /// One phrase's slot on the clock: enter, hold, fade.
    var cycleDuration: Double { effectiveEntrance + effectiveHold }

    /// Where the rotation is at `time`.
    ///
    /// Pure and driven by wall-clock time rather than by accumulated state, for the same reason
    /// the presets are pure functions of progress: every instance on screen (the gallery button,
    /// the lab preview) reads the same clock and therefore agrees, and nothing needs resetting
    /// when a sheet opens or a view remounts.
    func phase(at time: TimeInterval) -> ButtonLabelPhase {
        let count = max(1, activePhrases.count)
        let entrance = effectiveEntrance
        let cycle = cycleDuration
        let total = cycle * Double(count)

        // Double remainder so a negative time (a clock before the reference date) still lands in
        // 0..<total instead of mirroring the rotation.
        let wrapped = (time.truncatingRemainder(dividingBy: total) + total)
            .truncatingRemainder(dividingBy: total)
        let index = min(count - 1, Int(wrapped / cycle))
        let elapsed = wrapped - Double(index) * cycle

        // The preset's entrance completes at `entranceWindow` of its progress, so scaling elapsed
        // time onto that point is what makes ENTRANCE mean seconds rather than "seconds × 0.7".
        // Clamped at 1, where every preset holds its settled state.
        let progress = CGFloat(min(1, TextAnimationType.entranceWindow * elapsed / entrance))

        // The whole layer fades over the last beat of the hold, because the presets are
        // entrance-only — they have no exit, and without one the swap to the next phrase is a
        // single-frame cut. Capped against the hold so a short hold still gets a settled moment.
        let fade = min(0.35, effectiveHold * 0.4)
        let remaining = cycle - elapsed
        let alpha = CGFloat(min(1, max(0, remaining / fade)))

        return ButtonLabelPhase(phraseIndex: index, progress: progress, alpha: alpha)
    }

    // MARK: - Export

    /// A paste-ready Swift block, the lab's whole point: settle on a look, copy this, make it the
    /// button's constants, delete the scaffolding.
    var swiftSnippet: String {
        let phraseList = phrases
            .map { "\"\($0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"" }
            .joined(separator: ", ")
        return """
        // Copied from BUTTON TEXT LAB.
        static let tuned = ButtonLabelTuning(
            phrases: [\(phraseList)],
            animation: .\(animation.rawValue.lowercased()),
            parameter: \(Self.number(parameter)),
            slideDirection: .\(slideDirection.rawValue.lowercased()),
            gridOrigin: .\(gridOrigin.rawValue.lowercased()),
            entranceDuration: \(Self.number(entranceDuration)),
            holdDuration: \(Self.number(holdDuration))
        )
        """
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

/// One instant of the rotation, as the renderer consumes it.
struct ButtonLabelPhase: Equatable {
    /// Index into `activePhrases`.
    var phraseIndex: Int
    /// The preset's progress, `0…1` — the same clock `TextAnimationType.tileStates` reads.
    var progress: CGFloat
    /// Whole-layer opacity, `0…1`. 1 through the entrance and hold, ramping to 0 at the swap.
    var alpha: CGFloat
}

// MARK: - Tolerant decoding

/// Fills in whatever a stored blob is missing, for the reason every lab tuning does: the lab
/// exists to grow fields, and synthesised `Codable` would revert an evening's work to stock the
/// first time it does. In an extension so the memberwise initialiser survives — `.default` and the
/// snippet's output are both built with it.
extension ButtonLabelTuning {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ButtonLabelTuning.default

        func number(_ key: CodingKeys, _ or: Double) -> Double {
            ((try? container.decodeIfPresent(Double.self, forKey: key)) ?? nil) ?? or
        }

        self.init(
            phrases: ((try? container.decodeIfPresent([String].self, forKey: .phrases)) ?? nil)
                ?? fallback.phrases,
            animation: ((try? container.decodeIfPresent(TextAnimationType.self, forKey: .animation)) ?? nil)
                ?? fallback.animation,
            parameter: number(.parameter, fallback.parameter),
            slideDirection: ((try? container.decodeIfPresent(TextSlideDirection.self, forKey: .slideDirection)) ?? nil)
                ?? fallback.slideDirection,
            gridOrigin: ((try? container.decodeIfPresent(TextGridOrigin.self, forKey: .gridOrigin)) ?? nil)
                ?? fallback.gridOrigin,
            entranceDuration: number(.entranceDuration, fallback.entranceDuration),
            holdDuration: number(.holdDuration, fallback.holdDuration)
        )
    }
}
