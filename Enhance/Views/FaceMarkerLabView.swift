import SwiftUI
import UIKit

/// A bench for finding the numbers the face-marker experiments should ship with.
///
/// Same premise as GRADIENT LAB: a bracket length, a dim opacity and a hide delay cannot be
/// specified, only recognised. Every knob is live, the preview draws with the **real**
/// `FaceMarkerView` and `FaceSpotlightLayer`, and COPY PARAMETERS hands back the Swift to paste
/// once something looks right.
///
/// **Scaffolding, and meant to be deleted.** See `FaceMarkerTuning` for what graduation looks like.
struct FaceMarkerLabView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var store = FaceMarkerTuningStore.shared

    /// Drives the preview independently of the flags, so a variant can be judged without first
    /// turning it on for the whole app. APPLY is what pushes these out to the flags.
    @State private var previewOptions = FaceMarkerOptions(calm: true, reticle: true)
    @State private var previewSelection: Int? = 0
    @State private var didCopy = false

    @AppStorage(FeatureFlags.faceMarkersCalmKey) private var calmFlag = false
    @AppStorage(FeatureFlags.faceMarkersReticleKey) private var reticleFlag = false
    @AppStorage(FeatureFlags.faceMarkersSpotlightKey) private var spotlightFlag = false
    @AppStorage(FeatureFlags.faceMarkersHiddenKey) private var hiddenFlag = false

    private var tuning: Binding<FaceMarkerTuning> { $store.tuning }

    var body: some View {
        BottomSheet(isPresented: $isPresented, title: "FACE MARKER LAB", expandable: true) {
            VStack(spacing: 0) {
                // Pinned above the scroll view on purpose: the thing being judged must not move
                // when you reach for the control that changes it.
                preview
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                divider

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        variantToggles
                        divider
                        calmSliders
                        divider
                        reticleSliders
                        divider
                        spotlightSliders
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

    /// Opens showing what the app is currently wearing, so the preview is not quietly lying about
    /// what a toggle would do.
    ///
    /// The exception is a first visit sitting on DEFAULT: previewing the unchanged overlay would
    /// make the lab look broken, so that case falls back to CALM + RETICLE — the pair you came here
    /// to look at. Note this reads `hidden` too, so someone who deliberately chose *no markers*
    /// sees that choice reflected rather than being bounced back to a variant.
    private func syncPreviewToFlags() {
        let live = FaceMarkerOptions(
            calm: calmFlag,
            reticle: reticleFlag,
            spotlight: spotlightFlag,
            hidden: hiddenFlag
        )
        previewOptions = live.isDefault ? FaceMarkerOptions(calm: true, reticle: true) : live
    }

    // MARK: - Preview

    /// Two stand-in heads on a flat ground rather than a photograph.
    ///
    /// A real photo would be a better test of the *spotlight* and a worse test of everything else —
    /// bracket weight and label size are judged against the marker, and a busy image is exactly the
    /// noise you do not want while reading a 2pt stroke. Judge the spotlight on a real photo in the
    /// editor; judge the geometry here.
    ///
    /// Tapping a head selects it, which is the only way to see the flash and the lock-on at all.
    private var preview: some View {
        VStack(spacing: 10) {
            FaceMarkerPreview(
                options: previewOptions,
                tuning: store.tuning,
                selectedIndex: $previewSelection
            )
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))

            Text(previewSelection == nil ? "ALL FACES — TAP A HEAD TO SOLO" : "TAP THE SAME HEAD TO GO BACK TO ALL")
                .font(.silkscreenSmall)
                .foregroundColor(.textPrimary)
        }
    }

    // MARK: - Variants

    /// The same four rows Settings shows, from the same component — so the lab and Settings cannot
    /// drift into meaning different things by the same state. The three variants compose; DEFAULT
    /// is the state where none of them do.
    private var variantToggles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("VARIANTS")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            FaceMarkerVariantList(options: $previewOptions)
        }
    }

    // MARK: - Sliders

    private var calmSliders: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CALM")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            ParameterSliderRow(
                label: "AUTO-HIDE",
                value: normalized(tuning.autoHideDelay, in: 0...8),
                allowsZero: true,
                valueText: store.tuning.autoHideDelay < 0.05
                    ? "NEVER"
                    : String(format: "%.1fS", store.tuning.autoHideDelay)
            )
            ParameterSliderRow(
                label: "RESTING",
                value: normalized(tuning.restingOpacity, in: 0...1),
                allowsZero: true,
                valueText: String(format: "%.2f", store.tuning.restingOpacity)
            )
            ParameterSliderRow(
                label: "FLASH",
                value: normalized(tuning.flashDuration, in: 0.05...1),
                valueText: String(format: "%.2fS", store.tuning.flashDuration)
            )
            ParameterSliderRow(
                label: "TAP TARGET",
                value: normalized(tuning.minimumTapTarget, in: 20...64),
                valueText: "\(Int(store.tuning.minimumTapTarget))PT"
            )
        }
    }

    private var reticleSliders: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RETICLE")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            ParameterSliderRow(
                label: "BRACKET",
                value: normalized(tuning.bracketLength, in: 0.05...0.5),
                valueText: String(format: "%.2f", store.tuning.bracketLength)
            )
            ParameterSliderRow(
                label: "THICKNESS",
                value: normalized(tuning.bracketThickness, in: 1...6),
                valueText: String(format: "%.1fPT", store.tuning.bracketThickness)
            )
            ParameterSliderRow(
                label: "MARKER SIZE",
                value: normalized(tuning.markerScale, in: 0.9...1.6),
                valueText: String(format: "%.2f×", store.tuning.markerScale)
            )
            ParameterSliderRow(
                label: "LOCK-ON",
                value: normalized(tuning.lockOnScale, in: 1...1.5),
                valueText: String(format: "%.2f×", store.tuning.lockOnScale)
            )
            ParameterSliderRow(
                label: "LOCK-ON TIME",
                value: normalized(tuning.lockOnDuration, in: 0.05...0.8),
                valueText: String(format: "%.2fS", store.tuning.lockOnDuration)
            )
            ParameterSliderRow(
                label: "LABEL SIZE",
                value: normalized(tuning.labelSize, in: 6...20),
                valueText: "\(Int(store.tuning.labelSize))PT"
            )
            ParameterSliderRow(
                label: "UNSELECTED",
                value: normalized(tuning.unselectedOpacity, in: 0...1),
                allowsZero: true,
                valueText: String(format: "%.2f", store.tuning.unselectedOpacity)
            )

            Text("INDEX CHIP")
                .font(.silkscreenSubheadline)
                .foregroundColor(.textPrimary)

            SegmentedToggle(
                items: [true, false],
                selection: Binding(
                    get: { store.tuning.showsIndexLabel },
                    set: { store.tuning.showsIndexLabel = $0 }
                ),
                label: { $0 ? "FACE 01" : "OFF" }
            )
        }
    }

    private var spotlightSliders: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SPOTLIGHT")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            // Inert until a face is soloed, so say so rather than letting three dead sliders
            // read as a broken variant.
            if previewSelection == nil {
                Text("TAP A HEAD ABOVE — NOTHING DIMS UNTIL ONE IS SOLOED")
                    .font(.silkscreenSmall)
                    .foregroundColor(.textPrimary)
            }

            ParameterSliderRow(
                label: "DIMMING",
                value: normalized(tuning.spotlightDimming, in: 0...0.95),
                allowsZero: true,
                valueText: String(format: "%.2f", store.tuning.spotlightDimming)
            )
            ParameterSliderRow(
                label: "RADIUS",
                value: normalized(tuning.spotlightRadiusScale, in: 0.8...2.5),
                valueText: String(format: "%.2f×", store.tuning.spotlightRadiusScale)
            )
            ParameterSliderRow(
                label: "FEATHER",
                value: normalized(tuning.spotlightFeather, in: 0...1),
                allowsZero: true,
                valueText: String(format: "%.2f", store.tuning.spotlightFeather)
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
        VStack(alignment: .leading, spacing: 16) {
            // The split is invisible otherwise: the sliders write the shared store and are already
            // live in the editor, while the three variant checkmarks are local to this sheet until
            // APPLY. Never disabled, even when the flags already match — a dead commit button reads
            // as the lab being broken rather than as the app already agreeing with it.
            Text("SLIDERS ARE LIVE APP-WIDE. APPLY PUSHES THE VARIANTS.")
                .font(.silkscreenSmall)
                .foregroundColor(.textPrimary)

            Button {
                HapticService.medium()
                calmFlag = previewOptions.calm
                reticleFlag = previewOptions.reticle
                spotlightFlag = previewOptions.spotlight
                hiddenFlag = previewOptions.hidden
            } label: {
                Text("APPLY VARIANTS")
                    .font(.silkscreenButtonLabel)
                    .foregroundColor(Color.enhanceMint)
            }
            .buttonStyle(.plain)

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

// MARK: - Preview canvas

/// Hosts the real marker renderer over two stand-in heads.
///
/// A `UIViewRepresentable` rather than a SwiftUI redraw of the same shapes, because the entire
/// point is that the lab tunes **the shipping code path** — a SwiftUI lookalike would be a second
/// implementation to keep in step, and it would drift.
private struct FaceMarkerPreview: UIViewRepresentable {
    let options: FaceMarkerOptions
    let tuning: FaceMarkerTuning
    @Binding var selectedIndex: Int?

    func makeUIView(context: Context) -> FaceMarkerPreviewView {
        let view = FaceMarkerPreviewView()
        view.onSelect = { index in
            selectedIndex = selectedIndex == index ? nil : index
        }
        return view
    }

    func updateUIView(_ view: FaceMarkerPreviewView, context: Context) {
        view.update(options: options, tuning: tuning, selectedIndex: selectedIndex)
    }
}

private final class FaceMarkerPreviewView: UIView {

    /// Normalized, bottom-left origin — the same convention `DetectedFace.normalizedBoundingBox`
    /// uses, so the preview exercises the same Y-flip the canvas does.
    private static let faces: [(id: UUID, rect: CGRect)] = [
        (UUID(), CGRect(x: 0.10, y: 0.30, width: 0.32, height: 0.42)),
        (UUID(), CGRect(x: 0.58, y: 0.38, width: 0.26, height: 0.34))
    ]

    var onSelect: ((Int) -> Void)?

    private let ground = CALayer()
    private var heads: [CAShapeLayer] = []
    private let spotlight = FaceSpotlightLayer()
    private var markerViews: [FaceMarkerView] = []

    private var options = FaceMarkerOptions.legacy
    private var tuning = FaceMarkerTuning.default
    private var selectedIndex: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        ground.backgroundColor = UIColor(white: 0.16, alpha: 1).cgColor
        layer.addSublayer(ground)

        for _ in Self.faces {
            let head = CAShapeLayer()
            head.fillColor = UIColor(white: 0.42, alpha: 1).cgColor
            layer.addSublayer(head)
            heads.append(head)
        }

        layer.addSublayer(spotlight)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(options: FaceMarkerOptions, tuning: FaceMarkerTuning, selectedIndex: Int?) {
        self.options = options
        self.tuning = tuning
        self.selectedIndex = selectedIndex
        setNeedsLayout()
        layoutIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ground.frame = bounds
        for (index, face) in Self.faces.enumerated() {
            heads[index].path = UIBezierPath(ovalIn: frame(for: face.rect)).cgPath
        }
        CATransaction.commit()

        let markers = FaceMarkerPlan.markers(
            for: Self.faces,
            selectedIndex: selectedIndex,
            options: options
        )

        while markerViews.count > markers.count {
            markerViews.removeLast().removeFromSuperview()
        }
        while markerViews.count < markers.count {
            let view = FaceMarkerView()
            addSubview(view)
            markerViews.append(view)
        }

        for (index, marker) in markers.enumerated() {
            let view = markerViews[index]
            view.frame = frame(for: marker.rect)
            view.configure(
                marker: marker,
                options: options,
                tuning: tuning,
                tint: .enhanceMint,
                // No scroll view here, so no zoom to counter-scale against. The counter-scaling
                // CALM does is only observable in the editor, on a real pinch.
                contentScale: 1,
                onTap: { [weak self] idx in self?.onSelect?(idx) }
            )
        }

        if let rect = FaceMarkerPlan.spotlightRect(in: markers, options: options) {
            spotlight.update(
                spotlighting: tuning.markerRect(for: frame(for: rect)),
                in: bounds,
                tuning: tuning
            )
            // Under every marker, so brackets and the chip stay legible over the dimmed region.
            layer.insertSublayer(spotlight, above: heads.last)
        } else {
            spotlight.hide()
        }

        // With CALM on and no marker drawn, the heads are still tappable — otherwise the preview
        // would offer no way back once a variant hides its own chrome.
        isUserInteractionEnabled = true
    }

    private func frame(for normalized: CGRect) -> CGRect {
        let topY = 1.0 - normalized.origin.y - normalized.height
        return CGRect(
            x: normalized.origin.x * bounds.width,
            y: topY * bounds.height,
            width: normalized.width * bounds.width,
            height: normalized.height * bounds.height
        )
    }

    /// Falls back to hit-testing the heads themselves when no marker is drawn — the single-face
    /// CALM case, and any marker that has faded to resting.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        for (index, face) in Self.faces.enumerated() where frame(for: face.rect).contains(point) {
            onSelect?(index)
            return
        }
    }
}
