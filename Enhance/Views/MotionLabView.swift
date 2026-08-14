import SwiftUI
import UIKit

/// A bench for finding the motion the view-transition experiments should ship with.
///
/// Same premise as GRADIENT LAB and FACE MARKER LAB: a stagger, a start scale and a damping
/// fraction cannot be specified, only recognised. Every knob is live, the preview drives the
/// **real** `EffectCategoryTabs` and `EffectCardView`, and COPY PARAMETERS hands back the Swift to
/// paste once something feels right.
///
/// **Scaffolding, and meant to be deleted.** See `MotionTuning` for what graduation looks like.
struct MotionLabView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var store = MotionTuningStore.shared

    /// Drives the preview independently of the flags, so a change can be judged without first
    /// turning it on for the whole app. APPLY is what pushes these out to the flags.
    @State private var previewEntrance = true
    @State private var previewCategorySwitch = true
    @State private var previewTabScale = true
    @State private var previewTilePress = true

    /// Bumped by REPLAY ENTRANCE. A counter rather than a bool because the interesting event is
    /// *another* tap, and a bool has nowhere to put the second one — the same reason
    /// `FaceMarkerLabView` uses one.
    @State private var replayToken = 0

    @State private var previewCategory: EffectCategory = .zoomEffects
    @State private var didCopy = false
    @State private var didApply = false

    @AppStorage(FeatureFlags.motionEntranceKey) private var entranceFlag = false
    @AppStorage(FeatureFlags.motionCategorySwitchKey) private var categorySwitchFlag = false
    @AppStorage(FeatureFlags.motionTabScaleKey) private var tabScaleFlag = false
    @AppStorage(FeatureFlags.motionTilePressKey) private var tilePressFlag = false

    private var tuning: Binding<MotionTuning> { $store.tuning }

    var body: some View {
        BottomSheet(isPresented: $isPresented, title: "MOTION LAB", expandable: true) {
            VStack(spacing: 0) {
                // Pinned above the scroll on purpose: the thing being judged must not move when
                // you reach for the control that changes it.
                preview
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                divider

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        presetStrip
                        divider
                        globalCurveSection
                        divider
                        entranceSection
                        divider
                        categorySwitchSection
                        divider
                        tabSection
                        divider
                        tilePressSection
                        divider
                        actions
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 48)
                }
            }
            .onAppear(perform: syncPreviewToFlags)
        }
    }

    /// Opens showing what the app is currently wearing, so APPLY starts out honest.
    ///
    /// The exception is a first visit with every flag off: previewing nothing would make the lab
    /// look broken, so that case falls back to all four on — they are what you came here to look
    /// at, and unlike GRADIENT LAB's mutually-exclusive styles these compose freely.
    private func syncPreviewToFlags() {
        guard entranceFlag || categorySwitchFlag || tabScaleFlag || tilePressFlag else {
            previewEntrance = true
            previewCategorySwitch = true
            previewTabScale = true
            previewTilePress = true
            return
        }
        previewEntrance = entranceFlag
        previewCategorySwitch = categorySwitchFlag
        previewTabScale = tabScaleFlag
        previewTilePress = tilePressFlag
    }

    // MARK: - Preview

    /// The real tab row over real effect cards, in a miniature of the editor's controls area.
    ///
    /// Deliberately not a lookalike: `FaceMarkerLabView` records why — "a SwiftUI lookalike would
    /// be a second implementation to keep in step, and it would drift", and then the lab would be
    /// tuning something the app does not ship.
    private var preview: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                previewChip("ENTRANCE", isOn: $previewEntrance)
                previewChip("SWITCH", isOn: $previewCategorySwitch)
                previewChip("TAB", isOn: $previewTabScale)
                previewChip("PRESS", isOn: $previewTilePress)
            }

            MotionPreviewStage(
                tuning: store.tuning,
                category: $previewCategory,
                entranceEnabled: previewEntrance,
                categorySwitchEnabled: previewCategorySwitch,
                tabScaleEnabled: previewTabScale,
                tilePressEnabled: previewTilePress,
                replayToken: replayToken
            )

            HStack(spacing: 16) {
                Button {
                    HapticService.selection()
                    replayToken += 1
                } label: {
                    Text("REPLAY ENTRANCE")
                        .font(.silkscreenSmall)
                        .foregroundColor(.enhanceMint)
                }
                .buttonStyle(.plain)

                Text("TAP A TAB · PRESS AND HOLD A CARD")
                    .font(.silkscreenSmall)
                    .foregroundColor(.textInactive)
            }
        }
    }

    private func previewChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            HapticService.selection()
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.silkscreenSmall)
                .foregroundColor(isOn.wrappedValue ? .textOnGradient : .textInactive)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isOn.wrappedValue ? Color.enhanceMint : Color.surfaceControl)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Presets

    /// A scrolling strip of saved tunings. Each swatch shows its curve rather than a name you
    /// typed, so a feel is recognised rather than recalled — the graph is what a motion preset
    /// looks like, the way a gradient swatch is what a colour preset looks like.
    private var presetStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PRESETS")
                    .font(.silkscreenSectionTitle)
                    .foregroundColor(.white)
                Spacer()
                if !store.savedPresets.isEmpty {
                    Text("HOLD TO DELETE")
                        .font(.silkscreenSmall)
                        .foregroundColor(.textInactive)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.presets) { preset in
                        presetSwatch(preset)
                    }
                    saveSwatch
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func presetSwatch(_ preset: MotionPreset) -> some View {
        VStack(spacing: 4) {
            // The global bold, its four animations thin behind it — so a preset that pulls its
            // animations apart is visibly different from one that moves as a whole. Plotting the
            // global alone made ORIGINAL and SUGGESTED render identically, which defeats a strip
            // whose job is recognition.
            MotionCurveGraphView(
                curve: preset.tuning.globalCurve,
                companions: [
                    preset.tuning.entranceEffective,
                    preset.tuning.categorySwitchEffective,
                    preset.tuning.tabEffective,
                    preset.tuning.tilePressEffective
                ],
                showsGroundTruth: false,
                height: 44
            )
            .frame(width: 72)
            .overlay(
                RoundedRectangle(cornerRadius: AppConstants.CornerRadius.standard, style: .continuous)
                    .strokeBorder(Color.enhanceMint, lineWidth: preset.tuning == store.tuning ? 3 : 0)
            )

            Text(preset.title ?? "SAVED")
                .font(.silkscreenSmall)
                .foregroundColor(.textInactive)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticService.selection()
            store.load(preset)
        }
        .onLongPressGesture {
            guard !preset.isBuiltIn else { return }
            HapticService.selection()
            store.delete(preset)
        }
    }

    private var saveSwatch: some View {
        Button {
            HapticService.selection()
            store.saveCurrentAsPreset()
        } label: {
            Text("+")
                .font(.silkscreenTitle)
                .foregroundColor(.enhanceMint)
                .frame(width: 72, height: 44)
                .background(Color.surfaceControl)
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.standard, style: .continuous))
        }
        .buttonStyle(.plain)
        // Keeps the row's baseline aligned with the titled swatches beside it.
        .padding(.bottom, 16)
    }

    // MARK: - Global curve

    private var globalCurveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GLOBAL CURVE")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            Text("EVERY ANIMATION USES THIS UNLESS IT SAYS CUSTOM.")
                .font(.silkscreenSmall)
                .foregroundColor(.textInactive)

            MotionCurveGraphView(curve: store.tuning.globalCurve)

            curveSliders(for: tuning.globalCurve)
        }
    }

    /// The two sliders every curve section shares. `RESPONSE` is time to settle; `DAMPING` is how
    /// much it rings on the way — below 1 overshoots, at 1 and above it does not.
    private func curveSliders(for curve: Binding<MotionCurve>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ParameterSliderRow(
                label: "RESPONSE",
                value: normalized(curve.response, in: 0.05...0.8),
                valueText: String(format: "%.2fS", curve.wrappedValue.response)
            )
            ParameterSliderRow(
                label: "DAMPING",
                value: normalized(curve.dampingFraction, in: 0.2...1.2),
                valueText: String(format: "%.2f", curve.wrappedValue.dampingFraction)
            )
        }
    }

    // MARK: - Per-animation sections

    private var entranceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EDITOR ENTRANCE")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            ParameterSliderRow(
                label: "STAGGER",
                value: normalized(tuning.entranceStagger, in: 0...0.2),
                allowsZero: true,
                valueText: store.tuning.entranceStagger < 0.005
                    ? "TOGETHER"
                    : String(format: "%.3fS", store.tuning.entranceStagger)
            )
            ParameterSliderRow(
                label: "START SCALE",
                value: normalized(tuning.entranceScale, in: 0.6...1),
                valueText: String(format: "%.2f×", store.tuning.entranceScale)
            )
            ParameterSliderRow(
                label: "RISE",
                value: normalized(tuning.entranceOffsetY, in: 0...48),
                allowsZero: true,
                valueText: "\(Int(store.tuning.entranceOffsetY))PT"
            )

            curveOverride(
                override: tuning.entranceCurve,
                effective: store.tuning.entranceEffective
            )
        }
    }

    private var categorySwitchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CATEGORY SWITCH")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            ParameterSliderRow(
                label: "START SCALE",
                value: normalized(tuning.categorySwitchScale, in: 0.8...1),
                valueText: String(format: "%.2f×", store.tuning.categorySwitchScale)
            )

            curveOverride(
                override: tuning.categorySwitchCurve,
                effective: store.tuning.categorySwitchEffective
            )
        }
    }

    private var tabSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TAB SELECTION")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            ParameterSliderRow(
                label: "CAPSULE FROM",
                value: normalized(tuning.tabScaleFrom, in: 0.3...1),
                valueText: String(format: "%.2f×", store.tuning.tabScaleFrom)
            )

            curveOverride(
                override: tuning.tabCurve,
                effective: store.tuning.tabEffective
            )
        }
    }

    private var tilePressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TILE PRESS")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            ParameterSliderRow(
                label: "PRESS SCALE",
                value: normalized(tuning.tilePressScale, in: 0.85...1),
                valueText: String(format: "%.2f×", store.tuning.tilePressScale)
            )
            ParameterSliderRow(
                label: "DIM",
                value: normalized(tuning.tileBrightnessDelta, in: -0.2...0),
                allowsZero: true,
                valueText: String(format: "%.2f", store.tuning.tileBrightnessDelta)
            )

            curveOverride(
                override: tuning.tilePressCurve,
                effective: store.tuning.tilePressEffective
            )
        }
    }

    /// USE GLOBAL / CUSTOM, the graph, and — when custom — this animation's own two sliders.
    ///
    /// The graph draws the global dimmed behind the effective curve, so the gap between the two
    /// lines *is* the micro-adjustment, seen rather than inferred from four numbers.
    ///
    /// Switching to CUSTOM seeds the override from the *current* global rather than from some
    /// other default, so the first thing CUSTOM shows is a graph with no gap; the sliders then
    /// move it away from there. Switching back sets the override to `nil` rather than hiding it,
    /// so a later global retune actually reaches this animation again.
    @ViewBuilder
    private func curveOverride(
        override: Binding<MotionCurve?>,
        effective: MotionCurve
    ) -> some View {
        let isCustom = override.wrappedValue != nil

        VStack(alignment: .leading, spacing: 12) {
            SegmentedToggle(
                items: [false, true],
                selection: Binding(
                    get: { isCustom },
                    set: { wantsCustom in
                        override.wrappedValue = wantsCustom ? store.tuning.globalCurve : nil
                    }
                ),
                label: { $0 ? "CUSTOM" : "USE GLOBAL" }
            )

            MotionCurveGraphView(
                curve: effective,
                reference: isCustom ? store.tuning.globalCurve : nil
            )

            if isCustom {
                curveSliders(for: Binding(
                    get: { override.wrappedValue ?? store.tuning.globalCurve },
                    set: { override.wrappedValue = $0 }
                ))
            }
        }
    }

    /// Maps a real range onto the 0…1 lattice `ParameterSliderRow` binds to.
    ///
    /// The row is a 20-step discrete control (`EffectParameter.sliderSteps`) and its knob shows a
    /// position, not a value — which is why every row above passes `valueText` with real units.
    private func normalized(_ source: Binding<Double>, in range: ClosedRange<Double>) -> Binding<Double> {
        let span = range.upperBound - range.lowerBound
        return Binding(
            get: { (source.wrappedValue - range.lowerBound) / span },
            set: { source.wrappedValue = range.lowerBound + max(0, min(1, $0)) * span }
        )
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The sliders already write the shared store and are live in the editor. What does
            // *not* leave this sheet is the four preview chips, which is what APPLY pushes into
            // the feature flags. Never disabled, even when the flags already match — a dead
            // commit button reads as the lab being broken rather than as the app agreeing with
            // it, which GRADIENT LAB learned the hard way.
            Button {
                HapticService.medium()
                entranceFlag = previewEntrance
                categorySwitchFlag = previewCategorySwitch
                tabScaleFlag = previewTabScale
                tilePressFlag = previewTilePress
                didApply = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didApply = false }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(didApply ? "APPLIED ✓" : "APPLY TO APP")
                        .font(.silkscreenLabel)
                        .foregroundColor(.enhanceMint)
                    Text(isApplied
                         ? "SLIDERS ALREADY LIVE · CHIPS IN SYNC"
                         : "SLIDERS ALREADY LIVE · SETS THE CHIPS")
                        .font(.silkscreenSmall)
                        .foregroundColor(.textInactive)
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            Button {
                HapticService.selection()
                UIPasteboard.general.string = store.tuning.swiftSnippet
                didCopy = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
            } label: {
                Text(didCopy ? "COPIED ✓" : "COPY PARAMETERS")
                    .font(.silkscreenLabel)
                    .foregroundColor(didCopy ? .enhanceMint : .textPrimary)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            Button {
                HapticService.selection()
                store.reset()
            } label: {
                Text("RESET TO DEFAULTS")
                    .font(.silkscreenLabel)
                    .foregroundColor(.textInactive)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }

    private var isApplied: Bool {
        entranceFlag == previewEntrance
            && categorySwitchFlag == previewCategorySwitch
            && tabScaleFlag == previewTabScale
            && tilePressFlag == previewTilePress
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(height: 1)
    }
}

// MARK: - Preview stage

/// A miniature of the editor's controls area, built from the shipping components.
///
/// Split out of `MotionLabView` because it owns the entrance's replay state, and that state has
/// to reset and re-run without the surrounding sheet re-evaluating — the same separation
/// `FaceMarkerPreview` makes for the same reason.
private struct MotionPreviewStage: View {
    let tuning: MotionTuning
    @Binding var category: EffectCategory
    let entranceEnabled: Bool
    let categorySwitchEnabled: Bool
    let tabScaleEnabled: Bool
    let tilePressEnabled: Bool
    let replayToken: Int

    /// Drives the staggered entrance exactly as `EditorView.showControls` does.
    @State private var shown = false

    private let cardSize: CGFloat = 64
    private let cards = ["ORIGINAL", "ZOOM IN", "ZOOM OUT", "PULSE"]

    var body: some View {
        VStack(spacing: 8) {
            EffectCategoryTabs(
                selection: $category,
                motion: tabScaleEnabled
                    ? .init(scaleFrom: tuning.tabScaleFrom, curve: tuning.tabEffective)
                    : nil
            )
            .chromeEntrance(entranceMotion, shown: shown, index: 0)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { index, title in
                        EffectCardView(
                            title: title,
                            thumbnail: nil,
                            isActive: index == 0,
                            size: cardSize,
                            action: { HapticService.light() }
                        )
                    }
                }
            }
            .frame(height: cardSize)
            // Re-inserted on every category change so the switch transition actually plays —
            // the real editor swaps a different grid per category, and `id` reproduces that here
            // without needing four stand-in grids.
            .id(category)
            .transition(categoryTransition)
            .chromeEntrance(entranceMotion, shown: shown, index: 1)
        }
        .environment(\.effectCardPressMotion, tilePressEnabled
            ? .init(
                scale: tuning.tilePressScale,
                brightness: tuning.tileBrightnessDelta,
                curve: tuning.tilePressEffective
              )
            : nil)
        .animation(
            categorySwitchEnabled ? tuning.categorySwitchEffective.animation : .easeInOut(duration: 0.25),
            value: category
        )
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous)
                .fill(Color.surfacePrimary)
        )
        .onAppear(perform: playEntrance)
        .onChange(of: replayToken) { _, _ in playEntrance() }
    }

    /// The same value `EditorView` builds, so the preview and the editor stagger identically.
    private var entranceMotion: ChromeEntrance.Motion? {
        guard entranceEnabled else { return nil }
        return .init(
            stagger: tuning.entranceStagger,
            scale: tuning.entranceScale,
            offsetY: tuning.entranceOffsetY,
            curve: tuning.entranceEffective
        )
    }

    private var categoryTransition: AnyTransition {
        guard categorySwitchEnabled, tuning.categorySwitchScale != 1 else { return .opacity }
        return .opacity.combined(with: .scale(scale: tuning.categorySwitchScale, anchor: .center))
    }

    /// Snaps back to the pre-entrance state, then plays forward — otherwise a replay would
    /// animate from "already arrived" to "already arrived", which is nothing.
    private func playEntrance() {
        shown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            shown = true
        }
    }
}
