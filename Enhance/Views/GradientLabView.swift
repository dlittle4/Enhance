import SwiftUI
import UIKit

/// A bench for finding the colours the STATIC and DITHER experiments should ship with.
///
/// The premise is that these looks cannot be specified, only recognised — so rather than guess
/// literals into `GradientViews.swift` and rebuild, every parameter is a live control and
/// COPY PARAMETERS hands back the Swift to paste once something looks right.
///
/// **Scaffolding, and meant to be deleted.** See `GradientTuning` for what graduation looks like.
struct GradientLabView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var store = GradientTuningStore.shared

    /// Drives the preview independently of the flags, so the effect can be judged without first
    /// turning it on for the whole app. APPLY is what pushes these out to the flags.
    @State private var previewStatic = true
    @State private var previewDither = false
    @State private var didCopy = false
    @State private var didApply = false

    /// The live flags, written by APPLY.
    @AppStorage(FeatureFlags.staticGradientKey) private var staticFlag = false
    @AppStorage(FeatureFlags.ditherGradientKey) private var ditherFlag = false

    private var tuning: Binding<GradientTuning> { $store.tuning }

    var body: some View {
        BottomSheet(isPresented: $isPresented, title: "GRADIENT LAB", expandable: true) {
            VStack(spacing: 0) {
                // Pinned above the scroll view on purpose: the thing being judged must not move
                // when you reach for the control that changes it.
                preview
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                divider

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        presetStrip
                        divider

                        // MID only appears at 3 levels, where it is the colour the new threshold
                        // selects. Showing it at 2 would offer a well that changes nothing.
                        colorSection("POLES A", isThreeLevel
                            ? [("LIGHT", tuning.poleLightA), ("MID", tuning.poleMidA), ("DARK", tuning.poleDarkA)]
                            : [("LIGHT", tuning.poleLightA), ("DARK", tuning.poleDarkA)])
                        colorSection("POLES B", isThreeLevel
                            ? [("LIGHT", tuning.poleLightB), ("MID", tuning.poleMidB), ("DARK", tuning.poleDarkB)]
                            : [("LIGHT", tuning.poleLightB), ("DARK", tuning.poleDarkB)])
                        labelSection
                        colorSection("DENSITY FIELD", [
                            ("LIGHT", tuning.meshLight),
                            ("MID", tuning.meshMid),
                            ("DARK", tuning.meshDark)
                        ])
                        colorSection("BORDER", [
                            ("A START", tuning.borderStartA),
                            ("A END", tuning.borderEndA),
                            ("B START", tuning.borderStartB),
                            ("B END", tuning.borderEndB)
                        ])

                        divider
                        sliders
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

    /// Opens showing what the app is currently wearing, so APPLY starts out honestly greyed.
    ///
    /// The exception is a first visit with both flags off: previewing nothing would make the lab
    /// look broken, so that case falls back to STATIC — the one you came here to look at.
    private func syncPreviewToFlags() {
        guard staticFlag || ditherFlag else {
            previewStatic = true
            previewDither = false
            return
        }
        previewStatic = staticFlag
        previewDither = ditherFlag
    }

    private var isThreeLevel: Bool { store.tuning.levels >= 2.5 }

    // MARK: - Presets

    /// A scrolling strip of saved tunings, each rendered with its own values so you recognise the
    /// look rather than recalling a name you typed. The last slot saves the live tuning.
    ///
    /// Each swatch is a real `SimpleGradientBackground`, which means every one on screen is
    /// animating. At 40pt tall on a 12fps schedule that has been fine; if a long strip ever drags,
    /// the fix is to freeze the off-screen ones rather than to fall back to a static thumbnail —
    /// a still frame of a dither tells you almost nothing about how it moves.
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

    private func presetSwatch(_ preset: GradientPreset) -> some View {
        // Rendered under the preset's *own* effect state, so ORIGINAL shows the plain mesh and
        // reads as visibly the odd one out — which is exactly what it is.
        VStack(spacing: 4) {
            SimpleGradientBackground(
                style: .resolve(staticOn: preset.staticOn, ditherOn: preset.ditherOn, tuning: preset.tuning),
                tuning: preset.tuning
            )
            .frame(width: 64, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(mintGreen, lineWidth: isActive(preset) ? 3 : 0)
            )

            if let title = preset.title {
                Text(title)
                    .font(.silkscreenSmall)
                    .foregroundColor(.textInactive)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticService.selection()
            load(preset)
        }
        .onLongPressGesture {
            guard !preset.isBuiltIn else { return }
            HapticService.selection()
            store.delete(preset)
        }
    }

    /// Loading restores the chips as well as the colours — a preset describes a whole look, and
    /// half of ORIGINAL is *not being quantized at all*.
    private func load(_ preset: GradientPreset) {
        store.load(preset)
        previewStatic = preset.staticOn
        previewDither = preset.ditherOn
    }

    /// Matches on the effect state too, so ORIGINAL does not light up merely because the palette
    /// happens to be stock while the quantizer is running.
    private func isActive(_ preset: GradientPreset) -> Bool {
        preset.tuning == store.tuning
            && preset.staticOn == previewStatic
            && preset.ditherOn == previewDither
    }

    private var saveSwatch: some View {
        Button {
            HapticService.selection()
            store.saveCurrentAsPreset(staticOn: previewStatic, ditherOn: previewDither)
        } label: {
            Text("+")
                .font(.silkscreenTitle)
                .foregroundColor(mintGreen)
                .frame(width: 64, height: 44)
                .background(Color.surfaceControl)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        // Keeps the row's baseline aligned with the titled swatches beside it.
        .padding(.bottom, 16)
    }

    // MARK: - Label

    private var labelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LABEL")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            SegmentedToggle(
                items: GradientTuning.LabelMode.allCases,
                selection: Binding(
                    get: { store.tuning.labelMode },
                    set: { store.tuning.labelMode = $0 }
                ),
                label: \.title
            )

            // The measured ratio, not a verdict. WCAG wants 4.5 for body text and 3 for large —
            // a button label at 16pt bold counts as large, so 3 is the bar these have to clear.
            //
            // Reports the *worst* moment in the pulse rather than this one. An instant reading
            // would sit comfortably in the green for most of a cycle that dips into mud at one
            // end, which is precisely the failure worth being warned about.
            Text(contrastReadout)
                .font(.silkscreenSmall)
                .foregroundColor(store.tuning.worstLabelContrast() >= 3 ? mintGreen : Color(hex: 0xFF6B6B))
        }
    }

    private var contrastReadout: String {
        let mode = store.tuning.labelMode == .auto ? "AUTO" : store.tuning.labelMode.title
        return String(format: "%@ · WORST CONTRAST %.1f:1", mode, store.tuning.worstLabelContrast())
    }

    // MARK: - Preview

    private var preview: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                previewToggle("STATIC", isOn: $previewStatic)
                previewToggle("DITHER", isOn: $previewDither)
            }

            HStack(spacing: 12) {
                // Reads the tuning directly rather than through `gradientButtonLabel()`, which
                // resolves against the *flags* — in here the preview chips decide. Same clock and
                // crossfade as the real thing, so what you judge here is what ships.
                TimelineView(.periodic(from: .now, by: 1.0 / 6.0)) { timeline in
                    let color = store.tuning.labelColor(at: timeline.date.timeIntervalSinceReferenceDate)
                    Text("ENHANCE")
                        .font(.silkscreenButtonLabel)
                        .foregroundColor(color)
                        .animation(.easeInOut(duration: 0.35), value: color)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                }
                .background(
                    SimpleGradientBackground(style: previewStyle, tuning: store.tuning)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))

                // The ring gets its own swatch because it has its own flag, and because at a
                // button's 4pt line width a dithered border is easy to misread as a plain one.
                SimpleGradientBorder(
                    cornerRadius: AppConstants.CornerRadius.card,
                    lineWidth: 6,
                    style: previewStyle,
                    tuning: store.tuning
                )
                .frame(width: 88, height: 60)
            }
        }
    }

    private var previewStyle: ButtonGradientStyle {
        .resolve(staticOn: previewStatic, ditherOn: previewDither, tuning: store.tuning)
    }

    private func previewToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            HapticService.selection()
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.silkscreenSmall)
                .foregroundColor(isOn.wrappedValue ? .textOnGradient : .textInactive)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn.wrappedValue ? Color.enhanceMint : Color.surfaceControl)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Colours

    /// Native colour wells, deliberately unstyled.
    ///
    /// `EditorView.gradientStopsContent` records why: a `UIColorWell`'s tap target is its own
    /// swatch rather than the SwiftUI frame around it, so painting over one breaks hit testing,
    /// and ringing one leaves Apple's spectrum ring visible inside the mint one. Labels carry the
    /// meaning here instead, since — unlike shadows/midtones/highlights — "A START" is not
    /// something a colour can tell you by looking at it.
    private func colorSection(_ title: String, _ wells: [(String, Binding<RGBColor>)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            HStack(spacing: 0) {
                ForEach(Array(wells.enumerated()), id: \.offset) { _, well in
                    VStack(spacing: 6) {
                        ColorPicker("", selection: colorBinding(well.1), supportsOpacity: false)
                            .labelsHidden()
                        Text(well.0)
                            .font(.silkscreenSmall)
                            .foregroundColor(.textInactive)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Bridges the well's `Color` to the stored triple. The clamping that matters — a Display P3
    /// picker can hand back components outside 0–1 — lives in `RGBColor.init(_:)`.
    private func colorBinding(_ source: Binding<RGBColor>) -> Binding<Color> {
        Binding(
            get: { source.wrappedValue.color },
            set: { source.wrappedValue = RGBColor($0) }
        )
    }

    // MARK: - Numerics

    private var sliders: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PARAMETERS")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            ParameterSliderRow(
                label: "CELL SIZE",
                value: normalized(tuning.cellSize, in: 1...16),
                valueText: "\(Int(store.tuning.cellSize))PT"
            )
            ParameterSliderRow(
                label: "NOISE",
                value: normalized(tuning.noiseAmount, in: 0...1),
                allowsZero: true,
                valueText: String(format: "%.2f", store.tuning.noiseAmount)
            )
            ParameterSliderRow(
                label: "ORDERED",
                value: normalized(tuning.orderedAmount, in: 0...1),
                allowsZero: true,
                valueText: String(format: "%.2f", store.tuning.orderedAmount)
            )
            ParameterSliderRow(
                label: "HALFTONE",
                value: normalized(tuning.halftoneAmount, in: 0...1),
                allowsZero: true,
                valueText: String(format: "%.2f", store.tuning.halftoneAmount)
            )
            ParameterSliderRow(
                label: "SCREEN ANGLE",
                value: normalized(tuning.halftoneAngle, in: 0...(.pi / 2)),
                allowsZero: true,
                valueText: "\(Int(store.tuning.halftoneAngle * 180 / .pi))°"
            )
            ParameterSliderRow(
                label: "RGB SPLIT",
                value: normalized(tuning.splitDistance, in: 0...12),
                allowsZero: true,
                valueText: String(format: "%.1fPT", store.tuning.splitDistance)
            )
            ParameterSliderRow(
                label: "SPLIT ANGLE",
                value: normalized(tuning.splitAngle, in: 0...(2 * .pi)),
                allowsZero: true,
                valueText: "\(Int(store.tuning.splitAngle * 180 / .pi))°"
            )
            ParameterSliderRow(
                label: "LEVELS",
                value: normalized(tuning.levels, in: 2...3),
                allowsZero: true,
                valueText: "\(Int(store.tuning.levels.rounded()))"
            )
            ParameterSliderRow(
                label: "DRIFT SPEED",
                value: normalized(tuning.driftSpeed, in: 0...80),
                allowsZero: true,
                valueText: "\(Int(store.tuning.driftSpeed))PT/S"
            )
            ParameterSliderRow(
                label: "DRIFT ANGLE",
                value: normalized(tuning.driftAngle, in: 0...(2 * .pi)),
                allowsZero: true,
                valueText: "\(Int(store.tuning.driftAngle * 180 / .pi))°"
            )
            ParameterSliderRow(
                label: "FIELD MORPH",
                value: normalized(tuning.fieldDuration, in: 0.5...12),
                valueText: String(format: "%.1fS", store.tuning.fieldDuration)
            )
            ParameterSliderRow(
                label: "PULSE",
                value: normalized(tuning.pulseDuration, in: 1...12),
                valueText: String(format: "%.1fS", store.tuning.pulseDuration)
            )
            ParameterSliderRow(
                label: "FRAME RATE",
                value: normalized(tuning.staticFrameRate, in: 4...30),
                valueText: "\(Int(store.tuning.staticFrameRate))FPS"
            )
            ParameterSliderRow(
                label: "BORDER SPIN",
                value: normalized(tuning.borderRotationDuration, in: 2...30),
                valueText: String(format: "%.0fS", store.tuning.borderRotationDuration)
            )

            Text("BORDER DIRECTION")
                .font(.silkscreenSubheadline)
                .foregroundColor(.textPrimary)

            SegmentedToggle(
                items: [false, true],
                selection: Binding(
                    get: { store.tuning.borderReversed },
                    set: { store.tuning.borderReversed = $0 }
                ),
                label: { $0 ? "COUNTER-CW" : "CLOCKWISE" }
            )
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
            // The colours and sliders are already live app-wide — the lab writes the shared
            // store. What does *not* leave this sheet is the two preview chips, which is what
            // APPLY pushes into the feature flags.
            // Never disabled, even when the flags already match. Greying it out was the obvious
            // reading of "nothing left to do" and the wrong one *(user hit this after saving a
            // preset)*: the sequence that matters here is tune → save → apply, and finding the
            // last step dead reads as the lab being broken rather than as the app already
            // agreeing with it. Tapping when nothing would change is harmless; being unable to
            // is not.
            Button {
                HapticService.selection()
                staticFlag = previewStatic
                ditherFlag = previewDither
                didApply = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didApply = false }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(didApply ? "APPLIED ✓" : "APPLY TO APP")
                        .font(.silkscreenLabel)
                        .foregroundColor(mintGreen)
                    Text(applyHint)
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
                    .foregroundColor(didCopy ? mintGreen : .textPrimary)
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

    /// Whether the app's flags already match the preview chips.
    private var isApplied: Bool {
        staticFlag == previewStatic && ditherFlag == previewDither
    }

    /// Spells out the split that is otherwise invisible: colours and sliders write the shared
    /// store and are already live everywhere, while the two chips stay in this sheet until
    /// APPLY sends them out.
    private var applyHint: String {
        isApplied ? "COLOURS ALREADY LIVE · EFFECT IN SYNC" : "COLOURS ALREADY LIVE · SETS THE EFFECT"
    }

    // MARK: - Helpers

    private let mintGreen = Color.enhanceMint

    private var divider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(height: 1)
    }
}
