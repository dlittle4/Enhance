import SwiftUI
import UIKit

/// A bench for auditioning the vendored shader pack and dialling in the effects Enhance should
/// actually ship.
///
/// The premise is the same as GRADIENT LAB's: these looks cannot be specified, only recognised.
/// Every knob of all forty-one shaders is a live control over a real photo, the shortlist lives
/// in the star strip, and COPY MODIFIER hands back the one line of Swift —
/// `.bcsHolographic(intensity: 0.62, …)` — that reproduces the look via the typed wrappers in
/// `ShaderPackEffects.swift`. Tune by eye, star the keepers, copy, paste into real code.
///
/// **Scaffolding, and meant to be deleted.** When the final set graduates, this view, its store,
/// and the catalog go; the wrappers and `ShaderPack.metal` stay, because the graduated effects
/// call into them.
struct ShaderLabView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var store = ShaderLabStore.shared

    /// Which showcase asset the bench renders. Judged content must be real — these effects read
    /// structure, and a flat fill would flatter every one of them.
    @State private var photoIndex = 1

    @State private var didCopy = false

    private static let photoCount = 8

    var body: some View {
        BottomSheet(isPresented: $isPresented, title: "SHADER LAB", expandable: true) {
            VStack(spacing: 0) {
                // Pinned above the scroll view on purpose: the thing being judged must not move
                // when you reach for the control that changes it.
                preview
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                divider

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        shaderStrip
                        divider
                        parameterSection
                        divider
                        actions
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 48)
                }
            }
            .onAppear {
                // Snapshot for the strip's stable sort; see `orderedShaders`.
                openedFavorites = Set(store.state.favorites)
            }
        }
    }

    // MARK: - Preview

    private var preview: some View {
        let shader = store.selectedShader
        let values = store.values(for: shader)

        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                Image("showcase-\(photoIndex)")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .modifier(LabShaderEffect(shader: shader, values: values))
                    .contentShape(Rectangle())
                    // The interaction-driven shaders (`touchPos`) take the drag; for everyone
                    // else a tap cycles the photo. Both on one canvas would fight — a tap to
                    // move the lens would also swap the picture out from under it — so the
                    // canvas does one or the other and NEXT PHOTO below always works.
                    .gesture(canvasGesture(for: shader, in: geo.size))
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))

            HStack {
                Button {
                    HapticService.selection()
                    advancePhoto()
                } label: {
                    Text("NEXT PHOTO →")
                        .font(.silkscreenSmall)
                        .foregroundColor(mintGreen)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(hasPoint(shader) ? "DRAG TO AIM" : "TAP TO CHANGE PHOTO")
                    .font(.silkscreenSmall)
                    .foregroundColor(.textInactive)
            }
        }
    }

    private func advancePhoto() {
        photoIndex = photoIndex % Self.photoCount + 1
    }

    private func hasPoint(_ shader: ShaderLabShader) -> Bool {
        shader.params.contains { $0.isPoint }
    }

    /// A drag that writes the first point parameter's two slots, or — for shaders with no
    /// point — a zero-distance drag whose end is a tap that cycles the photo.
    private func canvasGesture(for shader: ShaderLabShader, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard let slot = firstPointSlot(of: shader) else { return }
                let x = max(0, min(1, drag.location.x / max(size.width, 1)))
                let y = max(0, min(1, drag.location.y / max(size.height, 1)))
                store.setValue(x, atSlot: slot, for: shader)
                store.setValue(y, atSlot: slot + 1, for: shader)
            }
            .onEnded { drag in
                guard firstPointSlot(of: shader) == nil,
                      abs(drag.translation.width) < 8, abs(drag.translation.height) < 8 else { return }
                HapticService.selection()
                advancePhoto()
            }
    }

    /// The flat-array slot where the shader's first (in practice, only) point parameter starts.
    private func firstPointSlot(of shader: ShaderLabShader) -> Int? {
        var slot = 0
        for param in shader.params {
            if param.isPoint { return slot }
            slot += param.slotCount
        }
        return nil
    }

    // MARK: - Shader strip

    /// Every shader as a chip, two rows deep and scrolling sideways — the presets convention,
    /// because 41 of anything stacked vertically would put PARAMETERS below a screen of picker.
    /// Starred shaders sort to the front: the strip's left edge *is* the final set so far.
    private var shaderStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SHADERS")
                    .font(.silkscreenSectionTitle)
                    .foregroundColor(.white)
                Spacer()
                Text("HOLD TO STAR")
                    .font(.silkscreenSmall)
                    .foregroundColor(.textInactive)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: [GridItem(.fixed(36), spacing: 8), GridItem(.fixed(36))], spacing: 8) {
                        ForEach(orderedShaders) { shader in
                            shaderChip(shader)
                                .id(shader.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 84)
                .onAppear {
                    proxy.scrollTo(store.selectedShader.id, anchor: .center)
                }
            }
        }
    }

    /// Favourites first, catalog order within each half. Deliberately *not* re-sorted while the
    /// lab is open — `orderedShaders` is recomputed on every store change, but a chip that
    /// teleports to the front the moment you star it would yank the strip out from under your
    /// thumb. It does move on next open, which is when the new order reads as information
    /// rather than as the UI misbehaving. (It stays honest because starring doesn't change
    /// *selection*, and selection is what the strip scrolls to.)
    private var orderedShaders: [ShaderLabShader] {
        let starred = ShaderLabCatalog.shaders.filter { openedFavorites.contains($0.id) }
        let rest = ShaderLabCatalog.shaders.filter { !openedFavorites.contains($0.id) }
        return starred + rest
    }

    /// The favourites as they stood when the sheet appeared; see `orderedShaders`.
    @State private var openedFavorites: Set<String> = []

    private func shaderChip(_ shader: ShaderLabShader) -> some View {
        let isSelected = store.selectedShader.id == shader.id
        let isStarred = store.isFavorite(shader.id)

        return Text(isStarred ? "★ \(shader.title)" : shader.title)
            .font(.silkscreenSmall)
            .foregroundColor(isSelected ? .textOnGradient : .textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(isSelected ? mintGreen : Color.surfaceControl)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                HapticService.selection()
                store.select(shader)
            }
            .onLongPressGesture {
                HapticService.selection()
                store.toggleFavorite(shader.id)
            }
    }

    // MARK: - Parameters

    private var parameterSection: some View {
        let shader = store.selectedShader
        let values = store.values(for: shader)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(shader.title)
                    .font(.silkscreenSectionTitle)
                    .foregroundColor(.white)

                Button {
                    HapticService.selection()
                    store.toggleFavorite(shader.id)
                } label: {
                    Text("★")
                        .font(.silkscreenLabel)
                        .foregroundColor(store.isFavorite(shader.id) ? mintGreen : .textInactive)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(shader.animated ? "ANIMATED" : "STATIC")
                    .font(.silkscreenSmall)
                    .foregroundColor(.textInactive)
            }

            ForEach(rowSpecs(for: shader)) { spec in
                ParameterSliderRow(
                    label: spec.label,
                    value: normalized(slotBinding(spec.id, shader: shader), in: spec.range),
                    // Every row's zero is the range's own lower bound — the documented floor,
                    // not a degenerate "off" — so the full lattice is always reachable.
                    allowsZero: true,
                    valueText: format(values.indices.contains(spec.id) ? values[spec.id] : 0, in: spec.range)
                )
            }
        }
    }

    /// One slider row per stored slot: a float parameter is one row, a point parameter is an
    /// X row and a Y row (the canvas drag writes the same two slots — the sliders are for
    /// nudging and for reading the number off).
    private struct RowSpec: Identifiable {
        let id: Int
        let label: String
        let range: ClosedRange<Double>
    }

    private func rowSpecs(for shader: ShaderLabShader) -> [RowSpec] {
        var specs: [RowSpec] = []
        var slot = 0
        for param in shader.params {
            if param.isPoint {
                specs.append(RowSpec(id: slot, label: displayLabel(param.label) + " X", range: 0...1))
                specs.append(RowSpec(id: slot + 1, label: displayLabel(param.label) + " Y", range: 0...1))
            } else {
                specs.append(RowSpec(id: slot, label: displayLabel(param.label), range: param.range))
            }
            slot += param.slotCount
        }
        return specs
    }

    /// `colorShift` → `COLOR SHIFT`. Silkscreen has no lowercase worth reading, and the labels
    /// come from Swift argument names.
    private func displayLabel(_ label: String) -> String {
        var out = ""
        for ch in label {
            if ch.isUppercase { out.append(" ") }
            out.append(ch)
        }
        return out.uppercased()
    }

    private func slotBinding(_ slot: Int, shader: ShaderLabShader) -> Binding<Double> {
        Binding(
            get: {
                let values = store.values(for: shader)
                return values.indices.contains(slot) ? values[slot] : 0
            },
            set: { store.setValue($0, atSlot: slot, for: shader) }
        )
    }

    /// Maps a real range onto the 0…1 lattice `ParameterSliderRow` binds to — the same bridge
    /// the other labs use, for the same rows.
    private func normalized(_ source: Binding<Double>, in range: ClosedRange<Double>) -> Binding<Double> {
        let span = range.upperBound - range.lowerBound
        return Binding(
            get: { (source.wrappedValue - range.lowerBound) / span },
            set: { source.wrappedValue = range.lowerBound + max(0, min(1, $0)) * span }
        )
    }

    /// Knob readouts sized to the range: wide ranges are integers, narrow ones keep the
    /// decimals that actually distinguish two positions on a 20-step lattice.
    private func format(_ value: Double, in range: ClosedRange<Double>) -> String {
        let span = range.upperBound - range.lowerBound
        if span >= 20 { return "\(Int(value.rounded()))" }
        if span >= 2 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    // MARK: - Actions

    private var actions: some View {
        let shader = store.selectedShader
        let snippet = shader.swiftSnippet(values: store.values(for: shader))

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticService.selection()
                UIPasteboard.general.string = snippet
                didCopy = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(didCopy ? "COPIED ✓" : "COPY MODIFIER")
                        .font(.silkscreenLabel)
                        .foregroundColor(mintGreen)
                    // The line itself, visible before you commit to copying it — and a live
                    // readout of the whole tuning that fits in one glance.
                    Text(snippet)
                        .font(.silkscreenSmall)
                        .foregroundColor(.textInactive)
                        .multilineTextAlignment(.leading)
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            Button {
                HapticService.selection()
                store.reset(shader)
            } label: {
                Text("RESET TO PACK DEFAULTS")
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

/// The wrappers' default, matched so the bench shows what a pasted modifier will ship. A file
/// global rather than a static on the modifier: `visualEffect`'s closure is `Sendable`, and a
/// static on a main-actor view type cannot be read from one without a warning.
private let labMaxSampleOffset = CGSize(width: 64, height: 64)

/// Applies the selected shader generically, one `layerEffect` per frame.
///
/// Routed through a `ViewModifier` for the reason `ShaderPackEffects.swift` documents on its
/// own two modifiers: `TimelineView`'s generic can't be inferred around a bare `visualEffect`
/// call, but inside `body(content:)` the content is concrete. The 3600s modulo keeps `float`
/// trig precise over long sessions — same convention as the wrappers.
private struct LabShaderEffect: ViewModifier {
    let shader: ShaderLabShader
    let values: [Double]

    @ViewBuilder
    func body(content: Content) -> some View {
        if shader.animated {
            TimelineView(.animation) { context in
                let t = Float(context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 3600))
                content.visualEffect { view, proxy in
                    view.layerEffect(
                        shader.shader(size: proxy.size, time: t, values: values),
                        maxSampleOffset: labMaxSampleOffset
                    )
                }
            }
        } else {
            content.visualEffect { view, proxy in
                view.layerEffect(
                    shader.shader(size: proxy.size, time: 0, values: values),
                    maxSampleOffset: labMaxSampleOffset
                )
            }
        }
    }
}
