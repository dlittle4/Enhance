import Testing
import Foundation
import CoreGraphics
@testable import Enhance

struct ZoomCardFramingTests {

    private let card: CGFloat = 160
    private let landscape = CGSize(width: 640, height: 480)
    private let portrait = CGSize(width: 480, height: 640)

    // MARK: - Which framing each type gets

    /// The property the cards rest on. These are stills, so if any two types resolved to
    /// the same fraction their cards would be pixel-identical and the gallery would be
    /// telling the user nothing.
    @Test func fraction_isDistinctForEveryType() {
        let fractions = AnimatorType.allCases.map { ZoomCardFraming.fraction(for: $0) }
        #expect(Set(fractions).count == AnimatorType.allCases.count, "got \(fractions)")
    }

    @Test func fraction_zoomInIsTightAndZoomOutIsWide() {
        #expect(ZoomCardFraming.fraction(for: .zoomIn) == 1)
        #expect(ZoomCardFraming.fraction(for: .zoomOut) == 0)
    }

    /// PULSE genuinely ends wide — `sin(π)` returns it to its start — so its card shows a
    /// midpoint instead. Pinned because "show the last frame" is the rule everywhere else
    /// and a future reader would otherwise be right to "fix" this to 0.
    @Test func fraction_pulseSitsStrictlyBetweenTheOthers() {
        let pulse = ZoomCardFraming.fraction(for: .pulse)
        #expect(pulse > ZoomCardFraming.fraction(for: .zoomOut))
        #expect(pulse < ZoomCardFraming.fraction(for: .zoomIn))
    }

    @Test func fraction_staysInUnitRange() {
        for type in AnimatorType.allCases {
            let f = ZoomCardFraming.fraction(for: type)
            #expect(f >= 0 && f <= 1, "\(type) produced \(f)")
        }
    }

    // MARK: - The transform

    /// ZOOM OUT's card must show the photo exactly as a plain thumbnail would: unscaled
    /// and unshifted.
    @Test func transform_atZeroFraction_isIdentity() {
        for size in [landscape, portrait] {
            let t = ZoomCardFraming.transform(
                fraction: 0, zoomScale: 3, zoomCenter: CGPoint(x: 0.2, y: 0.8),
                imageSize: size, cardSize: card
            )
            #expect(t.scale == 1)
            #expect(abs(t.offset.width) < 1e-9)
            #expect(abs(t.offset.height) < 1e-9)
        }
    }

