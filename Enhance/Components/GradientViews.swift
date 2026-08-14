import SwiftUI

// MARK: - Style

/// Which treatment a button gradient wears, as render parameters rather than as flags.
///
/// The two amounts are weights on the same shader, which is what lets STATIC and DITHER be
/// *independent* toggles: with both on the thresholds sum into a random-jittered ordered dither
/// — a real look — instead of one experiment having to win an arbitrary precedence fight.
///
/// Resolving flags to this type here, rather than branching on `UserDefaults` inside a view body,
/// keeps the policy pure and testable. Same shape as `EditorViewModel`'s injected
/// `allowsGenerationWithoutZoom`.
struct ButtonGradientStyle: Equatable {
    var noiseAmount: Double
    var orderedAmount: Double

    /// False means the plain `MeshGradient` path, untouched from before the experiments.
    var isQuantized: Bool { noiseAmount > 0 || orderedAmount > 0 }

    static let mesh = ButtonGradientStyle(noiseAmount: 0, orderedAmount: 0)

    static func resolve(staticOn: Bool, ditherOn: Bool, tuning: GradientTuning) -> ButtonGradientStyle {
        switch (staticOn, ditherOn) {
        case (false, false):
            return .mesh
        case (true, false):
            // Pure noise against a flat 0.5 cut.
            return ButtonGradientStyle(noiseAmount: tuning.noiseAmount, orderedAmount: 0)
        case (false, true):
            return ButtonGradientStyle(noiseAmount: 0, orderedAmount: tuning.orderedAmount)
        case (true, true):
            // The noise is halved in the blend: at full strength it swamps the Bayer matrix and
            // the result is indistinguishable from STATIC alone, which would make the second
            // toggle look broken rather than combined.
            return ButtonGradientStyle(noiseAmount: tuning.noiseAmount * 0.5,
                                       orderedAmount: tuning.orderedAmount)
        }
    }
}

// MARK: - Flag-reading wrappers

/// The button background every call site uses, and the only place the gradient flags are read.
///
/// Reading them here rather than at each of the seven call sites means a toggle in GENERAL
/// SETTINGS restyles every visible button live, with no notification plumbing — `@AppStorage` and
/// `@ObservedObject` both republish on change.
///
/// `cornerRadius` exists only so the optional ring can follow the caller's clip shape; the
/// background itself is still clipped by the caller as it always was.
struct ButtonGradientBackground: View {
    var cornerRadius: CGFloat = AppConstants.CornerRadius.card
    var borderWidth: CGFloat = 4

    /// False for callers that draw their own ring, so the flag's ring is not laid over an
    /// identical one at 0.85 opacity each.
    var showsBorder: Bool = true

    @AppStorage(FeatureFlags.staticGradientKey) private var staticOn = false
    @AppStorage(FeatureFlags.ditherGradientKey) private var ditherOn = false
    @AppStorage(FeatureFlags.staticBorderKey) private var borderOn = false
    @ObservedObject private var store = GradientTuningStore.shared

    var body: some View {
        SimpleGradientBackground(
            style: .resolve(staticOn: staticOn, ditherOn: ditherOn, tuning: store.tuning),
            tuning: store.tuning
        )
        .overlay {
            // The ring rides on the background rather than living only on `CircleButton`,
            // which turned out to be referenced by nothing but its own previews. A flag whose
            // effect is invisible in the running app cannot be evaluated, which is the one job
            // a flag has.
            if borderOn && showsBorder {
                ButtonGradientBorder(cornerRadius: cornerRadius, lineWidth: borderWidth)
            }
        }
    }
}

/// The animated ring, gated by its own flag so the border can be tried without the background.
struct ButtonGradientBorder: View {
    var cornerRadius: CGFloat = 8
    var lineWidth: CGFloat = 6

    @AppStorage(FeatureFlags.staticBorderKey) private var staticBorderOn = false
    @ObservedObject private var store = GradientTuningStore.shared

    var body: some View {
        SimpleGradientBorder(
            cornerRadius: cornerRadius,
            lineWidth: lineWidth,
            style: staticBorderOn
                ? ButtonGradientStyle(noiseAmount: store.tuning.noiseAmount, orderedAmount: 0)
                : .mesh,
            tuning: store.tuning
        )
    }
}

