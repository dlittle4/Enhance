import Combine
import Foundation

/// The live, shared EFFECTS LAB state — which effects are on, how each slider is windowed, what
/// each thumbnail renders at, and where the bench was left.
///
/// Deliberately *not* `@AppStorage`, for the reasons `MotionTuningStore` records: the value is a
/// struct, which that wrapper cannot hold, and dragging a window's end has to repaint the preview
/// mid-gesture, which an `ObservableObject` gives directly.
///
/// The editor never reads this object. It reads `lookup`, a value snapshotted into
/// `EditorViewModel` at construction — see `EffectLabLookup` for why that is both simpler and
/// correct. Every write here rebuilds `lookup`, so the next photo opened sees it.
///
/// Persisted as one JSON blob under one key. Scaffolding with the same delete-on-graduation
/// contract as the other labs: COPY SWIFT hands back the `retired` sets and the
/// `EffectTuningTables` literals, and once those are pasted the cleanup is `resetAll()`, deleting
/// this file and `EffectLabView`, and one `removeObject`.
final class EffectLabStore: ObservableObject {

    static let shared = EffectLabStore()

    static let storageKey = "effectLabState"

    /// Everything the lab holds about one effect. Only effects that have been touched have an
    /// entry; the rest fall back to code on read.
    struct Entry: Codable, Equatable {
        /// nil = the code default (on unless retired). Writing the code default *removes* the
        /// override rather than pinning a copy of it, so an untouched effect stays untouched.
        var enabled: Bool? = nil

        /// Windows keyed by parameter id (`intensity`, `size`, …), identity ones omitted.
        var windows: [String: ParameterWindow] = [:]

        var thumbnail = ThumbnailPreset()

        var isDefault: Bool { enabled == nil && windows.isEmpty && thumbnail.isDefault }

        init(enabled: Bool? = nil, windows: [String: ParameterWindow] = [:], thumbnail: ThumbnailPreset = ThumbnailPreset()) {
            self.enabled = enabled
            self.windows = windows
            self.thumbnail = thumbnail
        }

