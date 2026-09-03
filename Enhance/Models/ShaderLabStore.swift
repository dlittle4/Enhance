import Combine
import Foundation

/// The live, shared SHADER LAB state — which shader is on the bench, every shader's dialled-in
/// values, and the favourites shortlist.
///
/// Deliberately *not* `@AppStorage`, for the reasons `MotionTuningStore` records: the value is a
/// struct, which that wrapper cannot hold, and dragging a slider has to repaint the preview
/// mid-gesture, which an `ObservableObject` gives directly.
///
/// Persisted as one JSON blob under one key. The lab is scaffolding with the same
/// delete-on-graduation contract as the others, and when it goes the cleanup is a single
/// `removeObject`.
final class ShaderLabStore: ObservableObject {

    static let shared = ShaderLabStore()

    static let storageKey = "shaderLabState"

    struct State: Codable, Equatable {
        /// Which shader the bench shows. A name, not an index — the catalog is generated and
        /// its order can change under a refresh without orphaning the selection.
        var selectedID: String = "bcsHolographic"

        /// Every shader's tuned values, keyed by modifier name, in each shader's flat slot
        /// order. Only shaders that have actually been touched appear; the rest fall back to
        /// the catalog defaults on read.
        var values: [String: [Double]] = [:]

        /// The shortlist — the point of the lab is to end with a *final set*, and the set has
        /// to live somewhere while it is being narrowed. Insertion order, so the strip reads
        /// as the order you picked them.
        var favorites: [String] = []
    }

    @Published var state: State {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    /// `defaults` is injectable so tests can round-trip against a scratch suite instead of the
    /// app's own, which would leak a half-dialled shader into the next launch of the simulator.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            self.state = decoded
        } else {
            self.state = State()
        }
    }

    // MARK: - Selection

    var selectedShader: ShaderLabShader {
        // The fallback covers a persisted selection whose shader left the catalog in a
        // refresh; first-in-catalog beats crashing on a force-unwrap.
        ShaderLabCatalog.shader(id: state.selectedID) ?? ShaderLabCatalog.shaders[0]
    }

    func select(_ shader: ShaderLabShader) {
        state.selectedID = shader.id
    }

    // MARK: - Values

    /// The shader's live values — persisted if touched, catalog defaults if not. A stored
    /// array whose length no longer matches the shader's slots (the vendored pack was
    /// refreshed and a parameter came or went) is discarded rather than misread: those
    /// values were dialled against a different signature.
    func values(for shader: ShaderLabShader) -> [Double] {
        let stored = state.values[shader.id]
        let expected = shader.defaultValues
        guard let stored, stored.count == expected.count else { return expected }
        return stored
    }

    func setValue(_ value: Double, atSlot slot: Int, for shader: ShaderLabShader) {
        var current = values(for: shader)
        guard current.indices.contains(slot) else { return }
        current[slot] = value
        state.values[shader.id] = current
    }

    /// Back to the pack's tuned defaults — and *removed* from the blob, so an untouched
    /// shader stays untouched rather than pinned to a copy of today's defaults.
    func reset(_ shader: ShaderLabShader) {
        state.values.removeValue(forKey: shader.id)
    }

    // MARK: - Favourites

    func isFavorite(_ id: String) -> Bool {
        state.favorites.contains(id)
    }

    func toggleFavorite(_ id: String) {
        if let index = state.favorites.firstIndex(of: id) {
            state.favorites.remove(at: index)
        } else {
            state.favorites.append(id)
        }
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
