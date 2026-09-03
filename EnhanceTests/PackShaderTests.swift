import Testing
import CoreImage
import UIKit
@testable import Enhance

/// The SHADER LAB graduates that ship as Core Image kernels (PULSE is HEART BEAT on the ZOOM tab). What a preview cannot show: that every
/// kernel actually loaded from `ShaderPack.ci.metallib` (a bad signature yields a silent nil and
/// an effect that returns its input), that each one changes the frame, that zero intensity is a
/// no-op for the looks whose INTENSITY is an amount, and that the frame's extent survives.
struct PackShaderTests {

    private let ctx = CIContext(options: [.useSoftwareRenderer: true])

    static let pack: [VisualEffectType] = [
        .thermal, .chromaticSplit, .datamosh, .heatShimmer, .liveRipple, .melt,
        .neonEdge, .pixelateStorm, .shockwave, .solarize, .wavePool
    ]

    /// A gradient with a hard-edged square, so edge detection, displacement and palettes all
    /// have something to bite on.
    private func fixture(_ side: Int = 96) -> CIImage {
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let colors = [UIColor.systemOrange.cgColor, UIColor.systemTeal.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            UIColor.white.setFill()
            ctx.fill(CGRect(x: side / 3, y: side / 3, width: side / 3, height: side / 3))
        }
        return CIImage(cgImage: image.cgImage!)
    }

    private func pixels(_ image: CIImage) -> [UInt8] {
        let w = Int(image.extent.width), h = Int(image.extent.height)
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        ctx.render(image, toBitmap: &buf, rowBytes: w * 4, bounds: image.extent,
                   format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return buf
    }

    @Test("every kernel loads and changes the frame at full strength")
    func pack_everyKernelRenders() {
        let input = fixture()
        let before = pixels(input)
        for type in Self.pack {
            let effect = type.effect(intensity: 1.0, options: EffectOptions(size: 0.5))
            #expect(effect is PackShaderEffect, "\(type.rawValue) should build a pack effect")
            let output = effect.apply(to: input, progress: 1.0, frameIndex: 3)
            #expect(output.extent == input.extent, "\(type.rawValue) changed the extent")
            #expect(pixels(output) != before, "\(type.rawValue) returned its input — kernel not loaded?")
        }
    }

    /// INTENSITY is an amount for these, so zero must leave the photo alone (up to the sRGB
    /// round-trip, which is why the tolerance is a couple of levels, not byte equality).
    ///
    /// THERMAL is deliberately absent: its INTENSITY is the pack's own `intensity`, the palette
    /// mix, and the heat shimmer is a separate control that keeps displacing at zero — the same
    /// split the pack ships, kept rather than coupled so the lab's tuned look survives.
    /// PIXEL STORM and SHOCKWAVE read INTENSITY as block size and ring strength, not amounts.
    @Test("zero intensity is a no-op for the amount-driven looks")
    func pack_zeroIntensityIsANoOp() {
        let input = fixture()
        let before = pixels(input)
        let amountDriven: [VisualEffectType] = [
            .chromaticSplit, .datamosh, .heatShimmer, .liveRipple, .melt, .neonEdge, .solarize, .wavePool
        ]
        for type in amountDriven {
            let output = type.effect(intensity: 0, options: EffectOptions(size: 0.5))
                .apply(to: input, progress: 1.0, frameIndex: 3)
            let worst = zip(pixels(output), before).map { abs(Int($0) - Int($1)) }.max() ?? 0
            #expect(worst <= 3, "\(type.rawValue) at zero intensity differs by \(worst)/255")
        }
    }

    @Test("the pack's controls are live")
    func pack_secondControlIsLive() {
        let input = fixture()
        for type in Self.pack {
            let low = type.effect(intensity: 1.0, options: EffectOptions(size: 0.05)).apply(to: input, progress: 1.0, frameIndex: 3)
            let high = type.effect(intensity: 1.0, options: EffectOptions(size: 0.95)).apply(to: input, progress: 1.0, frameIndex: 3)
            #expect(pixels(low) != pixels(high), "\(type.rawValue)'s second control does nothing")
        }
    }

    /// The virtual frame: the same look on a photo twice the size should displace twice as many
    /// pixels, so a downscale of the large result matches the small one closely. Pinned loosely
    /// (mean difference), because resampling and the pack's own per-pixel noise both add texture.
    @Test("pixel constants scale with the frame")
    func pack_virtualFrameScalesWithTheImage() {
        let small = fixture(96)
        let large = fixture(192)
        let effect = VisualEffectType.melt.effect(intensity: 1.0, options: EffectOptions(size: 0.5))

        let smallOut = pixels(effect.apply(to: small, progress: 1.0, frameIndex: 3))
        let largeOut = effect.apply(to: large, progress: 1.0, frameIndex: 3)
            .transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        let downscaled = pixels(largeOut.cropped(to: small.extent))

        let mean = zip(smallOut, downscaled).map { abs(Int($0) - Int($1)) }.reduce(0, +) / max(1, smallOut.count)
        #expect(mean < 24, "large-frame render does not match the small one after downscaling (mean \(mean))")
    }

    @Test("all eleven IMAGE looks are selectable and declare INTENSITY first")
    func pack_declarations() {
        for type in Self.pack {
            #expect(!type.isRetired)
            #expect(type.parameters.first?.id == EffectParameter.intensityID)
            #expect(type.parameters.last?.id == EffectParameter.backgroundOnlyID)
            #expect(type.colorPickerKind == nil)
        }
        #expect(VisualEffectType.neonEdge.parameters.count == 6)
        #expect(VisualEffectType.melt.parameters.count == 5)
    }

    @Test("the tuned defaults open every pack knob where the lab left it")
    func pack_tunedDefaultsAreInTheTables() {
        for type in Self.pack {
            let prefix = EffectParameter.effectKey(for: type) + "|"
            // A tuned value that sits exactly at the midpoint (CHROMATIC SPLIT's spread) is the
            // identity window and is rightly absent; every look still carries at least one.
            #expect(EffectTuningTables.windows.keys.contains { $0.hasPrefix(prefix) },
                    "\(type.rawValue) has no tuned windows")
            let preset = EffectTuningTables.thumbnailPresets[EffectParameter.effectKey(for: type)]
            #expect(preset?.values[EffectParameter.intensityID] != nil, "\(type.rawValue) has no thumbnail preset")
        }
    }

