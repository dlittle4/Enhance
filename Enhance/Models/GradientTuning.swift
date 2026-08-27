import SwiftUI
import UIKit

/// Every knob on the button gradients, in one value.
///
/// This exists because the right colours for the STATIC and DITHER experiments are not knowable
/// from a spec — they have to be found by dragging a picker and looking at the result. So the
/// values that were hardcoded in `GradientViews.swift` move here, GRADIENT LAB edits them live,
/// and `swiftSnippet` hands back a paste-ready block of Swift once a look is settled.
///
/// **This type is scaffolding.** When an experiment graduates, its snippet becomes the new
/// defaults in `GradientViews.swift` and this file, `GradientTuningStore` and `GradientLabView`
/// all go — which is why the whole thing is one struct behind one `UserDefaults` key rather than
/// a scattering of properties. See `FeatureFlags` for the same reasoning applied to the toggles.
struct GradientTuning: Codable, Equatable {

    // MARK: Pole colours

    /// The two colours the static actually resolves to, in pulse state A.
    ///
    /// "Light" and "dark" name their *role* in the threshold, not their appearance: the light
    /// pole is what a bright cell of the density field takes. Making the light pole the darker
    /// colour is a legitimate thing to try in the lab.
    var poleLightA: RGBColor
    var poleDarkA: RGBColor

    /// The same pair at the other end of the pulse. The cross-fade between A and B is the whole
    /// of the colour animation; setting them equal freezes it.
    var poleLightB: RGBColor
    var poleDarkB: RGBColor

    /// The third pole, used only when `levels` is 3.
    ///
    /// Carried even at two levels so that raising and lowering the LEVELS slider is lossless —
    /// dropping to duotone and coming back returns the mid colour you had chosen, rather than a
    /// default you then have to find again.
    var poleMidA: RGBColor
    var poleMidB: RGBColor

    // MARK: Camera pole colours

    /// The same six poles again, for the camera buttons — the launcher beside MAKE A GIF and the
    /// in-camera shutter. They exist so the camera CTA can wear a different colour than the
    /// primary CTA *(user's call, 2026-08-26)*. Only the poles fork: texture, timing and the
    /// border stay shared, so the two buttons read as siblings in different shirts rather than
    /// as strangers.
    var cameraPoleLightA: RGBColor
    var cameraPoleDarkA: RGBColor
    var cameraPoleLightB: RGBColor
    var cameraPoleDarkB: RGBColor
    var cameraPoleMidA: RGBColor
    var cameraPoleMidB: RGBColor

    /// Which pole set a gradient view reads. Everything defaults to `.primary`; the two camera
    /// buttons are the only call sites that say otherwise.
    enum ButtonRole {
        case primary, camera
    }

    // MARK: Density field

    /// Three stops that build the 3×3 `MeshGradient` the quantized styles read as their density
    /// field. **The unquantized MESH style does not use these** — it keeps its own six-hue
    /// palette, so an install with every flag off is unchanged.
    ///
    /// They are a deliberate *luminance* ramp rather than a copy of that palette, and that is the
    /// whole reason they exist. The original nine colours are a hue swirl: cyan, mint, greens,
    /// periwinkle, orchid, magenta all land between 0.49 and 0.77 luminance. Beautiful as a
    /// gradient, useless as a threshold field — quantizing it gives noise of near-uniform density
    /// with no falloff anywhere. Spreading light → dark across the grid is what produces the
    /// thinning across a button that the effect is for.
    var meshLight: RGBColor
    var meshMid: RGBColor
    var meshDark: RGBColor

    // MARK: Border ring

    var borderStartA: RGBColor
    var borderEndA: RGBColor
    var borderStartB: RGBColor
    var borderEndB: RGBColor

    // MARK: Numerics

    /// Cell edge in points.
    ///
    /// Independent of the MESH path's 8pt pixelation, and much finer, because the two are doing
    /// different jobs: 8pt chunks read as *pixel art* when they carry a smooth gradient, but as
    /// clumsy blocks once each one is forced to a single flat colour. The reference screenshots
    /// are grain, not blocks — measured off them, roughly 2pt.
    var cellSize: Double

    /// How far the per-frame hash may push the threshold. 0 disables STATIC's boil.
    var noiseAmount: Double

