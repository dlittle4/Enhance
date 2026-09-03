import CoreImage
import SwiftUI
import UIKit

/// A bench for editing down the shipped effects: which IMAGE effects and FACE filters the
/// editor offers, the span of each slider it exposes, and what each picker card renders at.
///
/// Three knobs per effect, judged over a real photo:
///
/// - **ON IN EDITOR** — hold a chip or flip the row. The next photo opened in the editor shows
///   exactly the chips that are on, retired-in-code effects included if you switch them on.
/// - **WINDOWS** — per slider, MIN / MAX / DEFAULT within today's 0…1 span. The editor's knob
///   spans the window and opens at the default; the effect's own `init` is untouched (see
///   `ParameterWindow`). MIN / DEFAULT / MAX above the preview flips it to each end so the ends
///   are what you dial, not the middle.
/// - **THUMBNAIL** — the slider values and progress the card renders at, with the card itself
///   rendered by `EffectThumbnailRenderer`, the editor's own code.
///
/// COPY SWIFT hands back the two `retired` literals and the two `EffectTuningTables` tables;
/// paste, `resetAll()`, and the app renders what the lab showed.
///
/// **Scaffolding, and meant to be deleted.** This view and `EffectLabStore` go on graduation;
/// `EffectParameterWindows.swift` and `EffectThumbnailRenderer` stay, because the editor reads
/// them.
struct EffectLabView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var store = EffectLabStore.shared

    @State private var family: Family = .image
    @State private var photoIndex = 0
    @State private var auditionMode: AuditionMode = .default

    @State private var preview: UIImage?
    @State private var card: UIImage?
    @State private var status: String?
    @State private var didCopy = false

    @State private var photos: [LabPhoto] = []
    @State private var renderTask: Task<Void, Never>?

    /// Detection is cached per photo; it is the slow step and the answer never changes.
    @State private var faceCache: [Int: [DetectedFace]] = [:]

    private let faceService = FaceDetectionService()

    enum Family: String, CaseIterable, Hashable {
        case image = "IMAGE"
        case face = "FACE"
    }

    /// Which end of every window the preview shows.
    enum AuditionMode: String, CaseIterable, Hashable {
        case min = "MIN"
        case `default` = "DEFAULT"
        case max = "MAX"
        case thumbnail = "THUMB"
    }

    var body: some View {
        BottomSheet(isPresented: $isPresented, title: "EFFECTS LAB", expandable: true) {
            VStack(spacing: 0) {
                // Pinned above the scroll view on purpose: the thing being judged must not move
                // when you reach for the control that changes it.
                previewSection
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                divider

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        familySection
                        effectStrip
                        divider
                        effectHeader
                        windowsSection
                        divider
                        thumbnailSection
                        divider
                        actions
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 48)
                }
            }
            .onAppear {
                family = Family(rawValue: store.state.family) ?? .image
                if photos.isEmpty { photos = LabPhoto.load() }
                // FACE opens on a portrait; the first showcase photo is a cat in bedsheets.
                photoIndex = family == .face ? min(1, photos.count - 1) : 0
                scheduleRender()
            }
            .onDisappear { renderTask?.cancel() }
            .onChange(of: family) { _, new in
                store.state.family = new.rawValue
                scheduleRender()
            }
            .onChange(of: photoIndex) { _, _ in scheduleRender() }
            .onChange(of: auditionMode) { _, _ in scheduleRender() }
            .onReceive(store.$state) { _ in scheduleRender() }
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.surfaceControl
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                if let status {
                    Text(status)
                        .font(.silkscreenSmall)
                        .foregroundColor(.textPrimary)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.standard, style: .continuous))
                }
            }
            .frame(height: 260)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                HapticService.selection()
                advancePhoto()
            }

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

                SegmentedToggle(
                    items: AuditionMode.allCases,
                    selection: $auditionMode,
                    label: { $0.rawValue }
                )
                .frame(width: 230)
            }
        }
    }

    private func advancePhoto() {
        guard !photos.isEmpty else { return }
        photoIndex = (photoIndex + 1) % photos.count
    }

    // MARK: - Family

    private var familySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SegmentedToggle(items: Family.allCases, selection: $family, label: { $0.rawValue })

            let count = store.enabledCount(visual: family == .image)
            Text("\(count.on) OF \(count.total) ON")
                .font(.silkscreenSmall)
                .foregroundColor(.textInactive)
        }
    }

    // MARK: - Effect strip

    private var effectStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(family == .image ? "IMAGE EFFECTS" : "FACE FILTERS")
                    .font(.silkscreenSectionTitle)
                    .foregroundColor(.white)
                Spacer()
                Text("HOLD TO TOGGLE")
                    .font(.silkscreenSmall)
                    .foregroundColor(.textInactive)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: [GridItem(.fixed(36), spacing: 8), GridItem(.fixed(36))], spacing: 8) {
                        ForEach(effects) { effect in
                            chip(effect).id(effect.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 84)
                .onAppear { proxy.scrollTo(selected.id, anchor: .center) }
                .onChange(of: family) { _, _ in proxy.scrollTo(selected.id, anchor: .center) }
            }
        }
    }

    private func chip(_ effect: LabEffect) -> some View {
        let isSelected = selected == effect
        let isOn = store.isEnabledLab(effect)

        return Text(effect.retiredInCode ? "\(effect.title) · RETIRED" : effect.title)
            .font(.silkscreenSmall)
            .foregroundColor(isSelected ? .textOnGradient : (isOn ? .textPrimary : .textInactive))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(isSelected ? mintGreen : Color.surfaceControl)
            .opacity(isOn || isSelected ? 1 : 0.45)
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.standard, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                HapticService.selection()
                select(effect)
            }
            .onLongPressGesture {
                HapticService.medium()
                store.setEnabledLab(!isOn, for: effect)
            }
    }

    // MARK: - Effect header

    private var effectHeader: some View {
        let effect = selected
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(effect.title)
                    .font(.silkscreenSectionTitle)
                    .foregroundColor(.white)
                Spacer()
                Text(effect.retiredInCode ? "RETIRED IN CODE" : "SHIPS")
                    .font(.silkscreenSmall)
                    .foregroundColor(.textInactive)
            }

            ParameterToggleRow(
                label: "ON IN EDITOR",
                isOn: Binding(
                    get: { store.isEnabledLab(effect) },
                    set: { store.setEnabledLab($0, for: effect) }
                )
            )
        }
    }

    // MARK: - Windows

    private var windowsSection: some View {
        let effect = selected
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("WINDOWS")
                    .font(.silkscreenSectionTitle)
                    .foregroundColor(.white)
                Spacer()
                Text("OF TODAY'S 0…1")
                    .font(.silkscreenSmall)
                    .foregroundColor(.textInactive)
            }

            ForEach(effect.sliderParameters) { param in
                let window = store.windowLab(param.id, for: effect)
                VStack(alignment: .leading, spacing: 8) {
                    Text(param.label)
                        .font(.silkscreenSmall)
                        .foregroundColor(.textInactive)

                    ParameterSliderRow(
                        label: "MIN",
                        value: windowBinding(param.id, for: effect, \.min),
                        onCommit: { auditionMode = .min },
                        allowsZero: true,
                        valueText: String(format: "%.2f", window.min)
                    )
                    ParameterSliderRow(
                        label: "MAX",
                        value: windowBinding(param.id, for: effect, \.max),
                        onCommit: { auditionMode = .max },
                        allowsZero: true,
                        valueText: String(format: "%.2f", window.max)
                    )
                    // Edited *within* the window, so the knob's lattice position here is the
                    // position the editor's knob will open at.
                    ParameterSliderRow(
                        label: "DEFAULT",
                        value: normalized(windowBinding(param.id, for: effect, \.defaultValue), in: window.min...window.max),
                        onCommit: { auditionMode = .default },
                        allowsZero: true,
                        valueText: String(format: "%.2f", window.defaultValue)
                    )
                }
            }
        }
    }

    private func windowBinding(_ paramID: String, for effect: LabEffect,
                               _ keyPath: WritableKeyPath<ParameterWindow, Double>) -> Binding<Double> {
        Binding(
            get: { store.windowLab(paramID, for: effect)[keyPath: keyPath] },
            set: {
                var window = store.windowLab(paramID, for: effect)
                window[keyPath: keyPath] = $0
                store.setWindowLab(window, paramID, for: effect)
            }
        )
    }

    /// Maps a real range onto the 0…1 lattice `ParameterSliderRow` binds to — the same bridge
    /// the other labs use.
    private func normalized(_ source: Binding<Double>, in range: ClosedRange<Double>) -> Binding<Double> {
        let span = max(range.upperBound - range.lowerBound, 0.0001)
        return Binding(
            get: { (source.wrappedValue - range.lowerBound) / span },
            set: { source.wrappedValue = range.lowerBound + max(0, min(1, $0)) * span }
        )
    }

    // MARK: - Thumbnail

    private var thumbnailSection: some View {
        let effect = selected
        let preset = store.thumbnailLab(for: effect)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("THUMBNAIL")
                        .font(.silkscreenSectionTitle)
                        .foregroundColor(.white)
                    Text("RENDERED LIKE THE EDITOR")
                        .font(.silkscreenSmall)
                        .foregroundColor(.textInactive)
                    Text("VALUES PASS THROUGH THE WINDOW")
                        .font(.silkscreenSmall)
                        .foregroundColor(.textInactive)
                }
                Spacer()
                EffectCardView(title: effect.title, thumbnail: card, isActive: false, size: 110) {
                    auditionMode = .thumbnail
                }
            }

            ForEach(effect.sliderParameters) { param in
                let value = preset.values[param.id] ?? effect.defaultThumbnailValue(param.id)
                ParameterSliderRow(
                    label: param.label,
                    value: Binding(
                        get: { value },
                        set: { store.setThumbnailValueLab($0, param.id, for: effect) }
                    ),
                    onCommit: { auditionMode = .thumbnail }
                )
            }

            let progress = preset.progress ?? Double(effect.previewProgress)
            ParameterSliderRow(
                label: "PROGRESS",
                value: Binding(
                    get: { progress },
                    set: { store.setThumbnailProgressLab($0, for: effect) }
                ),
                onCommit: { auditionMode = .thumbnail },
                allowsZero: true,
                valueText: String(format: "%.2f", progress)
            )
        }
    }

    // MARK: - Actions

    private var actions: some View {
        let snippet = store.swiftSnippet
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticService.selection()
                UIPasteboard.general.string = snippet
                didCopy = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(didCopy ? "COPIED ✓" : "COPY SWIFT")
                        .font(.silkscreenLabel)
                        .foregroundColor(mintGreen)
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
                store.resetEffectLab(selected)
            } label: {
                Text("RESET EFFECT")
                    .font(.silkscreenLabel)
                    .foregroundColor(.textPrimary)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            Button {
                HapticService.selection()
                store.resetAll()
            } label: {
                Text("RESET ALL")
                    .font(.silkscreenLabel)
                    .foregroundColor(.textInactive)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Selection

    private var effects: [LabEffect] {
        switch family {
        case .image: return VisualEffectType.allCases.map(LabEffect.visual)
        case .face: return FaceFilterType.allCases.map(LabEffect.face)
        }
    }

    private var selected: LabEffect {
        switch family {
        case .image:
            return .visual(VisualEffectType(rawValue: store.state.selectedVisual) ?? .chromaShift)
        case .face:
            return .face(FaceFilterType(rawValue: store.state.selectedFace) ?? .lazerEyes)
        }
    }

    private func select(_ effect: LabEffect) {
        switch effect {
        case .visual(let type): store.state.selectedVisual = type.rawValue
        case .face(let filter): store.state.selectedFace = filter.rawValue
        }
    }

    // MARK: - Rendering

    /// Re-renders the preview and the card after a short settle, off the main thread. Every
    /// store write and every local change funnels here; the debounce is what keeps a slider drag
    /// from queueing a render per frame.
    private func scheduleRender() {
        renderTask?.cancel()
        guard photos.indices.contains(photoIndex) else { return }
        let photo = photos[photoIndex]
        let effect = selected
        let mode = auditionMode
        let lookup = store.lookup
        let index = photoIndex
        let cachedFaces = faceCache[index]

        renderTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }

            var faces = cachedFaces
            if effect.isFace, faces == nil {
                await MainActor.run { status = "DETECTING…" }
                faces = await faceService.detectFaces(in: photo.working)
                let detected = faces ?? []
                await MainActor.run { faceCache[index] = detected }
            }
            guard !Task.isCancelled else { return }

            let result = await Task.detached(priority: .userInitiated) {
                Self.render(effect, photo: photo, faces: faces ?? [], mode: mode, lookup: lookup)
            }.value
            guard !Task.isCancelled else { return }

            await MainActor.run {
                preview = result.preview
                card = result.card
                status = result.status
            }
        }
    }

    private struct RenderResult {
        var preview: UIImage?
        var card: UIImage?
        var status: String?
    }

    /// The preview at the audition values and the card through the editor's renderer.
    nonisolated private static func render(_ effect: LabEffect, photo: LabPhoto, faces: [DetectedFace],
                               mode: AuditionMode, lookup: EffectLabLookup) -> RenderResult {
        let renderer = EffectThumbnailRenderer(context: labContext)
        let base = CIImage(cgImage: photo.workingCG)

        switch effect {
        case .visual(let type):
            func value(_ id: String) -> Double { auditionValue(id, for: effect, mode: mode, lookup: lookup) }
            let options = EffectOptions(
                size: value(EffectParameter.sizeID),
                tertiary: value(EffectParameter.tertiaryID),
                quaternary: value(EffectParameter.quaternaryID),
                quinary: value(EffectParameter.quinaryID),
                tintColor: EffectThumbnailRenderer.visualTint,
                gradientStops: .default,
                pixelShape: .square
            )
            let built = type.effect(intensity: value(EffectParameter.intensityID), options: options)
            let output = built.apply(to: base, progress: auditionProgress(for: effect, mode: mode, lookup: lookup),
                                     frameIndex: EffectThumbnailRenderer.visualFrameIndex)
            let previewImage = labContext.createCGImage(output, from: output.extent).map(UIImage.init(cgImage:))
            let cardImage = renderer.render(type, source: photo.thumbCG, lab: lookup)
            return RenderResult(preview: previewImage, card: cardImage, status: nil)

        case .face(let filter):
            guard let first = faces.first else {
                return RenderResult(preview: UIImage(cgImage: photo.workingCG), card: nil,
                                    status: "NO FACE IN THIS PHOTO")
            }
            func value(_ id: String) -> Double { auditionValue(id, for: effect, mode: mode, lookup: lookup) }
            let built = filter.effect(
                intensity: value(EffectParameter.intensityID),
                secondValue: value(EffectParameter.secondaryID),
                laserColor: EffectThumbnailRenderer.faceLaser
            )
            let output = built.apply(to: base, faces: faces,
                                     progress: auditionProgress(for: effect, mode: mode, lookup: lookup),
                                     frameIndex: EffectThumbnailRenderer.faceFrameIndex)
            let previewImage = labContext.createCGImage(output, from: base.extent).map(UIImage.init(cgImage:))
            let crop = EffectThumbnailRenderer.faceCrop(for: first, in: base.extent)
            let cardImage = renderer.render(filter, base: base, face: first, crop: crop, lab: lookup)
            let note = faces.count > 1 ? "\(faces.count) FACES" : nil
            return RenderResult(preview: previewImage, card: cardImage, status: note)
        }
    }

    /// The slider-space `u` the audition mode asks for, through the window — the same arithmetic
    /// the editor's choke point does for the knob at that position.
    nonisolated private static func auditionValue(_ paramID: String, for effect: LabEffect, mode: AuditionMode,
                                      lookup: EffectLabLookup) -> Double {
        let window = effect.window(paramID, lookup: lookup)
        let u: Double
        switch mode {
        case .min: u = 0
        case .max: u = 1
        case .default: u = window.initialSliderValue
        case .thumbnail:
            u = effect.thumbnailPreset(lookup: lookup).values[paramID] ?? effect.defaultThumbnailValue(paramID)
        }
        return window.remap(u)
    }

    nonisolated private static func auditionProgress(for effect: LabEffect, mode: AuditionMode, lookup: EffectLabLookup) -> CGFloat {
        guard mode == .thumbnail, let progress = effect.thumbnailPreset(lookup: lookup).progress else {
            return effect.previewProgress
        }
        return CGFloat(progress)
    }

    // MARK: - Helpers

    private let mintGreen = Color.enhanceMint

    private var divider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(height: 1)
    }
}

