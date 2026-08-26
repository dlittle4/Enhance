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

    // MARK: Approach *(added 2026-08-20, user's call — the person-instance path, revived from
    // the parked work as lab-selectable settings rather than a rebuild)*

    /// Per-person instance masks (`VNGeneratePersonInstanceMaskRequest`) instead of the shared
    /// foreground union. Each face's head is cut from **that person's** silhouette, so a
    /// neighbour's pixels cannot ride along — the measured limit is Vision's cap of four
    /// instances, past which neighbours share a mask and degrade toward union behaviour.
    var usePersonMasks: Bool

    /// Bound the head region below by the **traced jaw** (Vision's `faceContour` landmarks,
    /// dropped slightly below the trace) instead of the ellipse + chin ramp. Falls back to the
    /// ellipse automatically for animals and estimated faces, whose contours are synthetic.
    var useJawRegion: Bool

    /// How far below the traced jaw the cut sits, × faceHeight. Vision traces the face oval —
    /// cheeks, not the anatomical jaw — so a cut on the trace clips ears and draws a seam along
    /// the face; dropping it hides the seam under the chin. 0 cuts on the trace itself.
    var jawDrop: Double

    /// Softness of the jaw seam, × faceWidth. Small is a knife line, large dissolves into the
    /// neck.
    var jawFeather: Double

    /// Half-width of the jaw region, × faceWidth — how much hair and hat it admits sideways.
    /// Scaled by REACH like the ellipse, so the slider means the same thing in both modes.
    var jawWidth: Double

    // MARK: Head pose *(2026-08-20, user's call)*

    /// Rotate the mask geometry with the head's roll, and shift it sideways with yaw, using the
    /// pose angles Vision reports on the same observation the landmarks come from. Ellipse and
    /// chin ramp only — the traced jaw already follows the head, because its points do.
    var followPose: Bool

    /// How far yaw pushes the ellipse toward the back of the head, × faceWidth at full profile.
    /// The skull extends behind the face; a symmetric ellipse cannot reach it on a turned head.
    var yawShift: Double

    /// Which request supplies the shared subject silhouette in the lab.
    /// `.foreground` is the shipped path (any subject, incl. animals); `.personAccurate` is
    /// `VNGeneratePersonSegmentationRequest` at `.accurate`, whose soft confidence matte has
    /// noticeably better hair edges but sees only people. Lab-only until graduated: the app's
    /// other subject effects (ECHO, BACKGROUND ONLY) stay on foreground regardless.
    var unionSource: UnionSource

    enum UnionSource: String, Codable, Equatable {
        case foreground
        case personAccurate
        /// The hair+skin mattes Portrait-mode photos embed in the file (iOS 13+,
        /// `AVSemanticSegmentationMatte`). The best head boundary available anywhere when
        /// present; absent from ordinary photos, so the lab falls back to foreground and says
        /// so. Lab-only, like `.personAccurate`.
        case portraitMatte
    }

    /// Intersect the region with the segmentation silhouette. **On is the shipped behaviour.**
    /// Off is the classic cheap big-head: the feathered region cut straight from the photo,
    /// background and all — it can never miss a hat, works on any subject, and carries a
    /// smeared disc of background that only shows on busy scenes. Exposed (user's call,
    /// 2026-08-20) so the eleven-photo walk can judge where the classic look holds up.
    var useSilhouette: Bool

    /// Composite all heads in one layered pass — each cut from the original frame, nearer
    /// (wider) faces occluding farther ones with hardened edges — instead of the sequential
    /// per-face loop whose overlapping heads cross-fade into ghosts. The anti-blur switch for
    /// group photos; off is the sequential baseline.
    var stackedPass: Bool

    // MARK: Auto fit *(2026-08-20 — derive per-photo geometry instead of tuning it)*

    /// Derive the chin cut and ellipse height per face from the silhouette itself:
    /// neck = the narrowest mask row below the chin, crown = the highest row that still reads
    /// as head (`HeadGeometryScanner`). The sliders' job shifts from positions to fallbacks —
    /// they apply unchanged wherever the scan finds nothing. Ellipse mode only; the traced jaw
    /// already measures its own bottom.
    var autoFit: Bool

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
        usePersonMasks: false,
        useJawRegion: false,
        jawDrop: 0.12,
        jawFeather: 0.08,
        jawWidth: 2.2,
        followPose: false,
        yawShift: 0.35,
        unionSource: .foreground,
        useSilhouette: true,
        stackedPass: false,
        autoFit: false,
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
