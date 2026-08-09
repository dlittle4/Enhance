import SwiftUI

/// Row height for the effect detail panel, adapted to the space the panel actually got.
///
/// The panel's rows are fixed-height, so on a short device three of them plus the header
/// simply do not fit — and because `needsScroll` is measured, an overflow silently
/// enables the `ScrollView`, where `DragGesture(minimumDistance: 0)` loses to the scroll
/// and dragging a slider scrolls the panel instead. Shrinking the rows to fit keeps the
/// scroll disabled, which is what makes that gesture conflict impossible rather than
/// merely unlikely.
///
/// Same reasoning as `AppConstants.Layout.effectCardSize(forControlsHeight:)`: one layout
/// that adapts, rather than a constant that fits the largest device.
private struct PanelRowHeightKey: EnvironmentKey {
    static let defaultValue = AppConstants.Layout.parameterRowHeight
}

extension EnvironmentValues {
    var panelRowHeight: CGFloat {
        get { self[PanelRowHeightKey.self] }
        set { self[PanelRowHeightKey.self] = newValue }
    }
}

extension AppConstants.Layout {
    /// Floor. The slider knob shrinks with the row (see `ParameterSliderRow`), so this
    /// is about legibility and touch target rather than fitting the knob.
    static let parameterRowMinHeight: CGFloat = 34

    /// Row height that lets `rowCount` rows *and the header* fit in `available`.
    ///
    /// The header counts as one more unit: it is the same height as a row, and leaving
    /// it out of the division was enough to overflow by ~8pt on a 4.7" screen — which
    /// re-enabled the scroll and clipped the knob.
    static func parameterRowHeight(forPanelHeight available: CGFloat, rowCount: Int) -> CGFloat {
        guard rowCount > 0, available > 0 else { return parameterRowHeight }
        let gaps = AppConstants.Spacing.small * CGFloat(rowCount)
        let usable = available - AppConstants.Spacing.grid * 2 - gaps
        let perUnit = usable / CGFloat(rowCount + 1)
        return min(parameterRowHeight, max(parameterRowMinHeight, perUnit))
    }
}
