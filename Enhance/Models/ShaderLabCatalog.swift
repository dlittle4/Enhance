import SwiftUI

/// One knob on a vendored shader, as SHADER LAB drives it.
///
/// Two kinds. A `value` is one `float` argument with the range and tuned default that upstream
/// documents — the lab's sliders bind to exactly that range, so the sweet spots the author found
/// are the span you scrub. A `point` is a `float2` interaction argument (`touchPos`), stored as
/// two 0…1 slots and passed to Metal premultiplied by the view's pixel size, which is the
/// convention `ShaderPackEffects.swift` uses for `UnitPoint` parameters.
struct ShaderLabParameter {
    let label: String
    let range: ClosedRange<Double>
    let defaultValue: Double
    let isPoint: Bool

    static func value(_ label: String, _ range: ClosedRange<Double>, default defaultValue: Double) -> ShaderLabParameter {
        ShaderLabParameter(label: label, range: range, defaultValue: defaultValue, isPoint: false)
    }

    /// Occupies two stored slots (x, then y), both 0…1, both defaulting to centre.
    static func point(_ label: String) -> ShaderLabParameter {
        ShaderLabParameter(label: label, range: 0...1, defaultValue: 0.5, isPoint: true)
    }

    /// How many entries this parameter contributes to a shader's flat value array.
    var slotCount: Int { isPoint ? 2 : 1 }
}

/// One vendored shader, described precisely enough for the lab to call it without a typed
/// wrapper: the `[[ stitchable ]]` function's name, its knobs in declaration order, and — for
/// animated shaders — where `time` sits among the arguments.
///
/// `timeSlot` earns its place: forty of the forty-one animated signatures take `time` right
/// after `size`, but `bcs_chromaticSplit` takes it fourth, and a hardcoded "size, time, params"
/// assembly would silently feed that shader its spread as a clock. The slot is the argument's
/// index with `size` at 0 and `time` itself excluded — the insertion point, not the final layout.
struct ShaderLabShader: Identifiable {
    let id: String
    let title: String
    let metalName: String
    var timeSlot: Int? = nil
    let params: [ShaderLabParameter]

    var animated: Bool { timeSlot != nil }

    /// The tuned defaults, flattened to the value array the store persists.
    var defaultValues: [Double] {
        params.flatMap { $0.isPoint ? [0.5, 0.5] : [$0.defaultValue] }
    }

    /// Assembles the shader for one frame. `values` is the flat array (`defaultValues` order);
    /// `time` is ignored for static shaders.
    func shader(size: CGSize, time: Float, values: [Double]) -> Shader {
        var args: [Shader.Argument] = [.float2(size)]
        var slot = 0
        for param in params {
            if param.isPoint {
                let x = values.indices.contains(slot) ? values[slot] : 0.5
                let y = values.indices.contains(slot + 1) ? values[slot + 1] : 0.5
                args.append(.float2(CGSize(width: size.width * x, height: size.height * y)))
                slot += 2
            } else {
                let v = values.indices.contains(slot) ? values[slot] : param.defaultValue
                args.append(.float(v))
                slot += 1
            }
        }
        if let timeSlot {
            args.insert(.float(time), at: timeSlot)
        }
        return Shader(function: ShaderFunction(library: .default, name: metalName), arguments: args)
    }

    /// The line COPY hands back — a call on the typed wrapper in `ShaderPackEffects.swift`,
    /// so the graduation path is paste-and-done.
    func swiftSnippet(values: [Double]) -> String {
        var parts: [String] = []
        var slot = 0
        for param in params {
            if param.isPoint {
                let x = values.indices.contains(slot) ? values[slot] : 0.5
                let y = values.indices.contains(slot + 1) ? values[slot + 1] : 0.5
                parts.append("\(param.label): UnitPoint(x: \(Self.literal(x)), y: \(Self.literal(y)))")
                slot += 2
            } else {
                let v = values.indices.contains(slot) ? values[slot] : param.defaultValue
                parts.append("\(param.label): \(Self.literal(v))")
                slot += 1
            }
        }
        return ".\(id)(\(parts.joined(separator: ", ")))"
    }

    /// A minimal literal — `12`, not `12.0`; `0.62`, not `0.6200000047`.
    private static func literal(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1_000_000 {
            return String(Int(v))
        }
        return String(format: "%.2f", v)
    }
}