// MARK: - LabEffect

/// One chip on the bench: either family, with the handful of per-effect answers the view needs
/// resolved in one place rather than switched on at every use.
enum LabEffect: Hashable, Identifiable {
    case visual(VisualEffectType)
    case face(FaceFilterType)

    var id: String {
        switch self {
        case .visual(let type): return EffectParameter.effectKey(for: type)
        case .face(let filter): return EffectParameter.effectKey(for: filter)
        }
    }

    var title: String {
        switch self {
        case .visual(let type): return type.rawValue
        case .face(let filter): return filter.rawValue
        }
    }

    var isFace: Bool {
        if case .face = self { return true }
        return false
    }

    var retiredInCode: Bool {
        switch self {
        case .visual(let type): return type.isRetired
        case .face(let filter): return filter.isRetired
        }
    }

    var previewProgress: CGFloat {
        switch self {
        case .visual(let type): return type.previewProgress
        case .face(let filter): return filter.previewProgress
        }
    }

    /// View layer only — this allocates, as `ParameterizedEffect.parameters` warns.
    var sliderParameters: [EffectParameter] {
        switch self {
        case .visual(let type): return type.parameters.filter { $0.kind == .slider }
        case .face(let filter): return filter.parameters.filter { $0.kind == .slider }
        }
    }