// MARK: - Label colour

/// Colours a label sitting on a gradient button.
///
/// Replaces the hardcoded `Color.textOnGradient` at those call sites. That constant was black,
/// which was safe while every button wore a bright mint mesh and stops being safe the moment the
/// poles can be dragged anywhere — a deep violet duotone puts black text on a dark ground. With
/// the flags off it still resolves to black, so nothing moves until you tune something.
///
/// A modifier rather than a colour constant because the answer depends on `GradientTuning`, and a
/// `static var` could not observe the store.
struct GradientButtonLabel: ViewModifier {
    @AppStorage(FeatureFlags.staticGradientKey) private var staticOn = false
    @AppStorage(FeatureFlags.ditherGradientKey) private var ditherOn = false
    @ObservedObject private var store = GradientTuningStore.shared

    /// Slow on purpose. This drives a decision between two colours, not a colour ramp — the pulse
    /// runs over seconds, so a handful of samples a second finds the crossover well inside the
    /// crossfade that hides it, at a fraction of the cost of tracking the display.
    private static let samplesPerSecond: Double = 6

    func body(content: Content) -> some View {
        // The mesh path is unchanged from before the experiments, so its label is too — the
        // contrast question only arises once the poles are what you are looking at.
        let quantized = ButtonGradientStyle
            .resolve(staticOn: staticOn, ditherOn: ditherOn, tuning: store.tuning)
            .isQuantized

        // Only `.auto` needs a clock. A fixed choice is a plain modifier, and paying for a
        // timeline on every button label to re-derive a constant would be silly.
        if quantized && store.tuning.labelMode == .auto {
            TimelineView(.periodic(from: .now, by: 1 / Self.samplesPerSecond)) { timeline in
                let color = store.tuning.labelColor(at: timeline.date.timeIntervalSinceReferenceDate)
                content
                    .foregroundColor(color)
                    // Black and white have no midpoint, so the flip is a step. Crossfading it is
                    // what keeps a pulse that crosses over from reading as a glitch.
                    .animation(.easeInOut(duration: 0.35), value: color)
            }
        } else {
            content.foregroundColor(quantized ? store.tuning.labelColor(at: 0) : .textOnGradient)
        }
    }
}

extension View {
    /// For text drawn over `ButtonGradientBackground`.
    func gradientButtonLabel() -> some View { modifier(GradientButtonLabel()) }
}

// MARK: - Canvas frame

/// The rotating gradient behind the editor canvas's frame, following the same flags as the
/// buttons *(user's call — APPLY should move the photo border too)*.
///
/// The caller still owns the shape: this fills its frame, and `EditorView` clips it to the outer
/// radius and punches the canvas out of the middle. Keeping the masking there is what lets one
/// view serve a frame and a button without knowing which it is.
///
/// Its density field is an `AngularGradient` rather than the buttons' mesh, because the sweep
/// around the frame *is* this element's character — quantizing a mesh here would have thrown away
/// the one thing that made it read as a rotating border.
struct CanvasGradientBorder: View {
    var size: CGFloat

    @AppStorage(FeatureFlags.staticGradientKey) private var staticOn = false
    @AppStorage(FeatureFlags.ditherGradientKey) private var ditherOn = false
    @ObservedObject private var store = GradientTuningStore.shared

    /// The original mint sweep. An 11-stop palindrome: the first and last stop are the same
    /// colour, so the seam where the angular gradient wraps is invisible.
    private static let meshColors: [Color] = [
        Color(red: 0.231, green: 1.0, blue: 0.988),
        Color(red: 0.122, green: 0.773, blue: 0.580),
        Color(red: 0.086, green: 0.698, blue: 0.443),
        Color(red: 0.537, green: 0.545, blue: 0.722),
        Color(red: 0.765, green: 0.467, blue: 0.863),
        Color(red: 0.988, green: 0.388, blue: 1.0),
        Color(red: 0.765, green: 0.467, blue: 0.863),
        Color(red: 0.537, green: 0.545, blue: 0.722),
        Color(red: 0.086, green: 0.698, blue: 0.443),
        Color(red: 0.122, green: 0.773, blue: 0.580),
        Color(red: 0.231, green: 1.0, blue: 0.988)
    ]

