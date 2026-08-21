import Combine
import Foundation

/// Every number that shapes BIG HEAD's mask, exposed so HEAD MASK LAB can tune them against
/// real photos instead of another round of edit → build → render → squint.
///
/// The mask is built in exactly one place — `BigHeadEffect.headMask(for:subject:extent:tuning:)`
/// — and both the effect and the lab call it, so what the lab shows is what the GIF gets.
/// `.default` reproduces the shipped baseline (exact `ea96ce3` geometry plus the chin cut);
/// a fresh install renders identically to before this file existed.
///
/// All lengths are in **face units** — multiples of `faceWidth`/`faceHeight` — so one setting
/// serves every photo scale. Offsets are y-up: positive moves up.
struct HeadMaskTuning: Codable, Equatable {

    // MARK: Ellipse

    /// Full width of the head ellipse, × faceWidth. The baseline's effective value is large —
    /// its arithmetic doubled what the code appears to say — and that inherited size is part of
    /// the approved look, so it is exposed rather than "fixed".
    var ellipseWidth: Double

    /// Full height of the head ellipse, × faceHeight.
    var ellipseHeight: Double

    /// Ellipse centre offset from the face centre, × faceHeight. Positive is up — toward the
    /// crown. 0 is the baseline: centred on the face.
    var centerYOffset: Double

    /// Edge softness handed to `FaceRegionMaskBuilder.ellipticalMask`, 0…1.
    var feather: Double

    // MARK: Chin cut

    /// Where the below-chin fade *ends* (fully opaque above), offset from the face centre in
    /// faceHeights. −0.5 is the face box's bottom edge — the baseline.
    var chinCutOffset: Double

    /// Length of the fade below the cut, × faceHeight. Smaller is a harder line.
    var chinFade: Double

    // MARK: Growth (previewed in the lab so the mask is judged on the result, not the overlay)

    /// Extra scale at full intensity: final = 1 + intensity² × growthMax.
    var growthMax: Double

    /// Where the scale pivots, as a fraction up the ellipse's bounds from its bottom.
    var pivotY: Double

    /// The shipped baseline. `ellipseWidth`/`Height` are written as the *effective* full-size
    /// multipliers the ea96ce3 arithmetic produced at size 0.5 (coverage 1.525, applied as a
    /// half-extent → 3.05× face width), not the misleading literals in the old init.
    static let `default` = HeadMaskTuning(
        ellipseWidth: 3.05,
        ellipseHeight: 3.05,
        centerYOffset: 0,
        feather: 0.35,
        chinCutOffset: -0.5,
        chinFade: 0.35,
        growthMax: 0.55,
        pivotY: 0.30
    )
}

/// The live, shared `HeadMaskTuning` — what HEAD MASK LAB writes and `BigHeadEffect` reads.
/// Same shape as `FaceMarkerTuningStore`, for the same reasons: `@Published` so a slider drag
/// redraws mid-gesture, one JSON blob under one key so graduation is a single `removeObject`.
final class HeadMaskTuningStore: ObservableObject {

    static let shared = HeadMaskTuningStore()

    static let storageKey = "headMaskTuning"

    @Published var tuning: HeadMaskTuning {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    /// Injectable so tests round-trip against a scratch suite rather than the app's own.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(HeadMaskTuning.self, from: data) {
            self.tuning = decoded
        } else {
            self.tuning = .default
        }
    }

    func reset() {
        tuning = .default
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tuning) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