/// Every shader in the vendored pack, in `Docs/parameters.json` order (alphabetical).
///
/// **Generated, not curated.** Produced from upstream's `Docs/parameters.json` cross-checked
/// against the `.metal` signatures; the six ranges upstream leaves undocumented
/// (`bcsEtherealAura`'s five, `touchAge`) bracket the tuned defaults instead, and one documented
/// range is widened where upstream's own default overdrives it (see `bcsNeonEdge`). If the
/// vendored pack is ever refreshed, regenerate rather than hand-edit — a transposed argument
/// here renders as garbage with no error anywhere. `ShaderLabTests` pins the invariants.
enum ShaderLabCatalog {
    static let shaders: [ShaderLabShader] = [
        ShaderLabShader(
            id: "bcsAurora", title: "AURORA", metalName: "bcs_aurora", timeSlot: 1,
            params: [
                .value("intensity", 0...1, default: 0.5),
                .value("bands", 1...8, default: 4.5),
                .value("speed", 0.3...3, default: 1.65),
                .value("colorShift", 0...1, default: 0.5)
            ]),
        ShaderLabShader(
            id: "bcsBlackHole", title: "BLACK HOLE", metalName: "bcs_blackHole", timeSlot: 1,
            params: [
                .value("mass", 0.05...0.5, default: 0.28),
                .value("spin", 0...5, default: 2.5),
                .value("distortion", 10...200, default: 105),
                .value("ringBrightness", 0...2, default: 1)
            ]),
        ShaderLabShader(
            id: "bcsChromaticSplit", title: "CHROMATIC SPLIT", metalName: "bcs_chromaticSplit", timeSlot: 4,
            params: [
                .value("spread", 0...30, default: 8),
                .value("angle", 0...6.28, default: 0),
                .value("edgeOnly", 0...1, default: 0.5),
                .value("animate", 0...1, default: 0.5)
            ]),
        ShaderLabShader(
            id: "bcsDatamosh", title: "DATAMOSH", metalName: "bcs_datamosh", timeSlot: 1,
            params: [
                .value("blockCorruption", 0...1, default: 0.4),
                .value("smearAmount", 0...60, default: 30),
                .value("colorBleed", 0...1, default: 0.5),
                .value("glitchRate", 0.5...5, default: 2)
            ]),
        ShaderLabShader(
            id: "bcsDisintegrate", title: "DISINTEGRATE", metalName: "bcs_disintegrate", timeSlot: 1,
            params: [
                .value("threshold", 0...1, default: 0),
                .value("edgeWidth", 0.05...0.3, default: 0.12),
                .value("driftAmount", 0...50, default: 25),
                .value("direction", 0...6.28, default: 1)
            ]),
        ShaderLabShader(
            id: "bcsDuochrome", title: "DUOCHROME", metalName: "bcs_duochrome", timeSlot: 1,
            params: [
                .value("intensity", 0...1, default: 0.5),
                .value("hue1", 0...1, default: 0.5),
                .value("hue2", 0...1, default: 0.5),
                .value("contrast", 0.5...2, default: 1.25)
            ]),
        ShaderLabShader(
            id: "bcsEcho", title: "ECHO · GHOST", metalName: "bcs_echo", timeSlot: 1,
            params: [
                .value("echoCount", 2...8, default: 4),
                .value("spread", 5...50, default: 20),
                .value("direction", 0...6.28, default: 0.785),
                .value("fade", 0.3...0.9, default: 0.6)
            ]),
        ShaderLabShader(
            id: "bcsEmboss", title: "EMBOSS · RELIEF", metalName: "bcs_emboss",
            params: [
                .value("strength", 0...5, default: 2),
                .value("angle", 0...6.28, default: 0.785),
                .value("mixAmount", 0...1, default: 0.8)
            ]),
        ShaderLabShader(
            id: "bcsEtherealAura", title: "ETHEREAL AURA (V2)", metalName: "bcs_etherealAura", timeSlot: 1,
            params: [
                .value("auraWidth", 0.02...0.4, default: 0.12),
                .value("auraIntensity", 0...2, default: 1),
                .value("pulseSpeed", 0.3...3, default: 1.5),
                .value("distortion", 0...30, default: 8),
                .value("hueShift", 0...6.28, default: 3.5)
            ]),
        ShaderLabShader(
            id: "bcsFrosted", title: "FROSTED GLASS", metalName: "bcs_frosted",
            params: [
                .value("frostAmount", 0...1, default: 0.5),
                .value("grainSize", 1...20, default: 10),
                .value("clearRadius", 0...1, default: 0.5),
                .value("clearSoftness", 0...1, default: 0.5)
            ]),
        ShaderLabShader(
            id: "bcsGeometricWarp", title: "GEOMETRIC WARP", metalName: "bcs_geometricWarp", timeSlot: 1,
            params: [
                .value("spiralTight", 1...8, default: 3),
                .value("zoomRepeat", 0.3...2, default: 1),
                .value("rotation", 0...6.28, default: 0),
                .value("blend", 0...1, default: 0)
            ]),
        ShaderLabShader(
            id: "bcsGlitch", title: "GLITCH", metalName: "bcs_glitch", timeSlot: 1,
            params: [
                .value("intensity", 0...1, default: 0.5),
                .value("blockSize", 2...50, default: 15),
                .value("scanLines", 0...1, default: 0.4),
                .value("colorShift", 0...20, default: 8)
            ]),
        ShaderLabShader(
            id: "bcsGravityWells", title: "GRAVITY WELLS", metalName: "bcs_gravityWells", timeSlot: 1,
            params: [
                .value("wellStrength", 10...200, default: 80),
                .value("wellCount", 1...5, default: 3),
                .value("orbitSpeed", 0.1...3, default: 0.8),
                .value("warpFalloff", 0.5...5, default: 2)
            ]),
        ShaderLabShader(
            id: "bcsHeatShimmer", title: "HEAT SHIMMER", metalName: "bcs_heatShimmer", timeSlot: 1,
            params: [
                .value("amplitude", 0...20, default: 10),
                .value("frequency", 1...30, default: 16),
                .value("speed", 0.5...5, default: 2.75),
                .value("verticalBias", 0...1, default: 0.5)
            ]),
        ShaderLabShader(
            id: "bcsHolographic", title: "HOLOGRAPHIC · PRISMATIC", metalName: "bcs_holographic", timeSlot: 1,
            params: [
                .value("intensity", 0...1, default: 0.4),
                .value("scale", 1...20, default: 8),
                .value("speed", 0.1...3, default: 1),
                .value("angleOffset", 0...6.28, default: 0.785)
            ]),
        ShaderLabShader(
            id: "bcsInkBleed", title: "INK BLEED · DOMAIN WARP", metalName: "bcs_inkBleed", timeSlot: 1,
            params: [
                .value("warpStrength", 0...50, default: 15),
                .value("scale", 1...10, default: 4),
                .value("speed", 0.1...2, default: 0.5),
                .value("detail", 2...8, default: 5)
            ]),
        ShaderLabShader(
            id: "bcsKaleidoscope", title: "KALEIDOSCOPE", metalName: "bcs_kaleidoscope", timeSlot: 1,
            params: [
                .value("segments", 2...16, default: 9),
                .value("rotation", 0...6.28, default: 3.14),
                .value("zoom", 0.5...3, default: 1.75),
                .value("animateSpeed", 0...2, default: 1)
            ]),
        ShaderLabShader(
            id: "bcsLiquidChrome", title: "LIQUID CHROME", metalName: "bcs_liquidChrome", timeSlot: 1,
            params: [
                .value("distortion", 0...30, default: 15),
                .value("chromeIntensity", 0...1, default: 0.5),
                .value("flowSpeed", 0.1...3, default: 1.55),
                .value("reflectionScale", 1...10, default: 5.5)
            ]),
        ShaderLabShader(
            id: "bcsLiquidMirror", title: "LIQUID MIRROR", metalName: "bcs_liquidMirror", timeSlot: 1,
            params: [
                .value("mirrorAxis", 0.3...0.7, default: 0.55),
                .value("ripple", 2...30, default: 12),
                .value("speed", 0.5...3, default: 1.5),
                .value("depth", 0...1, default: 0.5)
            ]),
        ShaderLabShader(
            id: "bcsLiveRipple", title: "LIVE RIPPLE", metalName: "bcs_liveRipple", timeSlot: 1,
            params: [
                .value("amplitude", 0...30, default: 12),
                .value("frequency", 5...60, default: 25),
                .value("speed", 1...10, default: 4),
                .value("damping", 0.5...5, default: 2),
                .value("ringCount", 1...5, default: 3)
            ]),
        ShaderLabShader(
            id: "bcsMagneticField", title: "MAGNETIC FIELD", metalName: "bcs_magneticField", timeSlot: 1,
            params: [
                .value("fieldStrength", 5...80, default: 40),
                .value("lineCount", 3...20, default: 8),
                .value("fieldTurbulence", 0...1, default: 0.5),
                .value("polarity", 0...1, default: 0)
            ]),
        ShaderLabShader(
            id: "bcsMelt", title: "MELT", metalName: "bcs_melt", timeSlot: 1,
            params: [
                .value("meltAmount", 0...100, default: 40),
                .value("dripScale", 1...15, default: 6),
                .value("speed", 0.1...3, default: 1),
                .value("heat", 0...1, default: 0.3)
            ]),
        ShaderLabShader(
            id: "bcsMorphBreathe", title: "MORPH BREATHE", metalName: "bcs_morphBreathe", timeSlot: 1,
            params: [
                .value("breatheDepth", 5...50, default: 28),
                .value("breatheRate", 0.3...3, default: 1.65),
                .value("warpComplexity", 1...8, default: 4.5),
                .value("organic", 0...1, default: 0.5)
            ]),
        ShaderLabShader(
            id: "bcsNeonEdge", title: "NEON EDGE", metalName: "bcs_neonEdge", timeSlot: 1,
            params: [
                .value("edgeStrength", 1...10, default: 5.5),
                // Upstream documents 0…2 but ships a tuned default of 4 — the author overdrives
                // the glow on purpose. The range widens to keep that default on the slider.
                .value("glowAmount", 0...4, default: 4),
                .value("colorCycle", 0...3, default: 1),
                .value("mixOriginal", 0...1, default: 1)
            ]),
        ShaderLabShader(
            id: "bcsPixelateMosaic", title: "PIXELATE MOSAIC", metalName: "bcs_pixelateMosaic", timeSlot: 1,
            params: [
                .value("pixelSize", 4...60, default: 20),
                .value("bevel", 0...1, default: 0.6),
                .value("animateAssemble", 0...1, default: 0.5),
                .value("gap", 0...0.3, default: 0.05)
            ]),
        ShaderLabShader(
            id: "bcsPixelateStorm", title: "PIXELATE STORM", metalName: "bcs_pixelateStorm", timeSlot: 1,
            params: [
                .value("pixelSize", 2...40, default: 21),
                .value("stormAmount", 0...1, default: 0.5),
                .value("swirl", 0...3, default: 1.5),
                .value("pulse", 0...3, default: 1.5)
            ]),
        ShaderLabShader(
            id: "bcsPlasma", title: "PLASMA", metalName: "bcs_plasma", timeSlot: 1,
            params: [
                .value("intensity", 0...1, default: 0.5),
                .value("scale", 1...10, default: 5.5),
                .value("speed", 0.5...5, default: 2.75),
                .value("colorMode", 0...1, default: 0.5)
            ]),
        ShaderLabShader(
            id: "bcsPulse", title: "PULSE · HEARTBEAT", metalName: "bcs_pulse", timeSlot: 1,
            params: [
                .value("amplitude", 0...30, default: 15),
                .value("bpm", 30...180, default: 72),
                .value("sharpness", 1...10, default: 3),
                .value("glowIntensity", 0...1, default: 0.5)
            ]),
        ShaderLabShader(
            id: "bcsRefractLens", title: "REFRACT LENS (INTERACTIVE)", metalName: "bcs_refractLens",
            params: [
                .point("touchPos"),
                .value("lensRadius", 0.1...0.5, default: 0.3),
                .value("refraction", 1...3, default: 2),
                .value("aberration", 0...15, default: 5),
                .value("wobble", 0...1, default: 0.5)
            ]),
        ShaderLabShader(
            id: "bcsShatter", title: "SHATTER", metalName: "bcs_shatter", timeSlot: 1,
            params: [
                .value("shardCount", 3...30, default: 16),
                .value("explode", 0...1, default: 0.5),
                .value("rotationAmt", 0...3, default: 1.5),
                .value("edgeGlow", 0...2, default: 1)
            ]),
        ShaderLabShader(
            id: "bcsShatterGlass", title: "SHATTER GLASS", metalName: "bcs_shatterGlass", timeSlot: 1,
            params: [
                .value("crackDensity", 3...15, default: 8),
                .value("glassRefraction", 0...20, default: 10),
                .value("prismStrength", 0...1, default: 0.5),
                .value("shatterSpread", 0...1, default: 0)
            ]),
        ShaderLabShader(
            id: "bcsShockwave", title: "SHOCKWAVE", metalName: "bcs_shockwave", timeSlot: 1,
            params: [
                .value("waveSpeed", 50...500, default: 200),
                .value("ringWidth", 5...60, default: 30),
                .value("strength", 5...80, default: 40),
                .value("repeatRate", 0.5...5, default: 2)
            ]),
        ShaderLabShader(
            id: "bcsSmokeReveal", title: "SMOKE REVEAL", metalName: "bcs_smokeReveal", timeSlot: 1,
            params: [
                .value("smokeAmount", 0...1, default: 0.6),
                .value("smokeScale", 2...10, default: 5),
                .value("windSpeed", 0.5...3, default: 1.5),
                .value("smokeTurb", 0.5...3, default: 1.5)
            ]),
        ShaderLabShader(
            id: "bcsSolarize", title: "SOLARIZE", metalName: "bcs_solarize", timeSlot: 1,
            params: [
                .value("threshold", 0.2...0.8, default: 0.5),
                .value("curveIntensity", 0...3, default: 1.5),
                .value("colorSeparation", 0...1, default: 0.5),
                .value("animate", 0...1, default: 0.5)
            ]),
        ShaderLabShader(
            id: "bcsThermal", title: "THERMAL", metalName: "bcs_thermal", timeSlot: 1,
            params: [
                .value("intensity", 0...1, default: 0.8),
                .value("shimmer", 0...15, default: 5),
                .value("noiseSpeed", 0.5...3, default: 1.5),
                .value("paletteShift", 0...1, default: 0)
            ]),
        ShaderLabShader(
            id: "bcsTopographic", title: "TOPOGRAPHIC", metalName: "bcs_topographic", timeSlot: 1,
            params: [
                .value("lineCount", 5...40, default: 20),
                .value("lineWidth", 0.01...0.15, default: 0.05),
                .value("colorize", 0...1, default: 0.7),
                .value("animate", 0...1, default: 0.3)
            ]),
        ShaderLabShader(
            id: "bcsTouchRipple", title: "TOUCH RIPPLE", metalName: "bcs_touchRipple",
            params: [
                .point("touchPos"),
                .value("touchAge", 0...4, default: 1),
                .value("amplitude", 0...30, default: 15),
                .value("frequency", 5...40, default: 20),
                .value("speed", 50...500, default: 300),
                .value("decay", 0.5...4, default: 2)
            ]),
        ShaderLabShader(
            id: "bcsUnderwaterCaustics", title: "UNDERWATER CAUSTICS", metalName: "bcs_underwaterCaustics", timeSlot: 1,
            params: [
                .value("causticScale", 2...15, default: 6),
                .value("causticIntensity", 0...2, default: 1),
                .value("waterDistortion", 0...30, default: 12),
                .value("waterDepth", 0...1, default: 0.4)
            ]),
        ShaderLabShader(
            id: "bcsVortex", title: "VORTEX SPIRAL", metalName: "bcs_vortex", timeSlot: 1,
            params: [
                .value("twistAmount", 0...10, default: 3),
                .value("radius", 0.1...1, default: 0.5),
                .value("speed", 0.1...3, default: 0.5),
                .value("falloff", 0.5...5, default: 2)
            ]),
        ShaderLabShader(
            id: "bcsWavePool", title: "WAVE POOL", metalName: "bcs_wavePool", timeSlot: 1,
            params: [
                .value("amplitude", 0...25, default: 12),
                .value("wavelength", 5...40, default: 22),
                .value("speed", 0.5...5, default: 2.75),
                .value("complexity", 1...6, default: 3.5)
            ]),
        ShaderLabShader(
            id: "bcsWormhole", title: "WORMHOLE", metalName: "bcs_wormhole", timeSlot: 1,
            params: [
                .value("depth", 1...8, default: 4.5),
                .value("speed", 0.3...3, default: 1.65),
                .value("twist", 0...5, default: 2.5),
                .value("radius", 0.1...0.5, default: 0.3)
            ]),
    ]

    static func shader(id: String) -> ShaderLabShader? {
        shaders.first { $0.id == id }
    }
}
