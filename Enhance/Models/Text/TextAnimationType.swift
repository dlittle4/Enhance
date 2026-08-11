import CoreGraphics

/// How finely the master raster is cut for a given entrance.
///
/// Chosen by the preset at prepare time, because it decides how many tiles the rasterizer
/// produces and therefore how many states the evaluator must return.
enum TextTileGranularity: Sendable {
    /// One tile: the whole block moves as a unit.
    case whole
    /// One tile per shaping-safe reveal unit — TYPE.
    case unit
    /// One tile per linguistic word token — WORD DROP.
    case word
}

/// What one tile is doing at one instant.
///
/// Two spatial spaces are mixed here on purpose, and the split is the contract:
/// `scaleDelta` and `rotationDelta` are **local**, applied about the tile's own centre, while
/// `translationDelta` is in **output space**, applied last. That is why a 90°-rotated title
/// still RISEs up the screen but scales about itself — gravity is a screen metaphor, scale is
/// a typographic one. See FEATURE-TEXT-EFFECTS.md §7.6.
///
/// `translationDelta` is normalized to the output frame's side, not pixels, so this whole type
/// is resolution-independent and the preview and export evaluators can be the same code.
struct TextTileState: Equatable, Sendable {
    var alpha: CGFloat
    var scaleDelta: CGFloat
    var rotationDelta: CGFloat
    var translationDelta: CGPoint

    /// The settled state. Every preset must return exactly this for every cut tile at
    /// progress 1, which is what makes the pause frames byte-identical to the master.
    static let resting = TextTileState(alpha: 1, scaleDelta: 1, rotationDelta: 0,
                                       translationDelta: .zero)

    static let hidden = TextTileState(alpha: 0, scaleDelta: 1, rotationDelta: 0,
                                      translationDelta: .zero)
}

/// How a text overlay enters, synchronized to the zoom's moving frames.
///
/// Entrance only. A looping wiggle during the pause would make the message harder to read,
/// raise the GIF's inter-frame entropy and file size, and break the promise that the final
/// state is stable — the pause is one render replicated, so it cannot move even if we wanted it.
///
/// Every preset is a pure, deterministic function of `progress` and the layout's seed. Calling a
/// random API inside the frame loop would make preview and export disagree and two generations of
/// the same overlay differ, neither of which is recoverable after the fact.
enum TextAnimationType: String, CaseIterable, Identifiable, Hashable, Sendable {
    case pop      = "POP"
    case rise     = "RISE"
    case type     = "TYPE"
    case wordDrop = "WORD DROP"
    case flicker  = "FLICKER"

    var id: String { rawValue }

    /// Every entrance is complete by 70% of the moving frames, leaving the last 30% and all of
    /// the pause showing settled text.
    static let entranceWindow: CGFloat = 0.70

    var granularity: TextTileGranularity {
        switch self {
        case .pop, .rise, .flicker: return .whole
        case .type:                 return .unit
        case .wordDrop:             return .word
        }
    }

    /// The greatest scale this preset ever reaches.
    ///
    /// The rasterizer draws the master this much larger than its resting size so the sharpest
    /// frame is 1:1 rather than an upscale, and the resting transform divides it back out. It is
    /// declared here rather than hardcoded in the rasterizer so a future preset that overshoots
    /// further widens the raster automatically.
    ///
    /// Fixed, not derived from the tunable: POP's BOUNCE modulates the overshoot *within* this
    /// ceiling, so the raster never has to be re-sized when a slider moves.
    var peakScale: CGFloat {
        switch self {
        case .pop: return 1.08
        default:   return 1.0
        }
    }

    /// Only TYPE draws a cursor, and it is the one synthetic tile in the system.
    var hasCursor: Bool { self == .type }

    /// The label of this preset's single tunable control, shown in the settings panel's third row.
    var parameterLabel: String {
        switch self {
        case .pop:      return "BOUNCE"
        case .rise:     return "DISTANCE"
        case .type:     return "SPEED"
        case .wordDrop: return "STAGGER"
        case .flicker:  return "INTENSITY"
        }
    }

    /// Stable storage key component for the tunable. Must not change once shipped — values are
    /// keyed on it, and renaming one silently resets that control to its default.
    var parameterID: String { "textAnimation" }

