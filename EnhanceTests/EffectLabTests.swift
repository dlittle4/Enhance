import Testing
import Foundation
import CoreImage
import UIKit
@testable import Enhance

/// Guards the parts of EFFECTS LAB a preview cannot show you: that a window's arithmetic puts
/// the editor's knob where the effect's default is, that the lab's on/off answer collapses to
/// the code's `retired` sets when untouched, that a dialled-in window survives relaunch, and
/// that the shared thumbnail renderer still produces the cards the editor always produced.
struct EffectLabTests {

    private func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "EffectLabTests-\(UUID().uuidString)")!
    }

    // MARK: - ParameterWindow

    @Test
    func window_normalized_enforcesInvariants() {
        // MIN dragged over MAX pushes MAX rather than inverting.
        let pushed = ParameterWindow(min: 0.8, max: 0.5, defaultValue: 0.6).normalized()
        #expect(pushed.min == 0.8)
        #expect(pushed.max == 0.8 + ParameterWindow.minimumSpan)
        #expect(pushed.defaultValue == 0.8)

        // MIN at the top: both ends back off to keep one step of span.
        let top = ParameterWindow(min: 1, max: 1, defaultValue: 1).normalized()
        #expect(top.max == 1)
        #expect(top.min == 1 - ParameterWindow.minimumSpan)

        // Default clamps into the window; junk clamps into 0…1.
        let clamped = ParameterWindow(min: 0.2, max: 0.6, defaultValue: 0.9).normalized()
        #expect(clamped.defaultValue == 0.6)
        let junk = ParameterWindow(min: -3, max: .nan, defaultValue: .infinity).normalized()
        #expect(junk.min == 0)
        #expect(junk.max == ParameterWindow.minimumSpan)
        #expect(junk.defaultValue == 0)
    }

    /// The graduated tables are not empty any more, so "no window" is spelled out rather than
    /// borrowed from `.identity`.
    private static let bare = EffectLabLookup(windows: [:], thumbnails: [:], enabledOverrides: [:])

    @Test
    func window_remap_isIdentityWithoutAWindow() {
        let lookup = Self.bare
        for u in stride(from: 0.0, through: 1.0, by: 0.25) {
            #expect(lookup.remap(u, paramID: EffectParameter.intensityID, for: VisualEffectType.halftone) == u)
        }
        #expect(lookup.initialSliderValue(EffectParameter.backgroundOnlyID, for: VisualEffectType.halftone, declared: 0) == 0)
    }

    @Test
    func window_remap_mapsEndsAndDefault() {
        let window = ParameterWindow(min: 0.1, max: 0.8, defaultValue: 0.45)
        #expect(window.remap(0) == 0.1)
        #expect(window.remap(1) == 0.8)
        #expect(abs(window.remap(window.initialSliderValue) - 0.45) < 1e-9)
        #expect(window.remap(2) == 0.8, "u is clamped before mapping")
    }

    // MARK: - EffectLabLookup

    @Test
    func lookup_resolvedSliderValue_nilStoredReadsTheDefault() {
        let key = EffectParameter.key(EffectParameter.intensityID, for: VisualEffectType.halftone)
        let lookup = EffectLabLookup(
            windows: [key: ParameterWindow(min: 0.1, max: 0.8, defaultValue: 0.45)],
            thumbnails: [:], enabledOverrides: [:])

        // Untouched knob → the window's own default, not the middle of the window.
        #expect(lookup.resolvedSliderValue(stored: nil, paramID: EffectParameter.intensityID,
                                           for: VisualEffectType.halftone) == 0.45)
        // A knob the user moved → remapped.
        #expect(lookup.resolvedSliderValue(stored: 1, paramID: EffectParameter.intensityID,
                                           for: VisualEffectType.halftone) == 0.8)
        // No window → the declared default, so a toggle stored as nil still reads as off.
        #expect(lookup.resolvedSliderValue(stored: nil, paramID: EffectParameter.backgroundOnlyID,
                                           for: VisualEffectType.halftone, declared: 0) == 0)
        // The other FISHEYE is untouched by HALFTONE's window.
        #expect(lookup.resolvedSliderValue(stored: nil, paramID: EffectParameter.intensityID,
                                           for: FaceFilterType.fisheye) == 0.5)
    }

    @Test
    func lookup_enabledDefaultsMirrorRetired() {
        let store = EffectLabStore(defaults: scratchDefaults(), tables: .empty)
        #expect(store.lookup.enabledVisualEffects == VisualEffectType.selectable)
        #expect(store.lookup.enabledFaceFilters == FaceFilterType.selectable)
        #expect(store.isEnabled(VisualEffectType.caustic) == false)

        store.setEnabled(true, for: VisualEffectType.caustic)
        #expect(store.lookup.enabledVisualEffects == VisualEffectType.allCases.filter { !$0.isRetired || $0 == .caustic },
                "a re-enabled effect takes its declaration-order slot")

        store.setEnabled(false, for: VisualEffectType.halftone)
        #expect(!store.lookup.enabledVisualEffects.contains(.halftone))
        #expect(store.enabledCount(visual: true) == (VisualEffectType.selectable.count, VisualEffectType.allCases.count))

        // Writing the code default removes the override rather than pinning a copy.
        store.setEnabled(false, for: VisualEffectType.caustic)
        store.setEnabled(true, for: VisualEffectType.halftone)
        #expect(store.state.entries.isEmpty)
    }

    // MARK: - EffectLabStore

    @Test
    func store_roundTripsWindowsThumbnailsAndEnabled() {
        let suite = scratchDefaults()
        let first = EffectLabStore(defaults: suite, tables: .empty)
        first.setWindow(ParameterWindow(min: 0.1, max: 0.8, defaultValue: 0.45),
                        EffectParameter.intensityID, for: VisualEffectType.halftone)
        first.setThumbnailValue(0.85, EffectParameter.intensityID, for: VisualEffectType.halftone)
        first.setThumbnailProgress(0.35, for: VisualEffectType.pixelate)
        first.setEnabled(false, for: FaceFilterType.squeeze)
        first.state.selectedFace = FaceFilterType.bigHead.rawValue

        let second = EffectLabStore(defaults: suite, tables: .empty)
        #expect(second.state == first.state)
        #expect(second.window(EffectParameter.intensityID, for: VisualEffectType.halftone)
                == ParameterWindow(min: 0.1, max: 0.8, defaultValue: 0.45))
        #expect(second.thumbnail(for: VisualEffectType.halftone).values[EffectParameter.intensityID] == 0.85)
        #expect(second.thumbnail(for: VisualEffectType.pixelate).progress == 0.35)
        #expect(second.isEnabled(FaceFilterType.squeeze) == false)
        #expect(!second.lookup.enabledFaceFilters.contains(.squeeze))
        #expect(second.state.selectedFace == FaceFilterType.bigHead.rawValue)
    }

    @Test
    func store_identityWindowIsNotStored() {
        let store = EffectLabStore(defaults: scratchDefaults(), tables: .empty)
        store.setWindow(ParameterWindow(min: 0.1, max: 1, defaultValue: 0.5),
                        EffectParameter.sizeID, for: VisualEffectType.fisheye)
        #expect(store.state.entries.count == 1)
        store.setWindow(.identity, EffectParameter.sizeID, for: VisualEffectType.fisheye)
        #expect(store.state.entries.isEmpty, "back to identity reads as untouched")
    }

    @Test
    func store_neverWindowsAToggle() {
        let store = EffectLabStore(defaults: scratchDefaults(), tables: .empty)
        store.setWindow(ParameterWindow(min: 0.2, max: 0.9, defaultValue: 0.5),
                        EffectParameter.backgroundOnlyID, for: VisualEffectType.halftone)
        #expect(store.state.entries.isEmpty)
        #expect(store.lookup.windows.isEmpty)
    }

    @Test
    func store_resetEffectRemovesTheEntry() {
        let store = EffectLabStore(defaults: scratchDefaults(), tables: .empty)
        store.setEnabled(false, for: VisualEffectType.halftone)
        store.setWindow(ParameterWindow(min: 0.3), EffectParameter.intensityID, for: VisualEffectType.halftone)
        store.setEnabled(false, for: VisualEffectType.dither)
        store.resetEffect(VisualEffectType.halftone)
        #expect(store.state.entries.keys.sorted() == [EffectParameter.effectKey(for: VisualEffectType.dither)])
        #expect(store.isEnabled(VisualEffectType.halftone))
    }

    @Test
    func store_resetAllClearsTheKey() {
        let suite = scratchDefaults()
        let store = EffectLabStore(defaults: suite, tables: .empty)
        store.setEnabled(false, for: VisualEffectType.halftone)
        #expect(suite.data(forKey: EffectLabStore.storageKey) != nil)
        store.resetAll()
        #expect(suite.data(forKey: EffectLabStore.storageKey) == nil)
        #expect(store.lookup == EffectLabLookup(windows: [:], thumbnails: [:], enabledOverrides: [:]))
    }

    @Test
    func store_decodesASparseBlob() {
        let suite = scratchDefaults()
        let blob = #"{"entries":{"visual|HALFTONE":{"windows":{"intensity":{"min":0.2}}},"visual|GHOST":{"enabled":false}}}"#
        suite.set(Data(blob.utf8), forKey: EffectLabStore.storageKey)

        let store = EffectLabStore(defaults: suite, tables: .empty)
        let window = store.window(EffectParameter.intensityID, for: VisualEffectType.halftone)
        #expect(window.min == 0.2)
        #expect(window.max == 1)
        #expect(window.defaultValue == 0.5, "a missing default lands on identity's and is inside the window")
        #expect(store.state.family == "IMAGE")
        #expect(store.state.entries["visual|GHOST"] != nil, "unknown effect keys are kept, not dropped")
        #expect(store.lookup.enabledVisualEffects == VisualEffectType.selectable,
                "an unknown key changes nothing the editor sees")
    }

    @Test
    func store_decodesAnEmptyObject() {
        let suite = scratchDefaults()
        suite.set(Data("{}".utf8), forKey: EffectLabStore.storageKey)
        let store = EffectLabStore(defaults: suite, tables: .empty)
        #expect(store.state == EffectLabStore.State())
        #expect(store.lookup == EffectLabLookup(windows: [:], thumbnails: [:], enabledOverrides: [:]))
    }

    // MARK: - Snippet

    @Test
    func snippet_emitsTheFourBlocks() {
        let store = EffectLabStore(defaults: scratchDefaults(), tables: .empty)
        store.setEnabled(false, for: VisualEffectType.heatHaze)
        store.setEnabled(false, for: FaceFilterType.squeeze)
        store.setWindow(ParameterWindow(min: 0.1, max: 0.8, defaultValue: 0.45),
                        EffectParameter.intensityID, for: VisualEffectType.halftone)
        store.setThumbnailValue(0.85, EffectParameter.intensityID, for: VisualEffectType.halftone)
        store.setThumbnailValue(0.3, EffectParameter.sizeID, for: VisualEffectType.halftone)
        store.setThumbnailProgress(0.35, for: VisualEffectType.pixelate)

        let expected = """
        // Copied from EFFECTS LAB. Paste each block over the declaration it names.

        // VisualEffectType.swift — replace `retired`:
        static let retired: Set<VisualEffectType> = [.heatHaze, .caustic, .stretch, .monotone, .duotone, .bloom, .inversion, .vintageGrain, .popArt]

        // FaceFilterType.swift — replace `retired`:
        static let retired: Set<FaceFilterType> = [.squeeze, .fadeToBW]

        // EffectParameterWindows.swift — replace `EffectTuningTables.windows`:
        static let windows: [String: ParameterWindow] = [
            "visual|HALFTONE|intensity": ParameterWindow(min: 0.10, max: 0.80, defaultValue: 0.45),
        ]

        // EffectParameterWindows.swift — replace `EffectTuningTables.thumbnailPresets`:
        static let thumbnailPresets: [String: ThumbnailPreset] = [
            "visual|HALFTONE": ThumbnailPreset(values: ["intensity": 0.85, "size": 0.30], progress: nil),
            "visual|PIXELATE": ThumbnailPreset(values: [:], progress: 0.35),
        ]
        """
        #expect(store.swiftSnippet == expected)
    }

    /// `String(describing:)` on a String-backed enum prints the case name, not the raw value.
    /// The snippet leans on that; if either enum ever adopts `CustomStringConvertible` this is
    /// the test that says so.
    @Test
    func snippet_retiredSetUsesCaseNames() {
        let store = EffectLabStore(defaults: scratchDefaults(), tables: .empty)
        store.setEnabled(false, for: VisualEffectType.lensDistortion)
        store.setEnabled(false, for: FaceFilterType.lensDistortion)
        #expect(store.swiftSnippet.contains("Set<VisualEffectType> = [.lensDistortion, .caustic, .stretch, .monotone"))
        #expect(store.swiftSnippet.contains("Set<FaceFilterType> = [.fadeToBW, .lensDistortion]"))
        #expect(!store.swiftSnippet.contains("\"LENS\""))
    }

    @Test
    func snippet_emptyTablesReadAsEmptyLiterals() {
        let store = EffectLabStore(defaults: scratchDefaults(), tables: .empty)
        #expect(store.swiftSnippet.contains("static let windows: [String: ParameterWindow] = [:]"))
        #expect(store.swiftSnippet.contains("static let thumbnailPresets: [String: ThumbnailPreset] = [:]"))
        #expect(store.swiftSnippet.contains("Set<FaceFilterType> = [.fadeToBW]"))
    }

    // MARK: - Thumbnail renderer

    private func gradientImage(_ size: Int = 120) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { ctx in
            let colors = [UIColor.systemOrange.cgColor, UIColor.systemTeal.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero,
                                             end: CGPoint(x: size, y: size), options: [])
            UIColor.white.setFill()
            ctx.fill(CGRect(x: size / 3, y: size / 3, width: size / 3, height: size / 3))
        }
        return image.cgImage!
    }

    private func bytes(_ image: UIImage?) -> Data? {
        image?.pngData()
    }

    /// With no lab state the renderer must produce exactly what `EditorViewModel` used to build
    /// inline: intensity 0.7, everything else 0.5, purple tint, frame 3, `previewProgress`.
    @Test
    func thumbnailRenderer_matchesTheHardcodedDefaults() {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let renderer = EffectThumbnailRenderer(context: context)
        let source = gradientImage()

        for type in [VisualEffectType.chromaShift, .halftone, .pixelate] {
            let options = EffectOptions(size: 0.5, tintColor: .purple, gradientStops: .default)
            let legacy = type.effect(intensity: 0.7, options: options)
                .apply(to: CIImage(cgImage: source), progress: type.previewProgress, frameIndex: 3)
            let legacyImage = context.createCGImage(legacy, from: legacy.extent).map(UIImage.init(cgImage:))

            let rendered = renderer.render(type, source: source, lab: Self.bare)
            #expect(bytes(rendered) == bytes(legacyImage), "\(type.rawValue) drifted from the legacy card")
        }
    }

    @Test
    func thumbnailRenderer_appliesThePresetThroughTheWindow() {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let renderer = EffectThumbnailRenderer(context: context)
        let source = gradientImage()
        let type = VisualEffectType.halftone

        let identity = renderer.render(type, source: source, lab: Self.bare)
        let again = renderer.render(type, source: source, lab: Self.bare)
        #expect(bytes(identity) == bytes(again), "rendering is deterministic")

        // A window that pins intensity near zero must change the card.
        let key = EffectParameter.key(EffectParameter.intensityID, for: type)
        let pinned = EffectLabLookup(
            windows: [key: ParameterWindow(min: 0, max: ParameterWindow.minimumSpan, defaultValue: 0)],
            thumbnails: [:], enabledOverrides: [:])
        let windowed = renderer.render(type, source: source, lab: pinned)
        #expect(bytes(windowed) != bytes(identity))

        // And the preset value 0.7 through that window equals a direct build at the remapped value.
        let direct = type.effect(intensity: ParameterWindow.minimumSpan * 0.7,
                                 options: EffectOptions(size: 0.5, tintColor: .purple, gradientStops: .default))
            .apply(to: CIImage(cgImage: source), progress: type.previewProgress, frameIndex: 3)
        let directImage = context.createCGImage(direct, from: direct.extent).map(UIImage.init(cgImage:))
        #expect(bytes(windowed) == bytes(directImage))
    }

    // MARK: - EditorViewModel

    @Test
    func viewModel_resolvesThroughTheInjectedLookup() {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let key = EffectParameter.key(EffectParameter.intensityID, for: VisualEffectType.halftone)
        let lookup = EffectLabLookup(
            windows: [key: ParameterWindow(min: 0.1, max: 0.8, defaultValue: 0.45)],
            thumbnails: [:],
            enabledOverrides: [EffectParameter.effectKey(for: VisualEffectType.halftone): false])
        let vm = EditorViewModel(content: .newImage(img), effectLab: lookup)

        // Untouched: the window's default. Moved to the top: the window's max.
        #expect(vm.resolvedValue(EffectParameter.intensityID, for: VisualEffectType.halftone) == 0.45)
        vm.setValue(1, EffectParameter.intensityID, for: VisualEffectType.halftone)
        #expect(vm.resolvedValue(EffectParameter.intensityID, for: VisualEffectType.halftone) == 0.8)
        // Untouched and unwindowed: today's 0.5.
        #expect(vm.resolvedValue(EffectParameter.sizeID, for: VisualEffectType.halftone) == 0.5)
        // The knob the editor opens with lands on the window default.
        #expect(abs(vm.effectLab.initialSliderValue(EffectParameter.intensityID, for: VisualEffectType.halftone, declared: 0.5) - 0.5) < 1e-9)
        // And the carousel the editor builds omits the switched-off effect.
        #expect(!vm.effectLab.enabledVisualEffects.contains(.halftone))
        #expect(vm.effectLab.enabledVisualEffects.contains(.dither))
    }

    @Test
    func viewModel_defaultsToIdentityWhenNothingIsDialledIn() {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let vm = EditorViewModel(content: .newImage(img), effectLab: .identity)
        #expect(vm.effectLab.enabledVisualEffects == VisualEffectType.selectable)
        #expect(vm.effectLab.enabledFaceFilters == FaceFilterType.selectable)
    }

    // MARK: - Declarations

    /// Retired effects now carry BACKGROUND ONLY too — the lab can put them back in front of
    /// the user, and they must arrive with the same modifier every other card has.
    @Test
    func retiredVisualEffects_alsoEndWithBackgroundOnly() {
        for type in VisualEffectType.retired {
            #expect(type.parameters.last?.id == EffectParameter.backgroundOnlyID, "\(type.rawValue)")
        }
        #expect(VisualEffectType.subjectEcho.parameters.last?.id != EffectParameter.backgroundOnlyID)
    }

    @Test
    func faceFilterType_selectableOmitsTheRetired() {
        #expect(FaceFilterType.retired == [.fadeToBW])
        #expect(FaceFilterType.selectable == FaceFilterType.allCases.filter { !$0.isRetired })
    }

    @Test
    func effectKey_prefixesEveryParameterKey() {
        #expect(EffectParameter.effectKey(for: VisualEffectType.halftone) == "visual|HALFTONE")
        #expect(EffectParameter.effectKey(for: FaceFilterType.fisheye) == "face|FISHEYE")
        #expect(EffectParameter.key("intensity", for: VisualEffectType.fisheye) == "visual|FISHEYE|intensity")
    }
}
