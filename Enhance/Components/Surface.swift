import SwiftUI

/// A raised surface behind content — the app's pill and card treatment.
///
/// Replaces eight hand-rolled copies of the same three lines:
///
/// ```swift
/// .background(
///     RoundedRectangle(cornerRadius: 16, style: .continuous)
///         .fill(Color(hex: 0x202020).opacity(0.8))
/// )
/// ```
///
/// which becomes `.surface(.raised, opacity: 0.8)`.
///
/// **Opacity is a parameter, not part of the style.** The eight call sites use three different
/// values — 0.8 in the editor, 0.95 and 1.0 in the gallery — and baking one in would have made
/// this primitive unusable for five of them. Same for the corner radius: it defaults to
/// `CornerRadius.card`, but one gallery pill is deliberately `.large` (12pt).
///
/// The `.continuous` corner style is not incidental. Every existing call site uses it, and
/// swapping to the default circular style is a visible change in the corner curve.
struct SurfaceModifier: ViewModifier {

    /// Which surface colour to use. Named for the role, so a theme can reassign them.
    enum Style {
        /// A pill or card sitting on a screen background. The common case.
        case raised
        /// The effect detail panel.
        case panel
        /// A selected cell.
        case active

        var color: Color {
            switch self {
            case .raised: return .surfaceRaised
            case .panel:  return .surfacePanel
            case .active: return .surfaceActive
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
        Text("RAISED").font(.silkscreenLabel).foregroundColor(.textPrimary)
            .frame(maxWidth: .infinity).frame(height: 60)
            .surface(.raised)

        Text("RAISED 80%").font(.silkscreenLabel).foregroundColor(.textPrimary)
            .frame(maxWidth: .infinity).frame(height: 60)
            .surface(.raised, opacity: 0.8)

        Text("PANEL, 20pt").font(.silkscreenLabel).foregroundColor(.textPrimary)
            .frame(maxWidth: .infinity).frame(height: 60)
            .surface(.panel, cornerRadius: AppConstants.Layout.panelCornerRadius)

        Text("ACTIVE").font(.silkscreenLabel).foregroundColor(.textPrimary)
            .frame(maxWidth: .infinity).frame(height: 60)
            .surface(.active)
    }
    .padding()
    .background(Color.surfaceBase)
}