    /// The tuned density ramp, mirrored for the same seamless-wrap reason.
    private func quantizedColors(_ tuning: GradientTuning) -> [Color] {
        let light = tuning.meshLight.color
        let mid = tuning.meshMid.color
        let dark = tuning.meshDark.color
        return [light, mid, dark, mid, light, mid, dark, mid, light]
    }

    /// The two paths keep separate `TimelineView`s rather than sharing one with a chosen schedule:
    /// `.animation` and `.periodic` are different types, and more to the point the unquantized
    /// path should stay on the display's own clock exactly as it always has, while the quantized
    /// one wants the chunky `staticFrameRate` cadence.
    @ViewBuilder
    var body: some View {
        let style = ButtonGradientStyle.resolve(staticOn: staticOn, ditherOn: ditherOn, tuning: store.tuning)

        if style.isQuantized {
            quantized(style: style, tuning: store.tuning)
        } else {
            mesh
        }
    }

    private func quantized(style: ButtonGradientStyle, tuning: GradientTuning) -> some View {
        TimelineView(.periodic(from: .now, by: 1 / max(1, tuning.staticFrameRate))) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let direction: Double = tuning.borderReversed ? -1 : 1
            let angle = now.remainder(dividingBy: tuning.borderRotationDuration) * 36 * direction
            let poles = tuning.poles(at: now)

            AngularGradient(colors: quantizedColors(tuning), center: .center, angle: .degrees(angle))
                .frame(width: size, height: size)
                .layerEffect(
                    ShaderLibrary.staticDither(
                        .float(tuning.cellSize),
                        .float2(CGSize(width: size, height: size)),
                        .float(tuning.frameSeed(at: now)),
                        .float(style.noiseAmount),
                        .float(style.orderedAmount),
                        .float(tuning.halftoneAmount),
                        .float(tuning.halftoneAngle),
                        .float(tuning.splitDistance),
                        .float(tuning.splitAngle),
                        .float(tuning.levels.rounded()),
                        .float2(tuning.driftOffset(at: now)),
                        .color(poles.light),
                        .color(poles.mid),
                        .color(poles.dark)
                    ),
                    maxSampleOffset: CGSize(
                        width: tuning.cellSize + tuning.splitDistance,
                        height: tuning.cellSize + tuning.splitDistance
                    )
                )
        }
    }

    private var mesh: some View {
        TimelineView(.animation) { timeline in
            let angle = timeline.date.timeIntervalSinceReferenceDate.remainder(dividingBy: 4) * 90
            AngularGradient(colors: Self.meshColors, center: .center, angle: .degrees(angle))
                .frame(width: size, height: size)
                .layerEffect(
                    ShaderLibrary.pixellate(.float(CGFloat(8)), .float2(CGSize(width: size, height: size))),
                    maxSampleOffset: CGSize(width: 8, height: 8)
                )
        }
    }
}

// MARK: - Button Background Gradient
// This gradient creates a smooth, diffused effect using MeshGradient
struct SimpleGradientBackground: View {
    var width: Int = 3
    var height: Int = 3
    var primaryColors: [Color] = [
        Color(red: 0.231, green: 1.0, blue: 0.988),   Color(red: 0.122, green: 0.773, blue: 0.580),  Color(red: 0.765, green: 0.467, blue: 0.863),
        Color(red: 0.157, green: 0.851, blue: 0.714),  Color(red: 0.086, green: 0.698, blue: 0.443),  Color(red: 0.988, green: 0.388, blue: 1.0),
        Color(red: 0.231, green: 1.0, blue: 0.988),   Color(red: 0.196, green: 0.659, blue: 0.514),  Color(red: 0.537, green: 0.545, blue: 0.722)
    ]
    var secondaryColors: [Color] = [
        Color(red: 0.157, green: 0.851, blue: 0.714),  Color(red: 0.086, green: 0.698, blue: 0.443),  Color(red: 0.988, green: 0.388, blue: 1.0),
        Color(red: 0.231, green: 1.0, blue: 0.988),   Color(red: 0.196, green: 0.659, blue: 0.514),  Color(red: 0.765, green: 0.467, blue: 0.863),
        Color(red: 0.157, green: 0.851, blue: 0.714),  Color(red: 0.122, green: 0.773, blue: 0.580),  Color(red: 0.988, green: 0.388, blue: 1.0)
    ]
    var positionAnimationDuration: Double = 3.0
    var colorAnimationDuration: Double = 5.0
    /// Set to a value > 0 to apply GPU pixelation. Larger values = chunkier pixels.
    var pixelSize: CGFloat = 8

