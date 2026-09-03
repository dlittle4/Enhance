import SwiftUI
import UIKit

/// A bench for the touch experiments: scrubbing the preview and slider overdrive.
///
/// The overdrive is demonstrated on a real `ParameterSliderRow` at the top, so the red knob, the
/// glitching readout and the ramping haptics can be felt without leaving the sheet. Scrubbing has
/// no stand-in here — its bench is the editor, where the sliders below are already live.
///
/// **Scaffolding, and meant to be deleted.** See `CanvasTuning`.
struct CanvasLabView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var store = CanvasTuningStore.shared

    @AppStorage(FeatureFlags.scrubPreviewKey) private var scrubFlag = false
    @AppStorage(FeatureFlags.sliderOverdriveKey) private var overdriveFlag = false
    @AppStorage(FeatureFlags.pathZoomKey) private var pathFlag = false

    /// The demo slider's value. Local: it drives nothing but the row itself.
    @State private var demoValue: Double = 0.8
    @State private var didCopy = false

    private var tuning: Binding<CanvasTuning> { $store.tuning }

    var body: some View {
        BottomSheet(isPresented: $isPresented, title: "CANVAS LAB", expandable: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    experiments
                    divider
                    overdriveSection
                    divider
                    scrubSection
                    divider
                    pathSection
                    divider
                    actions
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 48)
            }
        }
    }

    private var experiments: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EXPERIMENTS")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)
            labToggle("SCRUB THE PREVIEW", isOn: $scrubFlag)
            labToggle("SLIDER OVERDRIVE", isOn: $overdriveFlag)
            labToggle("STEERABLE ZOOM (PATH)", isOn: $pathFlag)
        }
    }

    private var pathSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PATH")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            Text("JUDGE IN THE EDITOR — PICK PATH, DRAW ON THE PHOTO")
                .font(.silkscreenSmall)
                .foregroundColor(.textPrimary)

            ParameterSliderRow(
                label: "EASE",
                value: normalized(tuning.pathEase, in: 0...1),
                allowsZero: true,
                valueText: String(format: "%.2f", store.tuning.pathEase)
            )
            ParameterSliderRow(
                label: "DWELL",
                value: normalized(tuning.pathDwell, in: 0...0.3),
                allowsZero: true,
                valueText: String(format: "%.2f", store.tuning.pathDwell)
            )
            ParameterSliderRow(
                label: "ZOOM RAMP",
                value: normalized(tuning.pathScaleRamp, in: 0...1),
                allowsZero: true,
                valueText: store.tuning.pathScaleRamp < 0.01 ? "HOLD" : String(format: "%.2f", store.tuning.pathScaleRamp)
            )
            ParameterSliderRow(
                label: "SPACING",
                value: normalized(tuning.pathSampleSpacing, in: 8...80),
                valueText: "\(Int(store.tuning.pathSampleSpacing))PT"
            )

            Text("CORNERS")
                .font(.silkscreenSubheadline)
                .foregroundColor(.textPrimary)

            SegmentedToggle(
                items: [true, false],
                selection: Binding(
                    get: { store.tuning.pathSmoothing },
                    set: { store.tuning.pathSmoothing = $0 }
                ),
                label: { $0 ? "ROUNDED" : "SHARP" }
            )
        }
    }

    private var overdriveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OVERDRIVE")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            Text("DRAG THE KNOB PAST THE END")
                .font(.silkscreenSmall)
                .foregroundColor(.textPrimary)

            ParameterSliderRow(
                label: "DEMO",
                value: $demoValue,
                overdriveMax: store.tuning.overdriveMax,
                overdriveGain: store.tuning.overdriveGain,
                glitchRate: store.tuning.overdriveGlitchRate
            )

            ParameterSliderRow(
                label: "MAX",
                value: normalized(tuning.overdriveMax, in: 1.05...2.5),
                valueText: "\(Int((store.tuning.overdriveMax * 100).rounded()))%"
            )
            ParameterSliderRow(
                label: "GAIN",
                value: normalized(tuning.overdriveGain, in: 1...8),
                valueText: String(format: "%.1f×", store.tuning.overdriveGain)
            )
            ParameterSliderRow(
                label: "GLITCH",
                value: normalized(tuning.overdriveGlitchRate, in: 0...1),
                allowsZero: true,
                valueText: String(format: "%.2f", store.tuning.overdriveGlitchRate)
            )
        }
    }

    private var scrubSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SCRUB")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            Text("JUDGE IN THE EDITOR — DRAG ACROSS A FINISHED GIF")
                .font(.silkscreenSmall)
                .foregroundColor(.textPrimary)

            ParameterSliderRow(
                label: "SPAN",
                value: normalized(tuning.scrubSpan, in: 80...800),
                valueText: "\(Int(store.tuning.scrubSpan))PT"
            )
            ParameterSliderRow(
                label: "TICK EVERY",
                value: normalized(tuning.scrubTickEvery, in: 1...12),
                valueText: "\(Int(store.tuning.scrubTickEvery.rounded())) FR"
            )
        }
    }

    private func labToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            HapticService.selection()
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundColor(isOn.wrappedValue ? Color.enhanceMint : .textInactive)
                    .frame(width: 24, height: 24)
                Text(title)
                    .font(.silkscreenLabel)
                    .foregroundColor(.textPrimary)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func normalized(_ source: Binding<Double>, in range: ClosedRange<Double>) -> Binding<Double> {
        let span = range.upperBound - range.lowerBound
        return Binding(
            get: { (source.wrappedValue - range.lowerBound) / span },
            set: { source.wrappedValue = range.lowerBound + max(0, min(1, $0)) * span }
        )
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SLIDERS ARE LIVE APP-WIDE.")
                .font(.silkscreenSmall)
                .foregroundColor(.textPrimary)

            Button {
                HapticService.selection()
                UIPasteboard.general.string = store.tuning.swiftSnippet
                didCopy = true
            } label: {
                Text(didCopy ? "COPIED ✓" : "COPY PARAMETERS")
                    .font(.silkscreenButtonLabel)
                    .foregroundColor(didCopy ? Color.enhanceMint : .textPrimary)
            }
            .buttonStyle(.plain)

            Button {
                HapticService.selection()
                store.reset()
                didCopy = false
            } label: {
                Text("RESET")
                    .font(.silkscreenButtonLabel)
                    .foregroundColor(.textPrimary)
            }
            .buttonStyle(.plain)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(height: 1)
    }
}
