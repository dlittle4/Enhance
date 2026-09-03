import SwiftUI

/// A raised surface behind content — the app's pill and card treatment.
///
/// Replaces eight hand-rolled copies of the same three lines:
///
/// ```swift
/// .background(
///     RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous)
///         .fill(Color(hex: 0x202020).opacity(0.8))
/// )
/// ```
///
/// which becomes `.surface(.card, opacity: 0.8)`.
///
/// **Opacity is a parameter, not part of the style.** The eight call sites use three different
/// values — 0.8 in the editor, 0.95 and 1.0 in the gallery — and baking one in would have made
/// this primitive unusable for five of them. Same for the corner radius: it defaults to
/// `CornerRadius.card`, but one gallery pill is deliberately `.large` (12pt).
///
/// The `.continuous` corner style is not incidental. Every existing call site uses it, and
/// swapping to the default circular style is a visible change in the corner curve.
struct SurfaceModifier: ViewModifier {

    /// Which surface colour to use. Named after the exported design tokens.
    ///
    /// Collapsed from three cases to two on 2026-08-12: `.raised` and `.panel` had become the
    /// same colour once the panel adopted the card surface, and two names for one value is
    /// exactly the duplication this token layer exists to remove.
    enum Style {
        /// A card, pill, or the effect detail panel.
        case card
        /// The track behind a segmented control, or a selected cell.
        case control

        var color: Color {
            switch self {
            case .card:    return .surfaceCard
            case .control: return .surfaceControl
            }
        }
    }

    let style: Style
    let opacity: Double
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(style.color.opacity(opacity))
        )
    }
}

extension View {
    /// Applies a raised surface behind this view.
    ///
    /// - Parameters:
    ///   - style: which surface colour — see `SurfaceModifier.Style`.
    ///   - opacity: applied to the fill, not the content. Defaults to fully opaque.
    ///   - cornerRadius: defaults to `CornerRadius.card` (16pt).
    func surface(
        _ style: SurfaceModifier.Style,
        opacity: Double = 1,
        cornerRadius: CGFloat = AppConstants.CornerRadius.card
    ) -> some View {
        modifier(SurfaceModifier(style: style, opacity: opacity, cornerRadius: cornerRadius))
    }
}

#Preview {
    VStack(spacing: 16) {
        Text("CARD").font(.silkscreenLabel).foregroundColor(.textPrimary)
            .frame(maxWidth: .infinity).frame(height: 60)
            .surface(.card)

        Text("CARD 80%").font(.silkscreenLabel).foregroundColor(.textPrimary)
            .frame(maxWidth: .infinity).frame(height: 60)
            .surface(.card, opacity: 0.8)

        Text("CARD, 24pt").font(.silkscreenLabel).foregroundColor(.textPrimary)
            .frame(maxWidth: .infinity).frame(height: 60)
            .surface(.card, cornerRadius: AppConstants.CornerRadius.canvasInner)

        Text("CONTROL").font(.silkscreenLabel).foregroundColor(.textPrimary)
            .frame(maxWidth: .infinity).frame(height: 60)
            .surface(.control)
    }
    .padding()
    .background(Color.surfacePrimary)
}