        private enum CodingKeys: String, CodingKey { case enabled, windows, thumbnail }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = ((try? container.decodeIfPresent(Bool.self, forKey: .enabled)) ?? nil)
            windows = ((try? container.decodeIfPresent([String: ParameterWindow].self, forKey: .windows)) ?? nil) ?? [:]
            thumbnail = ((try? container.decodeIfPresent(ThumbnailPreset.self, forKey: .thumbnail)) ?? nil) ?? ThumbnailPreset()
        }
    }

    struct State: Codable, Equatable {
        /// Keyed by `EffectParameter.effectKey(for:)`. Unknown keys — an effect renamed or
        /// deleted since the blob was written — are kept rather than dropped: a case may come
        /// back, and the lab is the one place a stale entry costs nothing.
        var entries: [String: Entry] = [:]

        /// Which tab the bench was left on, and which chip in each.
        var family: String = "IMAGE"
        var selectedVisual: String = VisualEffectType.chromaShift.rawValue
        var selectedFace: String = FaceFilterType.lazerEyes.rawValue

        init() {}

        private enum CodingKeys: String, CodingKey { case entries, family, selectedVisual, selectedFace }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let fallback = State()
            entries = ((try? container.decodeIfPresent([String: Entry].self, forKey: .entries)) ?? nil) ?? [:]
            family = ((try? container.decodeIfPresent(String.self, forKey: .family)) ?? nil) ?? fallback.family
            selectedVisual = ((try? container.decodeIfPresent(String.self, forKey: .selectedVisual)) ?? nil) ?? fallback.selectedVisual
            selectedFace = ((try? container.decodeIfPresent(String.self, forKey: .selectedFace)) ?? nil) ?? fallback.selectedFace
        }
    }

    @Published var state: State {
        didSet {
            persist()
            lookup = Self.resolve(state, over: tables)
        }
    }

    /// What the editor snapshots. Rebuilt on every write; never mutated in place.
    private(set) var lookup: EffectLabLookup

    private let defaults: UserDefaults

    /// The graduated tables the store overlays. Injectable so tests can assert against an empty
    /// baseline rather than whatever has been pasted into `EffectTuningTables` since.
    struct Tables {
        var windows: [String: ParameterWindow]
        var thumbnails: [String: ThumbnailPreset]

        static let graduated = Tables(windows: EffectTuningTables.windows,
                                      thumbnails: EffectTuningTables.thumbnailPresets)
        static let empty = Tables(windows: [:], thumbnails: [:])
    }

    private let tables: Tables

    /// `defaults` is injectable so tests can round-trip against a scratch suite instead of the
    /// app's own, which would leak a half-dialled window into the next launch of the simulator.
    init(defaults: UserDefaults = .standard, tables: Tables = .graduated) {
        self.defaults = defaults
        self.tables = tables

        let loaded: State
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            loaded = decoded
        } else {
            loaded = State()
        }
        self.state = loaded
        self.lookup = Self.resolve(loaded, over: tables)
    }

    // MARK: - Enabled

    func isEnabled<E: ParameterizedEffect>(_ effect: E) -> Bool {
        lookup.enabledOverrides[EffectParameter.effectKey(for: effect)] ?? !Self.retiredInCode(effect)
    }

    func setEnabled<E: ParameterizedEffect>(_ enabled: Bool, for effect: E) {
        let codeDefault = !Self.retiredInCode(effect)
        update(effect) { $0.enabled = enabled == codeDefault ? nil : enabled }
    }

    /// The number of effects on in a family, over the family's total.
    func enabledCount(visual: Bool) -> (on: Int, total: Int) {
        if visual {
            return (lookup.enabledVisualEffects.count, VisualEffectType.allCases.count)
        }
        return (lookup.enabledFaceFilters.count, FaceFilterType.allCases.count)
    }

    static func retiredInCode<E: ParameterizedEffect>(_ effect: E) -> Bool {
        if let visual = effect as? VisualEffectType { return visual.isRetired }
        if let face = effect as? FaceFilterType { return face.isRetired }
        return false
    }

    // MARK: - Windows

    /// The live window: the lab's, else the graduated table's, else identity.
    func window<E: ParameterizedEffect>(_ paramID: String, for effect: E) -> ParameterWindow {
        lookup.window(paramID, for: effect)
    }

    /// Normalised on the way in (see `ParameterWindow.normalized`), and removed when it comes
    /// back to identity so the blob only carries real decisions. A non-slider id — the
    /// BACKGROUND ONLY toggle — is refused: a window on a switch is meaningless, and a 0…1
    /// remap of its 0/1 value would silently turn it half on.
    func setWindow<E: ParameterizedEffect>(_ window: ParameterWindow, _ paramID: String, for effect: E) {
        guard paramID != EffectParameter.backgroundOnlyID else { return }
        let normalised = window.normalized()
        update(effect) {
            if normalised.isIdentity {
                $0.windows.removeValue(forKey: paramID)
            } else {
                $0.windows[paramID] = normalised
            }
        }
    }

    // MARK: - Thumbnails

    func thumbnail<E: ParameterizedEffect>(for effect: E) -> ThumbnailPreset {
        lookup.thumbnails[EffectParameter.effectKey(for: effect)] ?? ThumbnailPreset()
    }

    func setThumbnailValue<E: ParameterizedEffect>(_ value: Double, _ paramID: String, for effect: E) {
        update(effect) { $0.thumbnail.values[paramID] = max(0, min(1, value)) }
    }

    func setThumbnailProgress<E: ParameterizedEffect>(_ progress: Double?, for effect: E) {
        update(effect) { $0.thumbnail.progress = progress.map { max(0, min(1, $0)) } }
    }

    // MARK: - Reset

    /// Back to code for one effect — and *removed* from the blob, so it reads as untouched.
    func resetEffect<E: ParameterizedEffect>(_ effect: E) {
        state.entries.removeValue(forKey: EffectParameter.effectKey(for: effect))
    }

    /// Everything back to code. Removes the key rather than writing an empty state, so a
    /// fresh install and a reset lab are indistinguishable.
    func resetAll() {
        // State first: its setter persists, so the removal has to come after it.
        state = State()
        defaults.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Snippet

    /// The graduated result as Swift: the two `retired` literals and the two
    /// `EffectTuningTables` tables, each labelled with the declaration it replaces. Paste-only.
    ///
    /// The retired sets are always emitted in full — they *are* the final set — while the
    /// tables carry only what differs from identity. Case names come from `String(describing:)`,
    /// which prints the case name for a String-backed enum; `EffectLabTests` pins that.
    var swiftSnippet: String {
        let retiredVisual = VisualEffectType.allCases.filter { !lookup.isEnabled($0) }
        let retiredFace = FaceFilterType.allCases.filter { !lookup.isEnabled($0) }

        var lines: [String] = []
        lines.append("// Copied from EFFECTS LAB. Paste each block over the declaration it names.")
        lines.append("")
        lines.append("// VisualEffectType.swift — replace `retired`:")
        lines.append("static let retired: Set<VisualEffectType> = [\(Self.caseList(retiredVisual))]")
        lines.append("")
        lines.append("// FaceFilterType.swift — replace `retired`:")
        lines.append("static let retired: Set<FaceFilterType> = [\(Self.caseList(retiredFace))]")
        lines.append("")
        lines.append("// EffectParameterWindows.swift — replace `EffectTuningTables.windows`:")
        lines.append(contentsOf: Self.windowsTable(lookup.windows))
        lines.append("")
        lines.append("// EffectParameterWindows.swift — replace `EffectTuningTables.thumbnailPresets`:")
        lines.append(contentsOf: Self.presetsTable(lookup.thumbnails))
        return lines.joined(separator: "\n")
    }

    private static func caseList<E>(_ cases: [E]) -> String {
        cases.map { ".\(String(describing: $0))" }.joined(separator: ", ")
    }

    private static func windowsTable(_ windows: [String: ParameterWindow]) -> [String] {
        guard !windows.isEmpty else { return ["static let windows: [String: ParameterWindow] = [:]"] }
        var lines = ["static let windows: [String: ParameterWindow] = ["]
        for key in windows.keys.sorted() {
            let w = windows[key]!
            lines.append(String(format: "    \"%@\": ParameterWindow(min: %.2f, max: %.2f, defaultValue: %.2f),",
                                key, w.min, w.max, w.defaultValue))
        }
        lines.append("]")
        return lines
    }

    private static func presetsTable(_ presets: [String: ThumbnailPreset]) -> [String] {
        guard !presets.isEmpty else { return ["static let thumbnailPresets: [String: ThumbnailPreset] = [:]"] }
        var lines = ["static let thumbnailPresets: [String: ThumbnailPreset] = ["]
        for key in presets.keys.sorted() {
            let p = presets[key]!
            let values = p.values.keys.sorted()
                .map { String(format: "\"%@\": %.2f", $0, p.values[$0]!) }
                .joined(separator: ", ")
            let valuesLiteral = values.isEmpty ? "[:]" : "[\(values)]"
            let progress = p.progress.map { String(format: "%.2f", $0) } ?? "nil"
            lines.append("    \"\(key)\": ThumbnailPreset(values: \(valuesLiteral), progress: \(progress)),")
        }
        lines.append("]")
        return lines
    }

    // MARK: - Internals

    private func update<E: ParameterizedEffect>(_ effect: E, _ body: (inout Entry) -> Void) {
        let key = EffectParameter.effectKey(for: effect)
        var entry = state.entries[key] ?? Entry()
        body(&entry)
        if entry.isDefault {
            state.entries.removeValue(forKey: key)
        } else {
            state.entries[key] = entry
        }
    }

    /// The store's state overlaid on the graduated tables.
    private static func resolve(_ state: State, over tables: Tables) -> EffectLabLookup {
        var windows = tables.windows
        var thumbnails = tables.thumbnails
        var enabled: [String: Bool] = [:]
        for (effectKey, entry) in state.entries {
            for (paramID, window) in entry.windows where !window.isIdentity {
                windows["\(effectKey)|\(paramID)"] = window
            }
            if !entry.thumbnail.isDefault {
                thumbnails[effectKey] = entry.thumbnail
            }
            if let on = entry.enabled {
                enabled[effectKey] = on
            }
        }
        return EffectLabLookup(windows: windows, thumbnails: thumbnails, enabledOverrides: enabled)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
