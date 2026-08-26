import SwiftUI

/// The floating camera — the `FeatureFlags.cameraCapture` experiment's face.
///
/// A square viewfinder card low on the screen, over a scrim that keeps the gallery visible
/// behind it. Once a photo is taken the live card's chrome fades and a frozen `Image` of the
/// capture takes over as the `matchedGeometryEffect` source, ready to fly into the editor
/// canvas when the gallery hands the id over (`hasYieldedGeometry`).
///
/// The frozen image is a **sibling** of the card, not a child: the card clips its content to
/// the rounded square, and a flight clipped to its launchpad would vanish mid-air. The freeze
/// carries its own matching clip instead.
struct CameraOverlayView: View {

    /// Pairs the frozen capture with the editor canvas (`SharedZoomModifier`).
    static let captureGeometryID = "cameraCapture"

    /// Where the camera button's center lands in the card's own coordinate space (the card
    /// overlays the bottom bar): the anchor the card scales up from on open, so the entrance
    /// reads as growing out of the button. A transition anchor rather than matched geometry
    /// on purpose — a second always-mounted source in the gallery's shared namespace
    /// destabilized the other view-transition experiments, and the button never has to hide.
    static let launchAnchor = UnitPoint(x: 0.10, y: 0.85)

    let viewModel: CameraViewModel
    let namespace: Namespace.ID
    /// True once the gallery has handed the geometry id to the editor — the freeze frame
    /// yields `isSource` and follows the canvas from then on.
    let hasYieldedGeometry: Bool
    let onClose: () -> Void
    let onCapture: (UIImage) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// MOTION LAB's live values — the launch scale is a lab knob. Scaffolding, like every
    /// other observer of this store; see `MotionTuning`.
    @ObservedObject private var motionStore = MotionTuningStore.shared

    /// The entrance, as explicit state rather than an insertion `.transition`. Every
    /// transition variant tried on this overlay's insertion refused to animate (frame
    /// captures showed single-frame pops through three attempts — subtree `.animation`
    /// removed, single-transaction presentation, transition inside the layout), while
    /// state-driven `withAnimation` provably works everywhere in this app. So the card
    /// enters the way the editor's chrome does: mounted at its start pose, then animated
    /// to rest from `onAppear`.
    @State private var hasEntered = false

    private var hasCaptured: Bool { viewModel.capturedImage != nil }

    /// Scale the card holds before the entrance runs — the MOTION LAB knob, inert under
    /// Reduce Motion (fade only, no growth).
    private var restingScale: CGFloat {
        reduceMotion ? 1 : max(0.01, motionStore.tuning.cameraScaleFrom)
    }

