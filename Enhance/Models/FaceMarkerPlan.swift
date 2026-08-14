import CoreGraphics
import Foundation

/// Which face-marker experiments are on.
///
/// A value rather than three reads of `UserDefaults`, so the rendering path takes its policy as an
/// argument and a test can state a combination without touching global state — the same reason
/// `EditorViewModel` takes `allowsGenerationWithoutZoom` injected rather than sampling the flag
/// inline.
struct FaceMarkerOptions: Equatable {
    var calm: Bool = false
    var reticle: Bool = false
    var spotlight: Bool = false

    /// The app as it has always drawn face boxes. Named rather than written as `.init()` at call
    /// sites so the intent — "this is the unchanged overlay" — survives.
    static let legacy = FaceMarkerOptions()

    /// The live flags. Non-view readers use this; views should prefer `@AppStorage` bound to the
    /// same keys so a toggle repaints immediately.
    static var current: FaceMarkerOptions {
        FaceMarkerOptions(
            calm: FeatureFlags.faceMarkersCalm,
            reticle: FeatureFlags.faceMarkersReticle,
            spotlight: FeatureFlags.faceMarkersSpotlight
        )
    }

    /// **The combination policy, stated once.**
    ///
    /// All three compose, and that is a decision rather than an accident: CALM governs *when* a
    /// marker is on screen and how it animates, RETICLE governs *how it draws*, SPOTLIGHT dims the
    /// photo around the chosen face. No pair of those contradicts the other, so there is no
    /// precedence to arbitrate and every one of the eight combinations is a look someone might
    /// prefer.
    ///
    /// The one interaction worth naming: CALM can decide to draw *nothing* (a single face, or a
    /// marker that has timed out), and when it does, RETICLE has nothing to style. That is
    /// intentional — "quiet" beating "decorated" is the whole point of the calm variant — and it is
    /// why `markers(for:selectedIndex:options:)` applies the calm rules before the renderer ever
    /// sees the list.
    var isLegacy: Bool { self == .legacy }
}

/// One face's marker, as the canvas should draw it.
///
/// `isTarget` and `isSoloed` are deliberately separate, because today's overlay conflates them and
/// that conflation is most of what reads as clunky: with nothing selected, every face is a target,
/// and the old tuple's single `isSelected` then rendered all of them in the *selected* style —
/// blinking included.
struct FaceMarker: Equatable, Identifiable {
    let id: UUID
    let index: Int

    /// Normalized, bottom-left origin — `DetectedFace.normalizedBoundingBox` unchanged, so the
    /// canvas' existing Y-flip still applies.
    let rect: CGRect

    /// The effect will run on this face.
    let isTarget: Bool

    /// This specific face is the explicit choice. False for every marker when nothing is selected,
    /// even though all of them are targets.
    let isSoloed: Bool

    /// What the legacy renderer called `isSelected`. Kept as a derived property rather than stored,
    /// so the old look cannot drift from the new model.
    var legacyIsSelected: Bool { isTarget }
}

/// Turns detected faces plus a selection into the markers to draw.
///
/// Pure and free of UIKit so the rules can be tested without a canvas — the interesting behaviour
/// here is *whether a marker exists at all*, which is exactly the kind of thing that is invisible
/// in a screenshot test and obvious in a unit test.
enum FaceMarkerPlan {

    /// - Parameters:
    ///   - faces: identity and normalized bounding box per detected face, in detection order.
    ///   - selectedIndex: the soloed face, or nil for "all faces".
    ///   - options: which experiments are on.
    static func markers(
        for faces: [(id: UUID, rect: CGRect)],
        selectedIndex: Int?,
        options: FaceMarkerOptions
    ) -> [FaceMarker] {
        // A single face is not a choice, so CALM draws nothing over it. The effect still runs —
        // `activeFaces` already returns the one face whether or not it is explicitly selected — so
        // this removes chrome without removing capability.
        if options.calm && faces.count <= 1 { return [] }

        return faces.enumerated().map { index, face in
            FaceMarker(
                id: face.id,
                index: index,
                rect: face.rect,
                isTarget: selectedIndex == nil || selectedIndex == index,
                isSoloed: selectedIndex == index
            )
        }
    }

    /// Convenience over `DetectedFace`, which carries a good deal more than this needs.
    static func markers(
        for faces: [DetectedFace],
        selectedIndex: Int?,
        options: FaceMarkerOptions
    ) -> [FaceMarker] {
        markers(
            for: faces.map { (id: $0.id, rect: $0.normalizedBoundingBox) },
            selectedIndex: selectedIndex,
            options: options
        )
    }

    /// The face the spotlight should cut around, or nil when it should not draw.
    ///
    /// Nil unless the experiment is on *and* exactly one face is soloed. Dimming "everything except
    /// all of them" is not a meaningful image, and dimming around a lone face that was never chosen
    /// would spotlight a decision the user did not make.
    static func spotlightRect(in markers: [FaceMarker], options: FaceMarkerOptions) -> CGRect? {
        guard options.spotlight else { return nil }
        return markers.first(where: \.isSoloed)?.rect
    }
}
