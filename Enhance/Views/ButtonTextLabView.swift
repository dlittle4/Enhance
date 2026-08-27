import SwiftUI
import UIKit

/// A bench for the MAKE A GIF button's animated label: type candidate phrases in, flip between
/// the photo text-effect presets, and set the rotation's rhythm, all against a live replica of
/// the real button.
///
/// The premise is the one every lab here shares — this cannot be specified, only recognised. A
/// phrase that scans in a sentence dies at 16pt on a button, and a preset that delights on a
/// photo can be noise on a CTA; the only way to know is to watch the actual button play it.
///
/// **Scaffolding, and meant to be deleted.** See `ButtonLabelTuning` for what graduation looks
/// like.
struct ButtonTextLabView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var store = ButtonLabelTuningStore.shared

    /// The live flag, written by APPLY. The preview above ignores it on purpose, so the look can
    /// be judged without turning it on for the whole app — the same split GRADIENT LAB draws
    /// between its preview chips and the app's flags.
    @AppStorage(FeatureFlags.buttonTextEffectsKey) private var labelFlag = false

    @State private var didCopy = false
    @State private var didApply = false

    /// A button can hold roughly this much Silkscreen at 16pt before the ends clip. The overlay
    /// model itself allows 120 — this cap is about the destination, not the pipeline.
    private static let maxPhraseLength = 24

    /// Enough slots to compare real candidates, few enough that the raster cache stays a handful
    /// of megabytes rather than a gallery of them.
    private static let maxPhrases = 6

    var body: some View {
        BottomSheet(isPresented: $isPresented, title: "BUTTON TEXT LAB", expandable: true) {
            VStack(spacing: 0) {
                // Pinned above the scroll view on purpose: the thing being judged must not move
                // when you reach for the control that changes it.
                preview
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                divider

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        phrasesSection
                        divider
                        effectSection
                        if store.tuning.animation.usesFromRow {
                            fromSection
                        }
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
        }
    }

    // MARK: - Preview

    /// The gallery button, verbatim: same background component, same height, same radius. The
    /// background reads the gradient flags and tuning itself, so what plays here is what ships —
    /// including the contrast-managed label colour riding on whatever the gradient is doing.
    private var preview: some View {
        AnimatedButtonLabel()
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                ButtonGradientBackground()
                    .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card,
                                                style: .continuous))
            )
    }

    // MARK: - Phrases

    private var phrasesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PHRASES")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            ForEach(store.tuning.phrases.indices, id: \.self) { index in
                phraseRow(index)
            }

            if store.tuning.phrases.count < Self.maxPhrases {
                Button {
                    HapticService.selection()
                    store.tuning.phrases.append("")
                } label: {
                    Text("+ ADD PHRASE")
                        .font(.silkscreenSmall)
                        .foregroundColor(mintGreen)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            Text("PLAYED IN ORDER · BLANK ROWS ARE SKIPPED")
                .font(.silkscreenSmall)
                .foregroundColor(.textInactive)
        }
    }

    private func phraseRow(_ index: Int) -> some View {
        HStack(spacing: 8) {
            TextField("", text: phraseBinding(index),
                      prompt: Text("TYPE A PHRASE").foregroundColor(.white.opacity(0.4)))
                .font(.silkscreenLabel)
                .foregroundColor(.white)
                .tint(mintGreen)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: AppConstants.CornerRadius.control,
                                     style: .continuous)
                        .fill(Color.surfaceControl)
                )

            // The rotation can shrink but not vanish: with one row left there is nothing left to
            // choose between, and a rotation of zero phrases is not a rotation.
            if store.tuning.phrases.count > 1 {
                Button {
                    HapticService.selection()
                    guard store.tuning.phrases.indices.contains(index) else { return }
                    store.tuning.phrases.remove(at: index)
                } label: {
                    Text("✕")
                        .font(.silkscreenLabel)
                        .foregroundColor(.textInactive)
                        .frame(width: 32, height: 46)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Guarded against a row deleted mid-edit: SwiftUI can flush a field's binding after the
    /// index is gone, and an unguarded subscript is a crash on the way out of the sheet.
    private func phraseBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                store.tuning.phrases.indices.contains(index) ? store.tuning.phrases[index] : ""
            },
            set: { newValue in
                guard store.tuning.phrases.indices.contains(index) else { return }
                // No newlines — the label is one line — and a cap sized to the button rather
                // than to the overlay model's 120.
                var cleaned = newValue.replacingOccurrences(of: "\n", with: "")
                if cleaned.count > Self.maxPhraseLength {
                    cleaned = String(cleaned.prefix(Self.maxPhraseLength))
                }
                store.tuning.phrases[index] = cleaned
            }
        )
    }

    // MARK: - Effect

    /// All nine presets as a grid of chips rather than a `SegmentedToggle` — nine segments in one
    /// track would shrink each label past reading, and this choice is the lab's whole subject, so
    /// it gets room.
    private var effectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EFFECT")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                      spacing: 8) {
                ForEach(TextAnimationType.allCases) { preset in
                    effectChip(preset)
                }
            }
        }
    }

    private func effectChip(_ preset: TextAnimationType) -> some View {
        let isSelected = store.tuning.animation == preset
        return Button {
            guard !isSelected else { return }
            HapticService.light()
            store.tuning.animation = preset
        } label: {
            Text(preset.rawValue)
                .font(.silkscreenSubheadline)
                .foregroundColor(isSelected ? .textOnGradient : .textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: AppConstants.CornerRadius.control,
                                     style: .continuous)
                        .fill(isSelected ? Color.enhanceMint : Color.surfaceControl)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - From

    /// SLIDE's edge or GRID's origin, in the same slot — the two controls are exclusive by
    /// preset, exactly as the editor's text panel presents them.
    @ViewBuilder
    private var fromSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FROM")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            if store.tuning.animation.usesDirection {
                SegmentedToggle(
                    items: TextSlideDirection.allCases,
                    selection: Binding(
                        get: { store.tuning.slideDirection },
                        set: { store.tuning.slideDirection = $0 }
                    ),
                    label: \.rawValue
                )
            } else if store.tuning.animation.usesGridOrigin {
                SegmentedToggle(
                    items: TextGridOrigin.allCases,
                    selection: Binding(
                        get: { store.tuning.gridOrigin },
                        set: { store.tuning.gridOrigin = $0 }
                    ),
                    label: \.rawValue
                )
            }
        }
    }

    // MARK: - Sliders

    private var sliders: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PARAMETERS")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            // The active preset's own tunable, under its own name — the same control the text
            // panel shows for an overlay, reading and writing the same 0…1.
            ParameterSliderRow(
                label: store.tuning.animation.parameterLabel,
                value: Binding(
                    get: { store.tuning.parameter },
                    set: { store.tuning.parameter = min(1, max(0, $0)) }
                ),
                allowsZero: true,
                valueText: String(format: "%.2f", store.tuning.parameter)
            )
            ParameterSliderRow(
                label: "ENTRANCE",
                value: normalized(Binding(
                    get: { store.tuning.entranceDuration },
                    set: { store.tuning.entranceDuration = $0 }
                ), in: 0.3...3.0),
                valueText: String(format: "%.1fS", store.tuning.entranceDuration)
            )
            ParameterSliderRow(
                label: "HOLD",
                value: normalized(Binding(
                    get: { store.tuning.holdDuration },
                    set: { store.tuning.holdDuration = $0 }
                ), in: 0.5...6.0),
                valueText: String(format: "%.1fS", store.tuning.holdDuration)
            )
        }
    }

    /// Maps a real range onto the 0…1 lattice `ParameterSliderRow` binds to — the same bridge
    /// GRADIENT LAB documents, for the same 20-step control.
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
            // The phrases and sliders are already live anywhere the flag is on — the lab writes
            // the shared store. What APPLY sends out is the flag itself. Never disabled, for the
            // reason GRADIENT LAB records: a dead last step reads as the lab being broken, and a
            // tap that changes nothing is harmless.
            Button {
                HapticService.selection()
                labelFlag = true
                didApply = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didApply = false }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(didApply ? "APPLIED ✓" : "APPLY TO APP")
                        .font(.silkscreenLabel)
                        .foregroundColor(mintGreen)
                    Text(labelFlag
                            ? "LABEL ALREADY LIVE ON MAKE A GIF"
                            : "TURNS THE ANIMATED LABEL ON · SETTINGS TURNS IT OFF")
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

    // MARK: - Helpers

    private let mintGreen = Color.enhanceMint

    private var divider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(height: 1)
    }
}
