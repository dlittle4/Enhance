import SwiftUI

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
        }
        .buttonStyle(.plain)
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
                .fill(isActive ? Color.surfaceActive : Color.hairline)
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