    /// How far the Bayer matrix displaces the threshold from a flat 0.5 cut. 0 disables DITHER.
    var orderedAmount: Double

    /// How far the halftone screen displaces the threshold. 0 leaves square cells.
    ///
    /// Blended with the other two rather than switched between, so a little of it rounds the
    /// grain off and a lot of it turns the button into a dot screen.
    var halftoneAmount: Double

    /// Screen angle in radians. An unrotated screen aligns with the pixel grid and reads as a
    /// plaid, which is why print screens every process on a slant; 15–45° is the useful band.
    var halftoneAngle: Double

    /// How far apart the red and blue channels sample, in points. 0 is no split.
    var splitDistance: Double

    /// Direction of that displacement, in radians.
    var splitAngle: Double

    /// 2 for duotone, 3 to bring `poleMid` in. Fractional values are meaningless — the slider
    /// quantizes, and the shader floors.
    var levels: Double

    /// Seconds for a full there-and-back colour pulse.
    var pulseDuration: Double

    /// Ticks per second for the noise reseed.
    ///
    /// Deliberately not display rate: the chunky cadence is part of the look, and a `.periodic`
    /// schedule at 12fps costs a fraction of the view updates `TimelineView(.animation)` would
    /// across the seven buttons that can be on screen at once.
    var staticFrameRate: Double

    /// Seconds per full rotation of the border's angular gradient.
    var borderRotationDuration: Double

    /// Reverses that rotation. Two directions is the whole vocabulary a spin has.
    var borderReversed: Bool

    /// Direction the dither texture travels, in radians. 0 is rightward, π/2 downward.
    var driftAngle: Double

    /// How fast it travels, in points per second. 0 holds it still.
    ///
    /// This moves the *threshold* fields — the Bayer matrix, the halftone screen, the noise — not
    /// the gradient underneath. Scrolling the gradient would drag its edges through the frame and
    /// need a seam; scrolling the pattern over a stationary field is what reads as the texture
    /// itself marching, which is the effect worth having.
    var driftSpeed: Double

    /// Seconds for the density field's control points to drift from one arrangement to the other.
    ///
    /// The slow morph under everything else — was a hardcoded 3s. Distinct from `driftSpeed`:
    /// this changes the *shape* of the falloff, drift slides the grain across it.
    var fieldDuration: Double

    /// Which colour a button's label takes over the gradient.
    ///
    /// The app hardcoded `Color.textOnGradient` — black — which was safe when every button wore a
    /// bright mint mesh. It stops being safe the moment the poles can be dragged anywhere: a deep
    /// violet duotone puts black text on a dark ground. `.auto` is the honest default, since the
    /// value that keeps it readable is a function of colours the lab can change at any time.
    var labelMode: LabelMode

    enum LabelMode: String, Codable, CaseIterable {
        case auto, black, white

        var title: String { rawValue.uppercased() }
    }

    // MARK: - Defaults