    /// How many animated slots this preset needs for a given layout. Tiles carry a slot index
    /// into the array `tileStates` returns, so the two must agree.
    func slotCount(in layout: PreparedTextLayout) -> Int {
        switch granularity {
        case .whole: return 1
        case .unit:  return max(1, layout.units.count)
        case .word:  return max(1, layout.wordRanges.count)
        }
    }

    /// Total entries `tileStates` returns: one per slot, plus the cursor for TYPE.
    func stateCount(in layout: PreparedTextLayout) -> Int {
        slotCount(in: layout) + (hasCursor ? 1 : 0)
    }

    /// The index of the cursor's state, or `nil` when this preset has no cursor.
    func cursorStateIndex(in layout: PreparedTextLayout) -> Int? {
        hasCursor ? slotCount(in: layout) : nil
    }

    // MARK: - Evaluation

    /// Per-tile state at a normalized progress.
    ///
    /// - Parameters:
    ///   - progress: the generator's frame progress, `0…1`. Clamped here, so a caller passing a
    ///     value outside the range gets the endpoint rather than an extrapolated transform.
    ///   - layout: supplies the unit and word counts, and the overlay's seed.
    ///   - tuning: this preset's single control, `0…1`. Defaulted so the renderer and the tests
    ///     can call the two-argument form, the same way `VisualEffect` defaults its later
    ///     overloads rather than forcing every call site to thread a value it does not have.
    func tileStates(at progress: CGFloat,
                    layout: PreparedTextLayout,
                    tuning: CGFloat = 0.5) -> [TextTileState] {
        let p = min(1, max(0, progress))
        let q = min(1, p / Self.entranceWindow)
        let t = min(1, max(0, tuning))
        let slots = slotCount(in: layout)

        var states: [TextTileState]
        switch self {
        case .pop:      states = popStates(q: q, slots: slots, tuning: t)
        case .rise:     states = riseStates(q: q, slots: slots, tuning: t)
        case .type:     states = typeStates(q: q, slots: slots, tuning: t)
        case .wordDrop: states = wordDropStates(q: q, slots: slots, tuning: t)
        case .flicker:  states = flickerStates(q: q, slots: slots, tuning: t, seed: layout.seed)
        }

        if hasCursor {
            states.append(cursorState(q: q, slots: slots, tuning: t))
        }
        return states
    }

    // MARK: - Presets

    private func popStates(q: CGFloat, slots: Int, tuning: CGFloat) -> [TextTileState] {
        // BOUNCE modulates the overshoot within `peakScale`, so the raster size is unaffected.
        let peak = 1 + (peakScale - 1) * tuning * 2
        let clampedPeak = min(peakScale, max(1, peak))

        let scale: CGFloat
        if q <= 0.65 {
            scale = 0.55 + (clampedPeak - 0.55) * textEaseOut(q / 0.65)
        } else {
            // Settle exactly onto 1 at q == 1, so the resting invariant holds for every tuning.
            scale = clampedPeak + (1 - clampedPeak) * easeInOut((q - 0.65) / 0.35)
        }

        let alpha = textEaseOut(min(1, q / 0.45))
        let state = TextTileState(alpha: alpha, scaleDelta: scale,
                                  rotationDelta: 0, translationDelta: .zero)
        return Array(repeating: q >= 1 ? .resting : state, count: slots)
    }

    private func riseStates(q: CGFloat, slots: Int, tuning: CGFloat) -> [TextTileState] {
        // Normalized to the output side: 0.08 is the plan's ~48px of a 600px frame.
        let distance = 0.04 + 0.08 * tuning
        let remaining = 1 - textEaseOut(q)
        // Positive y is down, so the text starts *below* its resting place and travels up into it.
        let state = TextTileState(alpha: textEaseOut(min(1, q / 0.6)),
                                  scaleDelta: 1, rotationDelta: 0,
                                  translationDelta: CGPoint(x: 0, y: distance * remaining))
        return Array(repeating: q >= 1 ? .resting : state, count: slots)
    }

    private func typeStates(q: CGFloat, slots: Int, tuning: CGFloat) -> [TextTileState] {
        // SPEED finishes the reveal earlier, leaving the settled text on screen for longer.
        let completion = 0.75 + 0.25 * tuning
        let advance = min(1, q / completion)
        let revealed = Int((advance * CGFloat(slots)).rounded(.down))

        return (0..<slots).map { index in
            // A stepped reveal, not a per-unit fade: typing is discrete, and an exact 0/1 alpha
            // is what lets the partition test compare the composite byte-for-byte.
            index < revealed || q >= 1 ? .resting : .hidden
        }
    }

