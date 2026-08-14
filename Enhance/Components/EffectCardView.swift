import SwiftUI

/// Press feedback for an effect card: shrink and dim while held, spring back on release.
///
/// A sibling of `GifGridItemButtonStyle`, which does the same job for gallery thumbnails and is
/// the reason this shape is already proven. The difference is deliberate rather than accidental —
/// an effect card is meant to read **bouncier**, which means a lower damping fraction and a
/// visible ring on release.
///
/// A plain value type on purpose: it observes nothing. `ButtonStyle` is an awkward place for
/// dynamic properties, so the values arrive already resolved from `EffectCardView`, which is an
/// ordinary view and can observe whatever it likes.
struct EffectCardButtonStyle: ButtonStyle {

    /// What the press needs to know. `nil` anywhere upstream means "no press feedback", which is
    /// the app's shipped behaviour.
    struct PressMotion: Equatable {
        var scale: Double
        var brightness: Double
        var curve: MotionCurve
    }

    /// `nil` renders exactly as `.buttonStyle(.plain)` did — a custom style already suppresses the
    /// system's default press treatment, so the inert case needs no separate branch at the call
    /// site and the app's shipped look is preserved by the values, not by a conditional.
    let motion: PressMotion?

    func makeBody(configuration: Configuration) -> some View {
        // An inner View rather than modifiers directly on the label: the pulse needs @State,
        // and a ButtonStyle is not a View — state declared on the style itself is not
        // reliably retained.
        PressBody(configuration: configuration, motion: motion)
    }

    private struct PressBody: View {
        let configuration: Configuration
        let motion: PressMotion?

        /// Held at full press depth from the moment the finger lifts until the release spring
        /// has somewhere to spring back from. This is what makes a quick *tap* visible: a 50ms
        /// press barely starts the press-down animation, so animating back from wherever it got
        /// to reads as nothing. On release the card snaps (unanimated) to full depth and springs
        /// back from there — a long hold passes through the same path and looks identical,
        /// since it was already at depth.
        @State private var releasePulse = false

        var body: some View {
            let down = configuration.isPressed || releasePulse
            configuration.label
                .scaleEffect(down ? (motion?.scale ?? 1) : 1)
                .brightness(down ? (motion?.brightness ?? 0) : 0)
                .animation(motion?.curve.animation, value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { _, pressed in
                    guard motion != nil, !pressed else { return }
                    var snap = Transaction()
                    snap.disablesAnimations = true
                    withTransaction(snap) { releasePulse = true }
                    DispatchQueue.main.async {
                        withAnimation(motion?.curve.animation) { releasePulse = false }
                    }
                }
        }
    }
}

private struct EffectCardPressMotionKey: EnvironmentKey {
    static let defaultValue: EffectCardButtonStyle.PressMotion? = nil
}

extension EnvironmentValues {
    /// Press feedback for every `EffectCardView` below this point, or `nil` for none.
    ///
    /// Injected through the environment rather than passed as a parameter because the cards are
    /// built at four separate call sites in `EditorView` (zoom, face, image, text) and threading
    /// the same value through all of them would put a tuning concern in four signatures. It also
    /// lets MOTION LAB force the press on for its preview while the app leaves it off.
    var effectCardPressMotion: EffectCardButtonStyle.PressMotion? {
        get { self[EffectCardPressMotionKey.self] }
        set { self[EffectCardPressMotionKey.self] = newValue }
    }
}

/// A square effect card for the browse gallery: the user's photo with the effect
/// applied, its name over the bottom-left, mint stroke when selected.
///
/// Replaces the 60pt text chips. The thumbnail was already there at chip size, but at
/// 110pt it becomes the point of the card rather than incidental texture — you can see
/// what an effect does before selecting it.
struct EffectCardView<Background: View>: View {
    let title: String
    let isActive: Bool

    /// Face filters that need a face, or exactly one face, when the photo does not
    /// oblige. Carried on the card so the gallery stays a plain `ForEach`.
    var isBlocked: Bool = false

    /// Supplied by the caller from measured space rather than fixed, so cards scale
    /// with the device — see `AppConstants.Layout.effectCardSize(forControlsHeight:)`.
    let size: CGFloat