    /// **The adopted profile** *(user's call, 2026-08-26)*: the values dialled in on device and
    /// pulled from its defaults, replacing the carried-forward originals. The dark poles moved to
    /// deep greens, the dither/noise mix settled at 0.65/0.2 with a touch of halftone, and the
    /// field drifts — the look the STATIC/DITHERED flags now ship.
    static let `default` = GradientTuning(
        poleLightA: RGBColor(r: 0.231, g: 1.0, b: 0.988),
        poleDarkA: RGBColor(r: 0.0, g: 0.9367, b: 0.3347),
        poleLightB: RGBColor(r: 0.157, g: 0.851, b: 0.714),
        poleDarkB: RGBColor(r: 0.0, g: 0.7623, b: 0.4731),
        poleMidA: RGBColor(r: 0.122, g: 0.773, b: 0.580),
        poleMidB: RGBColor(r: 0.988, g: 0.388, b: 1.0),
        // The primary poles again, verbatim: until the lab pulls them apart, the camera button
        // is dressed identically and an untouched install cannot tell this fork ever happened.
        cameraPoleLightA: RGBColor(r: 0.231, g: 1.0, b: 0.988),
        cameraPoleDarkA: RGBColor(r: 0.0, g: 0.9367, b: 0.3347),
        cameraPoleLightB: RGBColor(r: 0.157, g: 0.851, b: 0.714),
        cameraPoleDarkB: RGBColor(r: 0.0, g: 0.7623, b: 0.4731),
        cameraPoleMidA: RGBColor(r: 0.122, g: 0.773, b: 0.580),
        cameraPoleMidB: RGBColor(r: 0.988, g: 0.388, b: 1.0),
        meshLight: RGBColor(r: 0.231, g: 1.0, b: 0.988),
        meshMid: RGBColor(r: 0.196, g: 0.659, b: 0.514),
        meshDark: RGBColor(r: 0.400, g: 0.220, b: 0.500),
        borderStartA: RGBColor(r: 0.0, g: 0.5, b: 0.9),
        borderEndA: RGBColor(r: 0.8, g: 0.2, b: 0.9),
        borderStartB: RGBColor(r: 0.95, g: 0.3, b: 0.7),
        borderEndB: RGBColor(r: 0.95, g: 0.1, b: 0.4),
        cellSize: 1.75,
        noiseAmount: 0.2,
        orderedAmount: 0.65,
        halftoneAmount: 0.35,
        halftoneAngle: .pi / 8,          // 22.5°, off the pixel grid
        splitDistance: 3,
        splitAngle: 1.4 * .pi,
        levels: 2,
        pulseDuration: 3.75,
        staticFrameRate: 26.1,
        borderRotationDuration: 11.8,
        borderReversed: false,
        driftAngle: 0.8 * .pi,
        driftSpeed: 16,
        fieldDuration: 9.7,
        labelMode: .auto
    )

    // MARK: - Derived

    /// The nine `MeshGradient` colours forming the density field, for one end of the pulse.
    ///
    /// Read as a grid: bright along one diagonal, dark along the other. That asymmetry is what
    /// gives a wide button the diagonal thinning in the reference screenshots — a concentric
    /// arrangement would have produced a vignette instead, which on a 60pt-tall capsule reads as
    /// a smudge rather than a gradient. `swapped` mirrors the diagonal, so the pulse sweeps the
    /// dense region across the button rather than merely brightening in place.
    func meshPalette(swapped: Bool) -> [Color] {
        let light = meshLight.color
        let mid = meshMid.color
        let dark = meshDark.color
        return swapped
            ? [dark, mid, light,
               mid, mid, light,
               dark, dark, mid]
            : [light, mid, dark,
               light, mid, mid,
               mid, dark, dark]
    }

    /// The pole colours at `time`, lerped across the pulse.
    ///
    /// A sine rather than a sawtooth so the turn at each end is smooth, and pure so the lab's
    /// preview, the buttons and the tests all agree on what a given instant looks like.
    func poles(at time: TimeInterval, role: ButtonRole = .primary) -> (light: Color, mid: Color, dark: Color) {
        let rgb = polesRGB(at: time, role: role)
        return (light: rgb.light.color, mid: rgb.mid.color, dark: rgb.dark.color)
    }

    /// The same lerp before the conversion to `Color`, whose components cannot be read back
    /// without a round trip through `UIColor`. The contrast maths wants the numbers.
    func polesRGB(at time: TimeInterval, role: ButtonRole = .primary) -> (light: RGBColor, mid: RGBColor, dark: RGBColor) {
        let t = pulsePhase(at: time)
        switch role {
        case .primary:
            return (
                light: poleLightA.lerp(to: poleLightB, t: t),
                mid: poleMidA.lerp(to: poleMidB, t: t),
                dark: poleDarkA.lerp(to: poleDarkB, t: t)
            )
        case .camera:
            return (
                light: cameraPoleLightA.lerp(to: cameraPoleLightB, t: t),
                mid: cameraPoleMidA.lerp(to: cameraPoleMidB, t: t),
                dark: cameraPoleDarkA.lerp(to: cameraPoleDarkB, t: t)
            )
        }
    }

    private func pulsePhase(at time: TimeInterval) -> Double {
        pulseDuration > 0 ? (sin(2 * .pi * time / pulseDuration) + 1) / 2 : 0
    }