    /// `.mesh` renders exactly as this view always has. The quantized styles replace the
    /// pixelation shader with `staticDither` and read the mesh as a density field instead.
    var style: ButtonGradientStyle = .mesh
    var tuning: GradientTuning = .default

    @State private var isAnimating = false
    @State private var isColorToggled = false

    var body: some View {
        Group {
            if style.isQuantized {
                quantized
            } else {
                mesh(colors: isColorToggled ? secondaryColors : primaryColors, pixelSize: pixelSize)
            }
        }
        .onAppear {
            // The quantized styles take both durations from the tuning so the lab's sliders reach
            // them; the plain mesh keeps its own constants and so is unchanged by anything here.
            let fieldDuration = style.isQuantized ? tuning.fieldDuration : positionAnimationDuration
            let colorDuration = style.isQuantized ? tuning.pulseDuration : colorAnimationDuration

            withAnimation(.easeInOut(duration: fieldDuration).repeatForever(autoreverses: true)) {
                isAnimating.toggle()
            }
            withAnimation(.easeInOut(duration: colorDuration).repeatForever(autoreverses: true)) {
                isColorToggled.toggle()
            }
        }
    }

    /// The mesh, still drifting under `withAnimation`, but drawn only to be measured: the shader
    /// reads its luminance and throws its colours away.
    ///
    /// `.periodic` rather than `.animation` is the point of the frame-rate knob. The chunky
    /// reseed cadence *is* the look, and it costs a fraction of the view updates a per-frame
    /// schedule would across the seven buttons that can share a screen.
    private var quantized: some View {
        TimelineView(.periodic(from: .now, by: 1 / max(1, tuning.staticFrameRate))) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let poles = tuning.poles(at: now)
            GeometryReader { geo in
                meshGradient(colors: tuning.meshPalette(swapped: isColorToggled))
                    .layerEffect(
                        ShaderLibrary.staticDither(
                            .float(tuning.cellSize),
                            .float2(geo.size),
                            .float(tuning.frameSeed(at: now)),
                            .float(style.noiseAmount),
                            .float(style.orderedAmount),
                            .float(tuning.halftoneAmount),
                            .float(tuning.halftoneAngle),
                            .float(tuning.splitDistance),
                            .float(tuning.splitAngle),
                            .float(tuning.levels.rounded()),
                            .float2(tuning.driftOffset(at: now)),
                            .color(poles.light),
                            .color(poles.mid),
                            .color(poles.dark)
                        ),
                        // The split samples *outside* the cell, so the offset has to be allowed
                        // for here as well — clip it and the fringe is cut off at the edges.
                        maxSampleOffset: CGSize(
                            width: tuning.cellSize + tuning.splitDistance,
                            height: tuning.cellSize + tuning.splitDistance
                        )
                    )
            }
        }
    }

    private func mesh(colors: [Color], pixelSize: CGFloat) -> some View {
        GeometryReader { geo in
            meshGradient(colors: colors)
                .layerEffect(
                    ShaderLibrary.pixellate(.float(pixelSize), .float2(geo.size)),
                    maxSampleOffset: CGSize(width: pixelSize, height: pixelSize)
                )
        }
    }

    private func meshGradient(colors: [Color]) -> some View {
        MeshGradient(width: width, height: height,
                     locations: .points([
                        SIMD2<Float>(0.0, 0.0), SIMD2<Float>(isAnimating ? 0.3 : 0.7, 0.0), SIMD2<Float>(1.0, 0.0),
                        SIMD2<Float>(0.0, 0.5), SIMD2<Float>(isAnimating ? 0.2 : 0.8, isAnimating ? 0.3 : 0.7), SIMD2<Float>(1.0, isAnimating ? 0.4 : 0.6),
                        SIMD2<Float>(0.0, 1.0), SIMD2<Float>(isAnimating ? 0.7 : 0.3, 1.0), SIMD2<Float>(1.0, 1.0)
                     ]),
                     colors: .colors(colors),
                     smoothsColors: true)
    }
}