    func defaultThumbnailValue(_ paramID: String) -> Double {
        paramID == EffectParameter.intensityID
            ? EffectLabLookup.defaultThumbnailIntensity
            : EffectLabLookup.defaultThumbnailSecondary
    }

    func window(_ paramID: String, lookup: EffectLabLookup) -> ParameterWindow {
        switch self {
        case .visual(let type): return lookup.window(paramID, for: type)
        case .face(let filter): return lookup.window(paramID, for: filter)
        }
    }

    func thumbnailPreset(lookup: EffectLabLookup) -> ThumbnailPreset {
        lookup.thumbnails[id] ?? ThumbnailPreset()
    }
}

/// The store's generic API, dispatched over `LabEffect` so the view reads as one path.
private extension EffectLabStore {
    func isEnabledLab(_ effect: LabEffect) -> Bool {
        switch effect {
        case .visual(let type): return isEnabled(type)
        case .face(let filter): return isEnabled(filter)
        }
    }

    func setEnabledLab(_ on: Bool, for effect: LabEffect) {
        switch effect {
        case .visual(let type): setEnabled(on, for: type)
        case .face(let filter): setEnabled(on, for: filter)
        }
    }

    func windowLab(_ paramID: String, for effect: LabEffect) -> ParameterWindow {
        switch effect {
        case .visual(let type): return window(paramID, for: type)
        case .face(let filter): return window(paramID, for: filter)
        }
    }

