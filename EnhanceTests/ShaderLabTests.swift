import Testing
import Foundation
@testable import Enhance

/// Guards the parts of SHADER LAB that a preview cannot show you: that the generated catalog
/// still agrees with itself (a transposed argument renders as garbage with no error anywhere),
/// and that a dialled-in shader survives relaunch.
struct ShaderLabTests {

    // MARK: - Catalog integrity

    /// The pack is 41 shaders; a regeneration that drops one should fail loudly here rather
    /// than as a chip quietly missing from the strip.
    @Test
    func catalog_carriesTheWholePack() {
        #expect(ShaderLabCatalog.shaders.count == 41)
        #expect(Set(ShaderLabCatalog.shaders.map(\.id)).count == 41)
        #expect(ShaderLabCatalog.shaders.allSatisfy { $0.metalName.hasPrefix("bcs_") })
    }

    /// `defaultValues` is the store's fallback and the length every persisted array is checked
    /// against — it must agree with the slot arithmetic everywhere else in the lab.
    @Test
    func catalog_defaultValuesMatchSlotCounts() {
        for shader in ShaderLabCatalog.shaders {
            let slots = shader.params.reduce(0) { $0 + $1.slotCount }
            #expect(shader.defaultValues.count == slots, "\(shader.id)")
        }
    }

    /// Every tuned default must sit on its own slider. Upstream ships one deliberate
    /// exception (`bcsNeonEdge.glowAmount`, default 4 against a documented 0…2); the catalog
    /// widens that range rather than clamping the author's look, and this test keeps it so.
    @Test
    func catalog_defaultsSitInsideTheirRanges() {
        for shader in ShaderLabCatalog.shaders {
            for param in shader.params where !param.isPoint {
                #expect(param.range.contains(param.defaultValue), "\(shader.id).\(param.label)")
            }
        }
    }

    /// The one irregular signature in the pack. Forty animated shaders take `time` right after
    /// `size`; `bcs_chromaticSplit` takes it fourth. If a regeneration ever flattens this to 1,
    /// the shader renders with its spread driven by the clock — wrong, but not an error.
    @Test
    func catalog_timeSlots_matchTheMetalSignatures() {
        for shader in ShaderLabCatalog.shaders {
            switch shader.id {
            case "bcsChromaticSplit":
                #expect(shader.timeSlot == 4)
            case "bcsEmboss", "bcsFrosted", "bcsRefractLens", "bcsTouchRipple":
                #expect(shader.timeSlot == nil, "\(shader.id) is static")
            default:
                #expect(shader.timeSlot == 1, "\(shader.id)")
            }
        }
    }

    // MARK: - The graduation snippet

    /// COPY MODIFIER's output is pasted into real code sight-unseen — its exact shape is the
    /// lab's contract with `ShaderPackEffects.swift`.
    @Test
    func snippet_emitsATypedWrapperCall() throws {
        let shader = try #require(ShaderLabCatalog.shader(id: "bcsHolographic"))

        let snippet = shader.swiftSnippet(values: [0.62, 14, 1.1, 0])

        #expect(snippet == ".bcsHolographic(intensity: 0.62, scale: 14, speed: 1.10, angleOffset: 0)")
    }

    /// A point parameter reads back as a `UnitPoint`, matching the wrapper's signature — two
    /// raw slots leaking into the snippet would not compile at the paste site.
    @Test
    func snippet_reassemblesPointSlotsIntoAUnitPoint() throws {
        let shader = try #require(ShaderLabCatalog.shader(id: "bcsRefractLens"))

        let snippet = shader.swiftSnippet(values: [0.25, 0.75, 0.3, 2, 5, 0.5])

        #expect(snippet == ".bcsRefractLens(touchPos: UnitPoint(x: 0.25, y: 0.75), lensRadius: 0.30, refraction: 2, aberration: 5, wobble: 0.50)")
    }

    // MARK: - Store

    private func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ShaderLabTests-\(UUID().uuidString)")!
    }

    /// An evening of dialling must survive relaunch — the store's whole reason to exist.
    @Test
    func store_roundTripsValuesSelectionAndFavourites() throws {
        let suite = scratchDefaults()
        let shader = try #require(ShaderLabCatalog.shader(id: "bcsGlitch"))

        let first = ShaderLabStore(defaults: suite)
        first.select(shader)
        first.setValue(0.9, atSlot: 0, for: shader)
        first.toggleFavorite("bcsGlitch")
        first.toggleFavorite("bcsAurora")

        let second = ShaderLabStore(defaults: suite)

        #expect(second.selectedShader.id == "bcsGlitch")
        #expect(second.values(for: shader)[0] == 0.9)
        #expect(second.state.favorites == ["bcsGlitch", "bcsAurora"])
    }

    /// An untouched shader reads as the pack's tuned defaults, not zeros.
    @Test
    func store_untouchedShaderFallsBackToPackDefaults() throws {
        let shader = try #require(ShaderLabCatalog.shader(id: "bcsAurora"))

        let store = ShaderLabStore(defaults: scratchDefaults())

        #expect(store.values(for: shader) == shader.defaultValues)
    }

    /// A stored array whose length no longer matches the shader's slots was dialled against a
    /// different signature — reading it positionally would assign old values to the wrong
    /// knobs, which is worse than losing the tuning.
    @Test
    func store_discardsValuesWhoseLengthNoLongerMatches() throws {
        let suite = scratchDefaults()
        let shader = try #require(ShaderLabCatalog.shader(id: "bcsAurora"))

        let first = ShaderLabStore(defaults: suite)
        first.state.values["bcsAurora"] = [1, 2]  // bcsAurora has four slots

        let second = ShaderLabStore(defaults: suite)

        #expect(second.values(for: shader) == shader.defaultValues)
    }

    /// RESET removes the entry rather than writing a copy of today's defaults, so a later
    /// refresh of the pack's tuning reaches shaders that were only ever reset.
    @Test
    func store_resetRemovesTheEntry() throws {
        let store = ShaderLabStore(defaults: scratchDefaults())
        let shader = try #require(ShaderLabCatalog.shader(id: "bcsMelt"))

        store.setValue(99, atSlot: 0, for: shader)
        #expect(store.state.values["bcsMelt"] != nil)

        store.reset(shader)

        #expect(store.state.values["bcsMelt"] == nil)
        #expect(store.values(for: shader) == shader.defaultValues)
    }

    /// A persisted selection whose shader left the catalog falls back to the first shader —
    /// first-in-catalog beats crashing on a stale name.
    @Test
    func store_staleSelectionFallsBackToFirstShader() {
        let store = ShaderLabStore(defaults: scratchDefaults())
        store.state.selectedID = "bcsRemovedInARefresh"

        #expect(store.selectedShader.id == ShaderLabCatalog.shaders[0].id)
    }
}