// MARK: - Border Gradient Animation
// Creates a soft, diffused border effect that matches Apple's gradient style
struct SimpleGradientBorder: View {
    var cornerRadius: CGFloat = 8
    var lineWidth: CGFloat = 6

    var style: ButtonGradientStyle = .mesh
    var tuning: GradientTuning = .default

    /// Animation state
    @State private var isColorToggled = false

    private var gradient: Gradient {
        let t = tuning
        return isColorToggled
            ? Gradient(colors: [t.borderStartB.color, t.borderEndB.color])
            : Gradient(colors: [t.borderStartA.color, t.borderEndA.color])
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            // Compute rotation angle based on current time
            let now = timeline.date.timeIntervalSinceReferenceDate
            let direction: Double = tuning.borderReversed ? -1 : 1
            let angle = now.remainder(dividingBy: tuning.borderRotationDuration) * 36 * direction

            ring(angle: angle, now: now)
                .onAppear {
                    // Animate color changes
                    withAnimation(.easeInOut(duration: tuning.pulseDuration).repeatForever(autoreverses: true)) {
                        isColorToggled.toggle()
                    }
                }
        }
    }

    /// One masked layer, not the three nested `strokeBorder`/`.background` shapes this used to
    /// carry. The old stack drew the same ring three times over; harmless when it was a flat
    /// gradient, but a `layerEffect` on top of it would have quantized a tripled composite.
    @ViewBuilder
    private func ring(angle: Double, now: TimeInterval) -> some View {
        GeometryReader { geo in
            // `AngularGradient` is both a `View` and a `ShapeStyle`, so `.opacity` on it is
            // ambiguous. Applied to the composed result instead, which is also where it belongs
            // now that the shader may have replaced the gradient's colours entirely.
            let base = AngularGradient(gradient: gradient, center: .center, angle: .degrees(angle))

            Group {
                if style.isQuantized {
                    let poles = tuning.poles(at: now)
                    base.layerEffect(
                        ShaderLibrary.staticDither(
                            .float(tuning.cellSize),
                            .float2(geo.size),
                            .float(tuning.frameSeed(at: now)),
                            .float(style.noiseAmount),
                            .float(style.orderedAmount),
                            .float(tuning.halftoneAmount),
                            .float(tuning.halftoneAngle),
                            .float(tuning.splitDistance),
                            .float(tuning.splitAngle),
                            .float(tuning.levels.rounded()),
                            .float2(tuning.driftOffset(at: now)),
                            .color(poles.light),
                            .color(poles.mid),
                            .color(poles.dark)
                        ),
                        maxSampleOffset: CGSize(
                            width: tuning.cellSize + tuning.splitDistance,
                            height: tuning.cellSize + tuning.splitDistance
                        )
                    )
                } else {
                    base
                }
            }
            .opacity(0.85)
            .mask(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(lineWidth: lineWidth)
            )
        }
    }
}

// Preview for the components
struct GradientViews_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Group {
                Text("MESH (default)").foregroundColor(.white)
                SimpleGradientBackground()
                    .frame(height: 60)
                    .cornerRadius(8)

                Text("STATIC").foregroundColor(.white)
                SimpleGradientBackground(
                    style: .resolve(staticOn: true, ditherOn: false, tuning: .default)
                )
                    .frame(height: 60)
                    .cornerRadius(8)

                Text("DITHER").foregroundColor(.white)
                SimpleGradientBackground(
                    style: .resolve(staticOn: false, ditherOn: true, tuning: .default)
                )
                    .frame(height: 60)
                    .cornerRadius(8)

                Text("BOTH").foregroundColor(.white)
                SimpleGradientBackground(
                    style: .resolve(staticOn: true, ditherOn: true, tuning: .default)
                )
                    .frame(height: 60)
                    .cornerRadius(8)
            }

            Divider().background(Color.white)

            Group {
                Text("BORDER").foregroundColor(.white)
                SimpleGradientBorder()
                    .frame(width: 200, height: 60)

                Text("STATIC BORDER").foregroundColor(.white)
                SimpleGradientBorder(
                    style: ButtonGradientStyle(noiseAmount: 1, orderedAmount: 0)
                )
                    .frame(width: 200, height: 60)
            }
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
