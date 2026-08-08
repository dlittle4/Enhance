import SwiftUI

/// A square effect card for the browse gallery: the user's photo with the effect
/// applied, its name over the bottom-left, mint stroke when selected.
///
/// Replaces the 60pt text chips. The thumbnail was already there at chip size, but at
/// 110pt it becomes the point of the card rather than incidental texture — you can see
/// what an effect does before selecting it.
struct EffectCardView: View {
    let title: String
    let thumbnail: UIImage?
    let isActive: Bool

    /// Face filters that need a face, or exactly one face, when the photo does not
    /// oblige. Carried on the card so the gallery stays a plain `ForEach`.
    var isBlocked: Bool = false

    /// Supplied by the caller from measured space rather than fixed, so cards scale
    /// with the device — see `AppConstants.Layout.effectCardSize(forControlsHeight:)`.
    let size: CGFloat

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
                background

                Text(title)
                    .font(.silkscreenControl)
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

    @ViewBuilder
    private var background: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipped()
                // Scrim so the title stays readable over an arbitrary photo. Lighter
                // when active, since the selected card should read brightest.
                .overlay(Color.black.opacity(isActive ? 0.25 : 0.45))
        } else {
            // Face cards have no thumbnail path yet, and on a photo with no faces one
            // would be meaningless anyway.
            Rectangle()
                .fill(isActive ? Color(hex: 0x323232) : Color.white.opacity(0.04))
        }
    }
}