    func setWindowLab(_ window: ParameterWindow, _ paramID: String, for effect: LabEffect) {
        switch effect {
        case .visual(let type): setWindow(window, paramID, for: type)
        case .face(let filter): setWindow(window, paramID, for: filter)
        }
    }

    func thumbnailLab(for effect: LabEffect) -> ThumbnailPreset {
        switch effect {
        case .visual(let type): return thumbnail(for: type)
        case .face(let filter): return thumbnail(for: filter)
        }
    }

    func setThumbnailValueLab(_ value: Double, _ paramID: String, for effect: LabEffect) {
        switch effect {
        case .visual(let type): setThumbnailValue(value, paramID, for: type)
        case .face(let filter): setThumbnailValue(value, paramID, for: filter)
        }
    }

    func setThumbnailProgressLab(_ progress: Double, for effect: LabEffect) {
        switch effect {
        case .visual(let type): setThumbnailProgress(progress, for: type)
        case .face(let filter): setThumbnailProgress(progress, for: filter)
        }
    }

    func resetEffectLab(_ effect: LabEffect) {
        switch effect {
        case .visual(let type): resetEffect(type)
        case .face(let filter): resetEffect(filter)
        }
    }
}

// MARK: - LabPhoto

/// A photo on the bench, decoded once at the two sizes the editor uses: the 650px working copy
/// the live preview and face cards are built on, and the 120px source the image cards use.
struct LabPhoto: Identifiable, Sendable {
    let id: String
    let working: UIImage
    let workingCG: CGImage
    let thumbCG: CGImage

