import SwiftUI

// A `\.panelRowHeight` environment value used to live here, so the panel could shrink its rows
// to fit a short device and keep its `ScrollView` disabled — back when a slider drag would have
// lost to that scroll.
//
// **Every part of that has since been superseded, and it was removed on 2026-08-13.**
// `ParameterSliderRow` scoped its drag to the knob (2026-08-12), so the gesture conflict the
// shrinking existed to prevent cannot arise and the scroll is merely accepted (ROADMAP §1a). The
// same redesign gave that row a fixed 49pt track, which left `SegmentedBar` as the value's only
// reader — one control quietly shrinking to 34pt while the identical control in PIXELATE stayed
// 46, which is the inconsistency that got both folded into `SegmentedToggle`.
//
// Rows are fixed-height now. If a row ever needs to adapt again, note what this cost: an
// adaptive height on *one* control is indistinguishable from a bug on every panel that shows it
// next to a fixed one.

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