    var body: some View {
        ZStack {
            // Slight scrim, per the design: the gallery stays legible behind the camera.
            // It fades with the chrome on capture so the incoming editor is not darkened.
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
                .opacity(!hasEntered || hasCaptured ? 0 : 1)
                .allowsHitTesting(hasEntered && !hasCaptured)

            viewfinderCard
                // Grows up out of the button's spot while fading in — and shrinks back into
                // it on dismiss. The anchor does the "out of the button" work; see
                // `launchAnchor`.
                .scaleEffect(hasEntered ? 1 : restingScale, anchor: Self.launchAnchor)
                .opacity(!hasEntered || hasCaptured ? 0 : 1)
                .allowsHitTesting(hasEntered && !hasCaptured)
                .cameraCardLayout(bottomPadding: motionStore.tuning.cameraBottomPadding)

            if let image = viewModel.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: AppConstants.Spacing.large, style: .continuous))
                    .matchedGeometryEffect(
                        id: Self.captureGeometryID,
                        in: namespace,
                        isSource: !hasYieldedGeometry
                    )
                    .cameraCardLayout(bottomPadding: motionStore.tuning.cameraBottomPadding)
                    // Purely visual: while it flies over the incoming editor it must never
                    // swallow taps meant for the chrome underneath.
                    .allowsHitTesting(false)
            }
        }
        // No subtree-wide `.animation(value:)` here — the capture fade is driven by an
        // explicit `withAnimation` where `capturedImage` is set (`CameraViewModel.capture()`),
        // the same shape `EditorViewModel` uses for `enhanceState`; the entrance by
        // `hasEntered` below.
        .onAppear {
            withAnimation(motionStore.tuning.cameraEffective.animation) {
                hasEntered = true
            }
        }
        .task { await viewModel.openCamera() }
        .onDisappear { viewModel.close() }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task { await viewModel.sceneDidActivate() }
            case .background:
                viewModel.sceneDidBackground()
            default:
                break
            }
        }
    }

    // MARK: - Card

    private var viewfinderCard: some View {
        ZStack(alignment: .bottom) {
            Color.black

            switch viewModel.permission {
            case .denied:
                permissionDeniedContent
            case .undetermined, .granted:
                CameraPreviewView(makeView: viewModel.makePreviewUIView)
                    .opacity(viewModel.sessionState == .running ? 1 : 0)
                    .animation(.easeIn(duration: 0.25), value: viewModel.sessionState)

                if case .failed(let message) = viewModel.sessionState {
                    Text(message)
                        .font(.silkscreenBody)
                        .foregroundColor(.textPrimary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if viewModel.permission != .denied {
                controlsRow
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    // Held back until the feed is up: during the launch morph the card passes
                    // through sizes that would crush a laid-out control row, and the mock/real
                    // session start covers almost exactly that window.
                    .opacity(controlsVisible ? 1 : 0)
                    .allowsHitTesting(controlsVisible)
                    .animation(.easeIn(duration: 0.25), value: controlsVisible)
            } else {
                closeButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        // Figma: the viewfinder's radius is the `spacing/large` token (32), a size up
        // from the editor canvas.
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.Spacing.large, style: .continuous))
    }

    // MARK: - Controls

    /// Running shows the working controls; a failure still shows them so the chevron stays
    /// reachable next to the error message.
    private var controlsVisible: Bool {
        if case .failed = viewModel.sessionState { return true }
        return viewModel.sessionState == .running
    }

    private var controlsRow: some View {
        ZStack {
            shutterButton

            HStack(spacing: 16) {
                closeButton
                Spacer()
                zoomButton
                flipButton
            }
        }
    }

    /// The reverse of the entrance: shrink back into the button, then hand the unmount to
    /// the gallery once the card is out of sight. Idempotent — a scrim tap racing the
    /// chevron just repeats a no-op state write and a second (harmless) close.
    private func dismiss() {
        withAnimation(motionStore.tuning.cameraEffective.animation) {
            hasEntered = false
        }
        // Unmount once the shrink has actually finished — the curve is a lab knob, so the
        // delay tracks it rather than hardcoding the default's length (a hardcoded beat cut
        // slower curves off mid-shrink).
        let settle = max(0.35, motionStore.tuning.cameraEffective.response * 1.2)
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
            onClose()
        }
    }

    private var closeButton: some View {
        Button {
            HapticService.selection()
            dismiss()
        } label: {
            controlWell {
                Image("icon-chevron-left")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(EnhancePressButtonStyle())
        .accessibilityLabel("Close camera")
        .accessibilityIdentifier("camera-close")
    }

    private var shutterButton: some View {
        Button {
            HapticService.medium()
            Task {
                await viewModel.capture()
                if let image = viewModel.capturedImage {
                    onCapture(image)
                }
            }
        } label: {
            // The camera's primary CTA wears what the other primary CTAs wear — the living
            // gradient — inside a transparent Liquid Glass rim *(user's call, 2026-08-26,
            // superseding the spec's flat mint)*.
            ZStack {
                ButtonGradientBackground()
                    .clipShape(RoundedRectangle(cornerRadius: AppConstants.Spacing.grid, style: .continuous))
                    .frame(width: 55, height: 55)
                Image("icon-camera-sharp")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .gradientButtonLabel()
            }
            .frame(width: 62, height: 62)
            .modifier(GlassSquare(cornerRadius: AppConstants.Spacing.grid + 3))
        }
        .buttonStyle(EnhancePressButtonStyle())
        .disabled(viewModel.isCapturing || viewModel.sessionState != .running)
        .accessibilityLabel("Take photo")
        .accessibilityIdentifier("camera-shutter")
    }

    private var zoomButton: some View {
        Button {
            HapticService.selection()
            viewModel.cycleZoom()
        } label: {
            controlWell {
                Text(viewModel.zoomLabel)
                    .font(.silkscreenSubheadline)
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(EnhancePressButtonStyle())
    }

    private var flipButton: some View {
        Button {
            HapticService.selection()
            Task { await viewModel.flip() }
        } label: {
            controlWell {
                // `switch-camera-sharp` over the spec's `more-horizontal-sharp` — a glyph
                // that says what the button does *(user's call, 2026-08-26)*.
                Image("icon-switch-camera-sharp")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(EnhancePressButtonStyle())
    }

    /// The small controls' shared shape: a rounded square on the grid radius, per the Figma
    /// spec (`spacing/grid` corners on 40pt wells) — squares, not circles, so the family
    /// matches the shutter beside them. Liquid Glass rather than a flat fill: the chrome
    /// floats over a live feed, and glass is what floating chrome is made of now.
    private func controlWell(@ViewBuilder content: () -> some View) -> some View {
        ZStack {
            content()
        }
        .frame(width: 40, height: 40)
        .modifier(GlassSquare(cornerRadius: AppConstants.Spacing.grid))
    }

    // MARK: - Permission denied

    private var permissionDeniedContent: some View {
        VStack(spacing: 20) {
            Text("ALLOW CAMERA ACCESS\nTO TAKE PHOTOS\nFOR YOUR GIFS")
                .font(.silkscreenBody)
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)

            Button {
                HapticService.selection()
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("OPEN SETTINGS")
                    .font(.silkscreenLabel)
                    .foregroundColor(.enhanceMint)
            }
            .buttonStyle(EnhancePressButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Liquid Glass where the OS has it, an ultra-thin material below iOS 26 — one modifier so
/// every piece of camera chrome refracts the same way.
private struct GlassSquare: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            // Glass as a *background*, not applied to the content itself: `glassEffect` on a
            // button's label hoists the label into an effect layer and its taps stop landing
            // (the zoom and flip buttons went dead, and the UI test's zoom taps had been
            // failing the same way). Behind the content, the glass is purely visual; the
            // explicit content shape then owns hit-testing *(user-reported, 2026-08-26)*.
            .background {
                if #available(iOS 26.0, *) {
                    // Plain glass, not `.interactive()`: interactive glass swells past its
                    // resting shape on touch, doubling `EnhancePressButtonStyle`'s press.
                    Color.clear.glassEffect(.regular, in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .contentShape(shape)
    }
}

/// The one place the viewfinder's on-screen frame is defined. The live card and the frozen
/// capture both use it, so the freeze lands pixel-exactly over the feed it replaces.
private struct CameraCardLayout: ViewModifier {
    /// Where the card rests, in points off the physical bottom edge — a MOTION LAB knob
    /// (`MotionTuning.cameraBottomPadding`; the Figma spec's value is 18).
    let bottomPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            // Measured from the physical bottom edge, not the safe area — the design sits
            // the card just off the hardware edge, riding over the home indicator.
            .padding(.bottom, bottomPadding)
            .ignoresSafeArea(edges: .bottom)
    }
}

private extension View {
    func cameraCardLayout(bottomPadding: CGFloat) -> some View {
        modifier(CameraCardLayout(bottomPadding: bottomPadding))
    }
}