    // MARK: - HEART BEAT

    /// The twelfth star rides the ZOOM tab: built by the pack factory, kept off the IMAGE
    /// carousel, and appended to the effect list only while the HEART BEAT zoom is selected.
    @Test("HEART BEAT is the pulse shader hosted on the ZOOM tab")
    func heartBeat_isThePulseShaderOnTheZoomTab() {
        #expect(VisualEffectType.pulse.rawValue == "HEART BEAT")
        #expect(VisualEffectType.pulse.isRetired, "must stay off the IMAGE carousel")
        #expect(VisualEffectType.pulse.effect(intensity: 1) is PackShaderEffect)
        #expect(VisualEffectType.pulse.parameters.last?.id != EffectParameter.backgroundOnlyID)
        #expect(AnimatorType.heartBeat.animator is StaticAnimator)

        let input = fixture()
        let output = VisualEffectType.pulse.effect(intensity: 1.0, options: EffectOptions(size: 0.5))
            .apply(to: input, progress: 0.9, frameIndex: 3)
        #expect(output.extent == input.extent)
        #expect(pixels(output) != pixels(input))

        let img = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { ctx in
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let vm = EditorViewModel(content: .newImage(img), effectLab: .identity)
        vm.selectedAnimatorType = .heartBeat
        #expect(vm.activeVisualEffectList.count == 1)
        #expect(vm.activeVisualEffectList.first is PackShaderEffect)
        vm.selectedVisualEffect = .halftone
        #expect(vm.activeVisualEffectList.count == 2, "the beat rides after the IMAGE selection")
        #expect(vm.activeVisualEffectList.last is PackShaderEffect)
        vm.selectedAnimatorType = .pulse
        #expect(vm.activeVisualEffectList.count == 1)
    }
}