    private func wordDropStates(q: CGFloat, slots: Int, tuning: CGFloat) -> [TextTileState] {
        guard slots > 0 else { return [] }
        let spread = 0.15 + 0.45 * tuning
        let window = max(0.0001, 1 - spread)

        return (0..<slots).map { index in
            guard q < 1 else { return .resting }
            let offset = slots > 1 ? spread * CGFloat(index) / CGFloat(slots - 1) : 0
            let local = min(1, max(0, (q - offset) / window))
            let eased = textEaseOut(local)
            // Negative y is up: each word falls from above and settles.
            return TextTileState(alpha: eased, scaleDelta: 1, rotationDelta: 0,
                                 translationDelta: CGPoint(x: 0, y: -0.05 * (1 - eased)))
        }
    }

    private func flickerStates(q: CGFloat, slots: Int, tuning: CGFloat,
                               seed: UInt64) -> [TextTileState] {
        guard q < 1 else { return Array(repeating: .resting, count: slots) }

        // Three flashes whose timing is jittered from the overlay's stored seed, so two overlays
        // flicker differently but one overlay flickers identically on every regeneration.
        var rng = seed &+ 0x5DEECE66D
        let stable: CGFloat = 0.68

        // Drawn before the branch below, deliberately. Taking it afterwards would consume a
        // different number of values depending on which path ran, so the twitch would jump the
        // moment the flashes stopped — deterministic, but visibly discontinuous.
        let twitchPhase = unitRandom(&rng) * 2 - 1
        var alpha: CGFloat = 0

        if q >= stable {
            alpha = 1
        } else {
            let depth = 0.35 + 0.45 * tuning
            for index in 0..<3 {
                let slotStart = 0.06 + CGFloat(index) * 0.20
                let jitter = unitRandom(&rng) * 0.06
                let start = slotStart + jitter
                let width = 0.05 + unitRandom(&rng) * 0.05
                if q >= start && q < start + width {
                    // Each flash lands brighter than the last, so it reads as resolving.
                    alpha = depth + (1 - depth) * CGFloat(index) / 2
                }
            }
        }

        // A small twitch that decays to nothing, giving the flashes a physical edge without
        // needing a second field on the state type.
        let twitch = 0.02 * (1 - q) * twitchPhase
        let state = TextTileState(alpha: alpha, scaleDelta: 1 + twitch,
                                  rotationDelta: 0, translationDelta: .zero)
        return Array(repeating: state, count: slots)
    }

    /// The TYPE cursor: a deterministic blink that is gone by the time the text settles.
    ///
    /// It must reach zero at `q == 1`. The pause is a single render replicated, so a cursor still
    /// visible at the end would sit frozen over the finished message for the whole hold.
    private func cursorState(q: CGFloat, slots: Int, tuning: CGFloat) -> TextTileState {
        guard q < 1 else { return .hidden }
        let blinks: CGFloat = 6
        let on = sin(q * blinks * 2 * CGFloat.pi) > 0
        // Fade the blink out over the last quarter so it never pops off mid-stroke.
        let envelope = min(1, max(0, (1 - q) / 0.25))
        return TextTileState(alpha: on ? envelope : 0, scaleDelta: 1,
                             rotationDelta: 0, translationDelta: .zero)
    }
}

// MARK: - Deterministic helpers

/// Cubic ease-out. Peer to `easeInOut` in `Animator.swift`, kept file-private so the module's
/// global namespace does not gain a second very general name.
private func textEaseOut(_ t: CGFloat) -> CGFloat {
    let clamped = min(1, max(0, t))
    return 1 - pow(1 - clamped, 3)
}

/// SplitMix64. A value-in, value-out generator so a seed always produces the same sequence —
/// the frame loop must never touch `SystemRandomNumberGenerator`.
private func splitMix64(_ state: inout UInt64) -> UInt64 {
    state = state &+ 0x9E3779B97F4A7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    return z ^ (z >> 31)
}

private func unitRandom(_ state: inout UInt64) -> CGFloat {
    CGFloat(splitMix64(&state) >> 11) / CGFloat(UInt64(1) << 53)
}
