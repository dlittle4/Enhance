import SwiftUI

/// The four-icon category row above the effect card gallery: ZOOM, FACE, IMAGE, TEXT.
///
/// Extracted from `EditorView` so MOTION LAB can preview **this** row rather than a lookalike.
/// `FaceMarkerLabView` made the same move with `FaceMarkerVariantList`, for the reason its comment
/// gives: a second implementation to keep in step will drift, and then the lab tunes something the
/// app does not ship. The extraction is otherwise a pure refactor — same geometry, same colours.
struct EffectCategoryTabs: View {

    @Binding var selection: EffectCategory

    /// Called before the selection changes, for the undo push. The editor pushes; the lab does not.
    var onWillChange: (() -> Void)? = nil

    /// Tuned motion for the selected capsule, or `nil` for the app's shipped behaviour — a plain
    /// colour cross-fade at whatever animation the enclosing state change carries.
    ///
    /// Passed in rather than read from `MotionTuningStore` here, so this component has no opinion
    /// about feature flags and the lab can force it on while the app leaves it off.
    var motion: TabMotion? = nil

    /// What the tab pop needs to know. A value, so the component stays free of the store.
    struct TabMotion: Equatable {
        var scaleFrom: Double
        var curve: MotionCurve
    }

    private static let tabs: [(asset: String, category: EffectCategory)] = [
        ("icon-zoom-in", .zoomEffects),
        ("icon-smile", .faceFilters),
        ("icon-image", .visualEffects),
        ("icon-text", .text)
    ]

    var body: some View {
        // Space-between, not a fixed gap: the design distributes the four tabs across the
        // full width with the first and last flush to the edges.
        HStack(spacing: 0) {
            ForEach(Array(Self.tabs.enumerated()), id: \.offset) { index, tab in
                icon(tab.asset, category: tab.category)
                if index < Self.tabs.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: AppConstants.Layout.categoryTabsHeight)
    }

    private func icon(_ assetName: String, category: EffectCategory) -> some View {
        let isActive = selection == category
        return Button {
            guard selection != category else { return }
            onWillChange?()
            HapticService.selection()
            selection = category
        } label: {
            // 72x40 on every tab, selected or not — the design gives each the same
            // 24pt icon inside 24pt horizontal and 8pt vertical padding, and only the
            // selected one paints a background. Sizing them all identically is what keeps
            // the row from shifting when the selection moves.
            Image(assetName)
                .renderingMode(.template)
                .foregroundColor(isActive ? .enhanceMint : .textInactive)
                .frame(width: 72, height: 40)
                .background(
                    // Fill only — the 1pt mint outline is gone *(user's call, 2026-08-15)*.
                    // It also retires the stroke/fill arrival mismatch the scaled capsule
                    // used to have, since there is now one shape to grow rather than two.
                    Capsule()
                        .fill(isActive ? Color.mintDim : Color.clear)
                        // Grows in rather than fading in at full size. At the default
                        // `scaleFrom` of 1 this is inert, which is today's behaviour.
                        .scaleEffect(isActive ? 1 : (motion?.scaleFrom ?? 1))
                )
                // **Its own animation, deliberately.** The capsule sits inside whatever animation
                // drives the category switch, so without this it would inherit that curve — and
                // the whole point of a per-animation micro-adjustment is that the tab pop can
                // differ from the content switch. A modifier this close to the view wins for the
                // view's own properties. With both on the global curve the two resolve to the
                // same value and behave as one animation, which is the shipped default.
                .animation(motion?.curve.animation, value: isActive)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct Harness: View {
        @State private var selection: EffectCategory = .zoomEffects
        var body: some View {
            VStack(spacing: 32) {
                EffectCategoryTabs(selection: $selection)

                EffectCategoryTabs(
                    selection: $selection,
                    motion: .init(
                        scaleFrom: 0.7,
                        curve: MotionCurve(response: 0.22, dampingFraction: 0.6)
                    )
                )
            }
            .padding(16)
            .background(Color.surfacePrimary)
        }
    }
    return Harness()
}