    /// A small whole number that advances once per static tick, for the noise hash.
    ///
    /// Not the raw time interval, and this is load-bearing rather than tidiness. A shader
    /// argument is a 32-bit `float`, and `timeIntervalSinceReferenceDate` is around 7.8×10⁸ —
    /// at that magnitude the mantissa has no bits left for a fraction, so consecutive frames
    /// arrive at the GPU as the *same* number and the static freezes into a still pattern.
    /// Counting ticks and wrapping keeps the value somewhere float32 can still tell frames apart.
    func frameSeed(at time: TimeInterval) -> Double {
        let rate = max(1, staticFrameRate)
        return (time * rate).rounded(.down).truncatingRemainder(dividingBy: 4096)
    }

    /// How far the threshold pattern has travelled by `time`, in points.
    ///
    /// Wrapped, for the same float32 reason `frameSeed` documents, and wrapped specifically to a
    /// multiple of four cells so the Bayer matrix — whose period is exactly four — lands back on
    /// itself and the wrap is invisible. The halftone screen is rotated, so its period does not
    /// divide evenly and it does take a small jump at the wrap; at these distances that is once
    /// every few minutes, against a seam every few seconds if the wrap were tightened to suit it.
    func driftOffset(at time: TimeInterval) -> CGSize {
        guard driftSpeed > 0 else { return .zero }
        let period = max(4 * cellSize, 1) * 256
        let travelled = (driftSpeed * time).truncatingRemainder(dividingBy: period)
        return CGSize(width: cos(driftAngle) * travelled, height: sin(driftAngle) * travelled)
    }

    // MARK: - Label contrast

    /// The colour a button's label should take over this gradient at `time`.
    ///
    /// `.auto` measures rather than guesses: WCAG relative luminance of the ground, then whichever
    /// of black or white scores the higher contrast ratio against it. The alternative — a
    /// brightness threshold — gets green wrong, because the eye weights green nearly ten times
    /// blue and a naive average does not.
    ///
    /// Evaluated **per instant** rather than once across the whole pulse *(user's call)*. A pulse
    /// that runs from mint to deep violet has no single label colour that is right for both ends,
    /// so the label tracks it and flips when the ground crosses over. Callers crossfade that flip
    /// rather than cutting it; see `GradientButtonLabel`.
    func labelColor(at time: TimeInterval, role: ButtonRole = .primary) -> Color {
        switch labelMode {
        case .black: return .black
        case .white: return .white
        case .auto:
            let ground = self.ground(at: time, role: role)
            return Self.contrastRatio(of: .white, on: ground) >=
                   Self.contrastRatio(of: .black, on: ground) ? .white : .black
        }
    }

    /// The mean of the colours actually on screen at `time`, weighted evenly.
    ///
    /// A dither is roughly half one pole and half the other at any point, so their mean is a fair
    /// stand-in for what a glyph sits on. At two levels the mid poles are not rendered, so
    /// including them would drag the ground toward a colour that is not there.
    func ground(at time: TimeInterval, role: ButtonRole = .primary) -> RGBColor {
        let poles = polesRGB(at: time, role: role)
        var swatches = [poles.light, poles.dark]
        if levels >= 2.5 { swatches.append(poles.mid) }

        let count = Double(swatches.count)
        return RGBColor(
            r: swatches.reduce(0) { $0 + $1.r } / count,
            g: swatches.reduce(0) { $0 + $1.g } / count,
            b: swatches.reduce(0) { $0 + $1.b } / count
        )
    }

    /// The contrast ratio the label actually achieves at `time`. Surfaced in the lab so a duotone
    /// that has drifted into unreadable territory says so, rather than waiting to be noticed on a
    /// real button.
    func labelContrast(at time: TimeInterval, role: ButtonRole = .primary) -> Double {
        Self.contrastRatio(of: labelColor(at: time, role: role), on: ground(at: time, role: role))
    }

    /// The worst ratio the label hits anywhere in the pulse.
    ///
    /// This is the number that decides whether a palette is *usable*: a look that reads beautifully
    /// at one end of the cycle and turns to mud at the other is a look that fails, and an instant
    /// reading taken at the wrong moment would not say so. Sampled rather than solved — the
    /// crossover is a step function, so there is nothing to differentiate.
    func worstLabelContrast(samples: Int = 24, role: ButtonRole = .primary) -> Double {
        guard pulseDuration > 0 else { return labelContrast(at: 0, role: role) }
        return (0..<samples)
            .map { labelContrast(at: pulseDuration * Double($0) / Double(samples), role: role) }
            .min() ?? labelContrast(at: 0, role: role)
    }