    /// The card's backdrop. Generic so the ZOOM cards can supply an animated preview —
    /// see `EffectCardView.init(title:thumbnail:…)` for the ordinary still case, which
    /// is what IMAGE and FACE use.
    @ViewBuilder var background: () -> Background

    var action: () -> Void

    @Environment(\.effectCardPressMotion) private var pressMotion

    /// A press is functional feedback rather than decoration, so under reduce motion it damps to
    /// a clean settle instead of disappearing — unlike the purely decorative motion elsewhere,
    /// which is skipped outright. The card still acknowledges the touch; it just stops ringing.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var resolvedPressMotion: EffectCardButtonStyle.PressMotion? {
        guard var motion = pressMotion else { return nil }
        if reduceMotion {
            motion.curve.dampingFraction = max(motion.curve.dampingFraction, 1)
        }
        return motion
    }

    /// Proportional to the card, capped at the panel radius so a full-size card matches
    /// the detail panel's corner rather than out-rounding it.
    private var radius: CGFloat {
        min(AppConstants.Layout.panelCornerRadius, size * 0.18)
    }

    /// Grows with the card so the title never crowds the corner at 160pt nor wastes a
    /// third of a 64pt card on padding.
    private var titlePadding: CGFloat {
        max(7, size * 0.09)
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                background()

                Text(title)
                    .font(.silkscreenBody)
                    // SwiftUI prefers wrapping over scaling, so the floor has to be low
                    // enough that a long single word ("HALFTONE") still fits on one line
                    // at a small card size — otherwise it breaks mid-word as "HALFTON/E".
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
                    .foregroundColor(isActive ? .enhanceMint : .white)
                    // Two lines so two-word names ("CHROMA SHIFT", "VINTAGE GRAIN") wrap
                    // rather than truncate — they do not fit on one even at 110pt.
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(titlePadding)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(isActive ? Color.enhanceMint : .clear, lineWidth: 2)
            )
            // A card must never claim more touch area than the square you can see.
            //
            // `clipShape` bounds the *drawing* and not the touch region, and the ZOOM cards put a
            // `scaleEffect` of up to 2.5× inside the frame (`ZoomCardThumbnail`) — so their button
            // was interactive across a region far wider than the card, silently swallowing taps
            // aimed at whatever sat beside it. It went unnoticed while ZOOM IN was leftmost and
            // its overspill fell off-screen; adding ORIGINAL in front of it put a real card under
            // that overspill, and roughly two thirds of ORIGINAL selected ZOOM IN instead.
            //
            // Fixed here rather than in `ZoomCardThumbnail` because the rule belongs to the card:
            // any backdrop is free to transform its content, and none of them should be able to
            // reach outside the frame to do it.
            .contentShape(Rectangle())
        }
        .buttonStyle(EffectCardButtonStyle(motion: resolvedPressMotion))
        .disabled(isBlocked)
        .opacity(isBlocked ? 0.35 : 1.0)
    }

}

/// The ordinary still backdrop: the effect applied to the user's photo, or a flat fill
/// when there is no thumbnail to show.
struct EffectCardThumbnail: View {
    let image: UIImage?
    let isActive: Bool
    let size: CGFloat

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipped()
                .effectCardScrim(isActive: isActive)
        } else {
            // A photo with no faces, where a face-effect thumbnail would be meaningless.
            Rectangle()
                .fill(isActive ? Color.surfaceControl : Color.divider)
        }
    }
}

extension View {
    /// Keeps a card title readable over an arbitrary photo. Lighter when active, since
    /// the selected card should read brightest.
    ///
    /// Applied by each backdrop rather than by the card, so the flat fill — which is
    /// already near-black — is not darkened a second time.
    func effectCardScrim(isActive: Bool) -> some View {
        overlay(Color.black.opacity(isActive ? 0.25 : 0.45))
    }
}

extension EffectCardView where Background == EffectCardThumbnail {
    /// Still-thumbnail card. Keeps the original call shape, so IMAGE and FACE are
    /// unchanged by the ZOOM cards needing something livelier.
    init(
        title: String,
        thumbnail: UIImage?,
        isActive: Bool,
        isBlocked: Bool = false,
        size: CGFloat,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            isActive: isActive,
            isBlocked: isBlocked,
            size: size,
            background: { EffectCardThumbnail(image: thumbnail, isActive: isActive, size: size) },
            action: action
        )
    }
}
