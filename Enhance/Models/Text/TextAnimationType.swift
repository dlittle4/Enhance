import CoreGraphics

/// How finely the master raster is cut for a given entrance.
///
/// Chosen by the preset at prepare time, because it decides how many tiles the rasterizer
/// produces and therefore how many states the evaluator must return.
enum TextTileGranularity: Sendable {
    /// One tile: the whole block moves as a unit.
    case whole
    /// One tile per shaping-safe reveal unit — TYPEWRITER.
    case unit
    /// One tile per linguistic word token — SLIDE.
    case word
}

/// Which edge SLIDE enters from.
///
/// The one axis that distinguished the old RISE and WORD DROP presets: both travel vertically and
/// settle, differing only in whether the text comes up from below or falls in from above. Folding
/// them into one preset with a direction leaves the carousel shorter and the choice clearer.
enum TextSlideDirection: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case up   = "UP"
    case down = "DOWN"

    var id: String { rawValue }

    /// Sign of the *starting* offset in output space, where positive y is down. Entering from
    /// below means starting at +y and travelling up to zero.
    var startSign: CGFloat { self == .up ? 1 : -1 }
}

/// What one tile is doing at one instant.
///
/// Two spatial spaces are mixed here on purpose, and the split is the contract:
/// `scaleDelta` and `rotationDelta` are **local**, applied about the tile's own centre, while
/// `translationDelta` is in **output space**, applied last. That is why a 90°-rotated title
/// still slides up the screen but scales about itself — gravity is a screen metaphor, scale is
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
enum TextAnimationType: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case pop        = "POP"
    case slide      = "SLIDE"
    case typewriter = "TYPEWRITER"
    case spin       = "SPIN"
    case flicker    = "FLICKER"

    var id: String { rawValue }

    /// Every entrance is complete by 70% of the moving frames, leaving the last 30% and all of
    /// the pause showing settled text.
    static let entranceWindow: CGFloat = 0.70

    var granularity: TextTileGranularity {
        switch self {
        case .pop, .spin, .flicker: return .whole
        case .typewriter:           return .unit
        case .slide:                return .word
        }
    }

    /// The greatest scale this preset ever reaches.
    ///
    /// The rasterizer draws the master this much larger than its resting size so the sharpest
    /// frame is 1:1 rather than an upscale, and the resting transform divides it back out. It is
    /// declared here rather than hardcoded in the rasterizer so a preset that overshoots further
    /// widens the raster automatically — which POP's spring relies on.
    var peakScale: CGFloat {
        switch self {
        case .pop: return 1.45
        default:   return 1.0
        }
    }

    /// Only TYPEWRITER draws a cursor, and it is the one synthetic tile in the system.
    var hasCursor: Bool { self == .typewriter }

    /// The label of this preset's single tunable control, shown in the settings panel.
    var parameterLabel: String {
        switch self {
        case .pop:        return "BOUNCE"
        case .slide:      return "DISTANCE"
        case .typewriter: return "SPEED"
        case .spin:       return "SPINS"
        case .flicker:    return "INTENSITY"
        }
    }

    /// Whether this preset exposes the UP/DOWN direction control.
    var usesDirection: Bool { self == .slide }

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

    /// Total entries `tileStates` returns: one per slot, plus the cursor for TYPEWRITER.
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
    ///     can call the shorter form, the same way `VisualEffect` defaults its later overloads
    ///     rather than forcing every call site to thread a value it does not have.
    ///   - direction: SLIDE's entry edge; ignored by every other preset.
    func tileStates(at progress: CGFloat,
                    layout: PreparedTextLayout,
                    tuning: CGFloat = 0.5,
                    direction: TextSlideDirection = .up) -> [TextTileState] {
        let p = min(1, max(0, progress))
        let q = min(1, p / Self.entranceWindow)
        let t = min(1, max(0, tuning))
        let slots = slotCount(in: layout)

        var states: [TextTileState]
        switch self {
        case .pop:        states = popStates(q: q, slots: slots, tuning: t)
        case .slide:      states = slideStates(q: q, slots: slots, tuning: t, direction: direction)
        case .typewriter: states = typewriterStates(q: q, slots: slots, tuning: t)
        case .spin:       states = spinStates(q: q, slots: slots, tuning: t)
        case .flicker:    states = flickerStates(q: q, slots: slots, tuning: t, seed: layout.seed)
        }

        if hasCursor {
            states.append(cursorState(q: q))
        }
        return states
    }

    // MARK: - Presets

    /// A spring that overshoots and rings down, rather than the single soft overshoot this had
    /// before — which read as a gentle swell instead of a bounce.
    ///
    /// BOUNCE scales the amplitude of the ringing, so the control changes how springy it feels
    /// rather than merely how big the one overshoot is. The decay is exponential and the sine is
    /// phased to start at −1, so the text begins small, punches past full size, and settles.
    private func popStates(q: CGFloat, slots: Int, tuning: CGFloat) -> [TextTileState] {
        guard q < 1 else { return Array(repeating: .resting, count: slots) }

        let amplitude = 0.4 + 0.8 * tuning          // 0.4…1.2
        let ring = pow(2, -10 * q) * sin((q * 10 - 0.75) * (2 * CGFloat.pi / 3))
        // Bounded by peakScale so the raster is never upscaled at the overshoot frame.
        let scale = min(peakScale, max(0.05, 1 + ring * amplitude))

        let state = TextTileState(alpha: textEaseOut(min(1, q / 0.35)), scaleDelta: scale,
                                  rotationDelta: 0, translationDelta: .zero)
        return Array(repeating: state, count: slots)
    }

    /// Word tokens travelling in from one edge and settling, staggered so the line cascades.
    ///
    /// This is the old RISE and WORD DROP folded together: they only ever differed by which edge
    /// the text came from, which is now `direction`.
    private func slideStates(q: CGFloat, slots: Int, tuning: CGFloat,
                             direction: TextSlideDirection) -> [TextTileState] {
        guard slots > 0 else { return [] }
        // Normalized to the output side: 0.12 is a little over a tenth of the frame.
        let distance = (0.04 + 0.08 * tuning) * direction.startSign
        let spread: CGFloat = 0.35
        let window = max(0.0001, 1 - spread)

        return (0..<slots).map { index in
            guard q < 1 else { return .resting }
            let offset = slots > 1 ? spread * CGFloat(index) / CGFloat(slots - 1) : 0
            let local = min(1, max(0, (q - offset) / window))
            let eased = textEaseOut(local)
            return TextTileState(alpha: eased, scaleDelta: 1, rotationDelta: 0,
                                 translationDelta: CGPoint(x: 0, y: distance * (1 - eased)))
        }
    }

    /// A stepped reveal, unit by unit, with a blinking block cursor.
    ///
    /// SPEED reads the way a speed control should: **higher is faster**. It sets how much of the
    /// entrance window the reveal consumes, so turning it up finishes the typing sooner and leaves
    /// the finished message on screen for longer. It used to be inverted.
    private func typewriterStates(q: CGFloat, slots: Int, tuning: CGFloat) -> [TextTileState] {
        let completion = 1.0 - 0.35 * tuning        // 1.0 (slowest) … 0.65 (fastest)
        let advance = min(1, q / completion)
        let revealed = Int((advance * CGFloat(slots)).rounded(.down))

        return (0..<slots).map { index in
            // Discrete 0/1 alpha: typing is stepped, and an exact alpha is what lets the
            // partition test compare the composite byte for byte.
            index < revealed || q >= 1 ? .resting : .hidden
        }
    }

    /// Spins into place: the block turns through whole revolutions while growing to full size.
    ///
    /// The rotation is a *local* delta, so it pivots on the text's own centre rather than swinging
    /// the block around the frame. SPINS chooses how many turns, and the easing is a plain
    /// ease-out so the last part of the turn slows into the resting orientation.
    private func spinStates(q: CGFloat, slots: Int, tuning: CGFloat) -> [TextTileState] {
        guard q < 1 else { return Array(repeating: .resting, count: slots) }

        let turns = 1 + (2 * tuning).rounded()      // 1, 2 or 3 full revolutions
        let eased = textEaseOut(q)
        let remaining = 1 - eased
        let state = TextTileState(
            alpha: textEaseOut(min(1, q / 0.3)),
            scaleDelta: max(0.05, 0.2 + 0.8 * eased),
            // Unwinds to exactly zero, so the text lands upright at its resting angle.
            rotationDelta: turns * 2 * CGFloat.pi * remaining,
            translationDelta: .zero
        )
        return Array(repeating: state, count: slots)
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

    /// The TYPEWRITER cursor: a deterministic blink that is gone by the time the text settles.
    ///
    /// It must reach zero at `q == 1`. The pause is a single render replicated, so a cursor still
    /// visible at the end would sit frozen over the finished message for the whole hold.
    private func cursorState(q: CGFloat) -> TextTileState {
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