    /// WCAG 2.1 contrast ratio, 1 (identical) to 21 (black on white).
    static func contrastRatio(of foreground: Color, on background: RGBColor) -> Double {
        let a = relativeLuminance(of: RGBColor(foreground))
        let b = relativeLuminance(of: background)
        let lighter = max(a, b), darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// WCAG relative luminance: linearize each channel out of sRGB's gamma curve, then weight by
    /// the eye's sensitivity to it. The weights are why this is not a brightness average.
    static func relativeLuminance(of color: RGBColor) -> Double {
        func linear(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    }

    // MARK: - Export

    /// A paste-ready Swift block naming the properties it replaces.
    ///
    /// The point of the lab: settle on a look, copy this, drop it into `GradientViews.swift`,
    /// delete the scaffolding.
    var swiftSnippet: String {
        """
        // Copied from GRADIENT LAB.
        static let tuned = GradientTuning(
            poleLightA: \(poleLightA.swiftLiteral),
            poleDarkA: \(poleDarkA.swiftLiteral),
            poleLightB: \(poleLightB.swiftLiteral),
            poleDarkB: \(poleDarkB.swiftLiteral),
            poleMidA: \(poleMidA.swiftLiteral),
            poleMidB: \(poleMidB.swiftLiteral),
            cameraPoleLightA: \(cameraPoleLightA.swiftLiteral),
            cameraPoleDarkA: \(cameraPoleDarkA.swiftLiteral),
            cameraPoleLightB: \(cameraPoleLightB.swiftLiteral),
            cameraPoleDarkB: \(cameraPoleDarkB.swiftLiteral),
            cameraPoleMidA: \(cameraPoleMidA.swiftLiteral),
            cameraPoleMidB: \(cameraPoleMidB.swiftLiteral),
            meshLight: \(meshLight.swiftLiteral),
            meshMid: \(meshMid.swiftLiteral),
            meshDark: \(meshDark.swiftLiteral),
            borderStartA: \(borderStartA.swiftLiteral),
            borderEndA: \(borderEndA.swiftLiteral),
            borderStartB: \(borderStartB.swiftLiteral),
            borderEndB: \(borderEndB.swiftLiteral),
            cellSize: \(Self.number(cellSize)),
            noiseAmount: \(Self.number(noiseAmount)),
            orderedAmount: \(Self.number(orderedAmount)),
            halftoneAmount: \(Self.number(halftoneAmount)),
            halftoneAngle: \(Self.number(halftoneAngle)),
            splitDistance: \(Self.number(splitDistance)),
            splitAngle: \(Self.number(splitAngle)),
            levels: \(Self.number(levels)),
            pulseDuration: \(Self.number(pulseDuration)),
            staticFrameRate: \(Self.number(staticFrameRate)),
            borderRotationDuration: \(Self.number(borderRotationDuration)),
            borderReversed: \(borderReversed),
            driftAngle: \(Self.number(driftAngle)),
            driftSpeed: \(Self.number(driftSpeed)),
            fieldDuration: \(Self.number(fieldDuration)),
            labelMode: .\(labelMode.rawValue)
        )
        """
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

// MARK: - Tolerant decoding

/// Decoding that fills in whatever the stored blob is missing.
///
/// Synthesised `Codable` throws on an absent key, which would mean that every time the lab gains
/// a parameter, the tuning already in `UserDefaults` stops decoding and an evening's work reverts
/// to stock on the next launch. The lab exists *to* grow these fields, so that is the expected
/// path rather than an edge case.
///
/// In an extension rather than the main declaration so the memberwise initialiser survives —
/// `GradientTuning.default` is built with it.
extension GradientTuning {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = GradientTuning.default

        func color(_ key: CodingKeys, _ or: RGBColor) -> RGBColor {
            ((try? container.decodeIfPresent(RGBColor.self, forKey: key)) ?? nil) ?? or
        }
        func number(_ key: CodingKeys, _ or: Double) -> Double {
            ((try? container.decodeIfPresent(Double.self, forKey: key)) ?? nil) ?? or
        }

        // Decoded ahead of the big call because the camera poles fall back to *these*, not to the
        // stock defaults: a blob from before the camera fork was tuned with one set of poles, and
        // the honest reading is that its camera button wore them too. Falling back to `fallback`
        // instead would snap the camera button to stock greens while every other button kept the
        // user's palette.
        let poleLightA = color(.poleLightA, fallback.poleLightA)
        let poleDarkA = color(.poleDarkA, fallback.poleDarkA)
        let poleLightB = color(.poleLightB, fallback.poleLightB)
        let poleDarkB = color(.poleDarkB, fallback.poleDarkB)
        let poleMidA = color(.poleMidA, fallback.poleMidA)
        let poleMidB = color(.poleMidB, fallback.poleMidB)

        self.init(
            poleLightA: poleLightA,
            poleDarkA: poleDarkA,
            poleLightB: poleLightB,
            poleDarkB: poleDarkB,
            poleMidA: poleMidA,
            poleMidB: poleMidB,
            cameraPoleLightA: color(.cameraPoleLightA, poleLightA),
            cameraPoleDarkA: color(.cameraPoleDarkA, poleDarkA),
            cameraPoleLightB: color(.cameraPoleLightB, poleLightB),
            cameraPoleDarkB: color(.cameraPoleDarkB, poleDarkB),
            cameraPoleMidA: color(.cameraPoleMidA, poleMidA),
            cameraPoleMidB: color(.cameraPoleMidB, poleMidB),
            meshLight: color(.meshLight, fallback.meshLight),
            meshMid: color(.meshMid, fallback.meshMid),
            meshDark: color(.meshDark, fallback.meshDark),
            borderStartA: color(.borderStartA, fallback.borderStartA),
            borderEndA: color(.borderEndA, fallback.borderEndA),
            borderStartB: color(.borderStartB, fallback.borderStartB),
            borderEndB: color(.borderEndB, fallback.borderEndB),
            cellSize: number(.cellSize, fallback.cellSize),
            noiseAmount: number(.noiseAmount, fallback.noiseAmount),
            orderedAmount: number(.orderedAmount, fallback.orderedAmount),
            halftoneAmount: number(.halftoneAmount, fallback.halftoneAmount),
            halftoneAngle: number(.halftoneAngle, fallback.halftoneAngle),
            splitDistance: number(.splitDistance, fallback.splitDistance),
            splitAngle: number(.splitAngle, fallback.splitAngle),
            levels: number(.levels, fallback.levels),
            pulseDuration: number(.pulseDuration, fallback.pulseDuration),
            staticFrameRate: number(.staticFrameRate, fallback.staticFrameRate),
            borderRotationDuration: number(.borderRotationDuration, fallback.borderRotationDuration),
            borderReversed: ((try? container.decodeIfPresent(Bool.self, forKey: .borderReversed)) ?? nil)
                ?? fallback.borderReversed,
            driftAngle: number(.driftAngle, fallback.driftAngle),
            driftSpeed: number(.driftSpeed, fallback.driftSpeed),
            fieldDuration: number(.fieldDuration, fallback.fieldDuration),
            labelMode: ((try? container.decodeIfPresent(LabelMode.self, forKey: .labelMode)) ?? nil)
                ?? fallback.labelMode
        )
    }
}

/// An sRGB triple that survives `Codable`, which `Color` does not.
///
/// The `Color` → components direction reuses the recipe `GradientStops` already relies on: a
/// `ColorPicker` can hand back Display P3 colours whose sRGB components fall outside 0–1, and
/// those reach a shader as out-of-gamut garbage unless they are clamped here.
struct RGBColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double

    var color: Color { Color(red: r, green: g, blue: b) }

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.r = Double(max(0, min(1, red)))
        self.g = Double(max(0, min(1, green)))
        self.b = Double(max(0, min(1, blue)))
    }

    func lerp(to other: RGBColor, t: Double) -> RGBColor {
        let f = max(0, min(1, t))
        return RGBColor(
            r: r + (other.r - r) * f,
            g: g + (other.g - g) * f,
            b: b + (other.b - b) * f
        )
    }

    var swiftLiteral: String {
        String(format: "RGBColor(r: %.3f, g: %.3f, b: %.3f)", r, g, b)
    }
}