    init?(id: String, image: UIImage) {
        guard let workingCG = EffectThumbnailRenderer.previewSource(from: image, maxPixel: 650),
              let thumbCG = EffectThumbnailRenderer.thumbnailSource(from: image) else { return nil }
        self.id = id
        self.working = UIImage(cgImage: workingCG)
        self.workingCG = workingCG
        self.thumbCG = thumbCG
    }

    /// The eight showcase stills, then any dev fixtures bundled from `Enhance/DevFixtures/`
    /// (gitignored; the HEAD MASK LAB corpus) for faces the showcase set lacks.
    static func load() -> [LabPhoto] {
        var photos: [LabPhoto] = []
        for index in 1...8 {
            if let image = UIImage(named: "showcase-\(index)"),
               let photo = LabPhoto(id: "showcase-\(index)", image: image) {
                photos.append(photo)
            }
        }
        let fixtures = (Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: nil) ?? [])
            .filter { ["jpg", "jpeg", "heic"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in fixtures {
            if let image = UIImage(contentsOfFile: url.path),
               let photo = LabPhoto(id: url.lastPathComponent, image: image) {
                photos.append(photo)
            }
        }
        return photos
    }
}

/// The bench's own Core Image context. A file global rather than a static on the view: the
/// render runs off the main actor, and a `View`'s statics are main-actor isolated.
private let labContext = CIContext(options: [.useSoftwareRenderer: false])