    /// A centred zoom needs no pan, whatever the scale or the image aspect. This is the
    /// case that would expose a sign error or a bad aspect-fill correction.
    @Test func transform_withCentredZoom_neverOffsets() {
        for size in [landscape, portrait] {
            for f in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let t = ZoomCardFraming.transform(
                    fraction: f, zoomScale: 4, zoomCenter: CGPoint(x: 0.5, y: 0.5),
                    imageSize: size, cardSize: card
                )
                #expect(abs(t.offset.width) < 1e-9, "aspect \(size) at \(f)")
                #expect(abs(t.offset.height) < 1e-9, "aspect \(size) at \(f)")
            }
        }
    }

    /// Log interpolation, matching `interpolate` in Animator.swift: halfway along is the
    /// geometric mean, not the arithmetic one. At 4x that is 2x, not 2.5x — which is
    /// exactly what PULSE's card renders at.
    @Test func transform_scaleInterpolatesLogarithmically() {
        let half = ZoomCardFraming.transform(
            fraction: 0.5, zoomScale: 4, zoomCenter: CGPoint(x: 0.5, y: 0.5),
            imageSize: landscape, cardSize: card
        )
        #expect(abs(half.scale - 2) < 1e-9)

        let full = ZoomCardFraming.transform(
            fraction: 1, zoomScale: 4, zoomCenter: CGPoint(x: 0.5, y: 0.5),
            imageSize: landscape, cardSize: card
        )
        #expect(abs(full.scale - 4) < 1e-9)
    }

    /// A zoom target left of centre must pull the content *right* to bring it into view.
    /// Pinning the sign stops a plausible-looking refactor from inverting the pan.
    @Test func transform_pansTowardTheZoomTarget() {
        let left = ZoomCardFraming.transform(
            fraction: 1, zoomScale: 3, zoomCenter: CGPoint(x: 0.2, y: 0.5),
            imageSize: landscape, cardSize: card
        )
        #expect(left.offset.width > 0, "a target left of centre moves content right")

        let up = ZoomCardFraming.transform(
            fraction: 1, zoomScale: 3, zoomCenter: CGPoint(x: 0.5, y: 0.2),
            imageSize: portrait, cardSize: card
        )
        #expect(up.offset.height > 0, "a target above centre moves content down")
    }

    /// The card is square and the photo is aspect-filled, so the overflowing axis carries
    /// more content per unit of normalised coordinate. An offset computed against the
    /// card instead of the filled rect would miss this.
    @Test func transform_accountsForTheAspectFilledOverflow() {
        let wide = ZoomCardFraming.transform(
            fraction: 1, zoomScale: 2, zoomCenter: CGPoint(x: 0.2, y: 0.5),
            imageSize: landscape, cardSize: card
        )
        let square = ZoomCardFraming.transform(
            fraction: 1, zoomScale: 2, zoomCenter: CGPoint(x: 0.2, y: 0.5),
            imageSize: CGSize(width: 500, height: 500), cardSize: card
        )
        #expect(wide.offset.width > square.offset.width,
                "a landscape photo overflows horizontally, so the same normalised target is further out")
    }

    /// `zoomScale` below 1 would shrink the image inside the card and expose the
    /// background behind it.
    @Test func transform_neverScalesBelowOne() {
        for scale in [CGFloat(0), 0.5, 1] {
            let t = ZoomCardFraming.transform(
                fraction: 1, zoomScale: scale, zoomCenter: CGPoint(x: 0.5, y: 0.5),
                imageSize: landscape, cardSize: card
            )
            #expect(t.scale == 1)
        }
    }

    @Test func transform_withDegenerateInput_isIdentity() {
        let noImage = ZoomCardFraming.transform(
            fraction: 1, zoomScale: 3, zoomCenter: CGPoint(x: 0.5, y: 0.5),
            imageSize: .zero, cardSize: card
        )
        #expect(noImage.scale == 1)
        #expect(noImage.offset == .zero)

        let noCard = ZoomCardFraming.transform(
            fraction: 1, zoomScale: 3, zoomCenter: CGPoint(x: 0.5, y: 0.5),
            imageSize: landscape, cardSize: 0
        )
        #expect(noCard.scale == 1)
        #expect(noCard.offset == .zero)
    }

    /// End to end: the three cards must actually differ in what they render, not just in
    /// their fraction. With a real zoom set, every scale should be distinct.
    @Test func transform_producesADistinctScalePerType() {
        let scales = AnimatorType.allCases.map { type in
            ZoomCardFraming.transform(
                fraction: ZoomCardFraming.fraction(for: type),
                zoomScale: 2.5, zoomCenter: CGPoint(x: 0.5, y: 0.5),
                imageSize: landscape, cardSize: card
            ).scale
        }
        #expect(Set(scales).count == AnimatorType.allCases.count, "got \(scales)")
    }

    /// `rect` is how a framing reaches the generator, which reads only its **centre** and takes
    /// the magnification from the scale alongside it. The size still has to describe the region
    /// the framing names, or the value lies to any later reader.
    @Test func rect_isCentredOnTheFramingAndSizedByItsScale() {
        let framing = ZoomFraming(scale: 4, center: CGPoint(x: 0.25, y: 0.75))

        #expect(abs(framing.rect.midX - 0.25) < 1e-9)
        #expect(abs(framing.rect.midY - 0.75) < 1e-9)
        #expect(abs(framing.rect.width - 0.25) < 1e-9)
    }

    /// At or below 1× there is nothing cropped away, so the rect is the whole frame rather than
    /// something inverted by a scale under one.
    @Test func rect_atNoZoom_isTheWholeFrame() {
        #expect(ZoomFraming(scale: 1, center: CGPoint(x: 0.5, y: 0.5)).rect
            == CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(ZoomFraming(scale: 0.5, center: CGPoint(x: 0.5, y: 0.5)).rect.width == 1)
    }
}
