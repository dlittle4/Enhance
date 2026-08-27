import SwiftUI

/// The floating camera — the `FeatureFlags.cameraCapture` experiment's face.
///
/// A square viewfinder card low on the screen, over a scrim that keeps the gallery visible
/// behind it. Once a photo is taken the live card's chrome fades and a frozen `Image` of the
/// capture holds its place, reporting where it sits (`onFreezeFrameChange`) so the gallery's
/// flyer can take off from that exact rect — the same measured-rect flight the grid-cell zoom
/// flies, replacing the matched-geometry pairing this overlay used to carry (see
/// FEATURE-VIEW-TRANSITIONS.md, Idea 1's device-pass record, for why matched geometry cannot
/// do this job: the photo chased the canvas's *bordered* rect and landed over the stroke).
///
/// The frozen image is a **sibling** of the card, not a child: the card clips its content to
/// the rounded square, and the flyer that replaces it must never have been clipped to its
/// launchpad. The freeze carries its own matching clip instead.
struct CameraOverlayView: View {

    /// The corner radius the frozen capture wears — the flight's starting clip, flown to the
    /// canvas's radius by the gallery.
    static let freezeCornerRadius: CGFloat = AppConstants.Spacing.large

    /// Where the camera button's center lands in the card's own coordinate space (the card
    /// overlays the bottom bar): the anchor the card scales up from on open, so the entrance
    /// reads as growing out of the button. The button never has to hide.
    static let launchAnchor = UnitPoint(x: 0.10, y: 0.85)

    let viewModel: CameraViewModel
    /// True while the gallery's flyer is carrying the captured photo — the freeze frame hides
    /// beneath it, the same one-visible-copy rule the grid cell follows.
    let photoInFlight: Bool
    let onClose: () -> Void
    let onCapture: (UIImage) -> Void
    /// The frozen capture's frame in global coordinates, reported on layout — the flight's
    /// launch pad. Measured on the freeze itself (which carries no entrance transform) rather
    /// than the viewfinder card, whose launch morph scales it.
    let onFreezeFrameChange: (CGRect) -> Void

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

    /// The feed's pixel-resolve intro. `waiting` covers the feed in black until the first
    /// tapped frame lands; `running` is the sweep; `done` unmounts the overlay and hands
    /// off to the live preview layer. One-way — the intro plays once per presentation.
    private enum ResolvePhase { case waiting, running, done }
    @State private var resolvePhase: ResolvePhase = .waiting

    /// The overlay's closing fade, as explicit state for the same reason `hasEntered` is.
    @State private var resolveVisible = true

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
                    .clipShape(RoundedRectangle(cornerRadius: Self.freezeCornerRadius, style: .continuous))
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        onFreezeFrameChange(frame)
                    }
                    .cameraCardLayout(bottomPadding: motionStore.tuning.cameraBottomPadding)
                    // Hidden the moment the flyer mounts over it — same picture, same rect,
                    // so the swap is invisible and only one copy is ever on screen.
                    .opacity(photoInFlight ? 0 : 1)
                    // Purely visual: it must never swallow taps meant for the chrome
                    // underneath.
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
            // Decided before the session starts so the tap can catch the very first frame.
            // Reduce Motion and a zeroed REVEAL TIME never enable the tap at all — the feed
            // keeps its plain fade and the real service's video path stays cold.
            if reduceMotion || motionStore.tuning.cameraRevealTime <= 0 {
                resolvePhase = .done
            } else {
                viewModel.beginIntroFrames()
            }
            startResolveIfReady()
        }
        .task { await viewModel.openCamera() }
        .onDisappear { viewModel.close() }
        .onChange(of: hasEntered) { _, _ in startResolveIfReady() }
        // Nil-to-frame is the start signal; the Bool keeps this from firing per frame.
        .onChange(of: viewModel.previewFrame == nil) { _, _ in startResolveIfReady() }
        .onChange(of: viewModel.sessionState) { _, newState in
            switch newState {
            case .failed:
                // Immediately, not via the fade: the error text renders above the overlay,
                // but a black square lingering under it reads as a hung feed.
                finishResolve(fade: false)
            case .running:
                // The tap is optional hardware (`canAddOutput` may refuse it): if no frame
                // arrives shortly after the session is live, degrade to exactly the plain
                // fade this intro replaced.
                guard resolvePhase == .waiting else { break }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if resolvePhase == .waiting { finishResolve(fade: true) }
                }
            default:
                break
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // Backgrounding tore the tap down (`sceneDidBackground` → `endIntroFrames`);
                // an intro still waiting for its first frame needs it re-armed or the
                // overlay would sit black forever.
                if resolvePhase == .waiting { viewModel.beginIntroFrames() }
                Task { await viewModel.sceneDidActivate() }
            case .background:
                viewModel.sceneDidBackground()
            default:
                break
            }
        }
    }

    // MARK: - Resolve intro

    /// Starts the sweep, once, and only when everything it needs has arrived — the entrance
    /// underway and a first frame to draw. Idempotent and called from every trigger, so
    /// whichever arrives last is the one that starts it (`GifGridItem` shape).
    private func startResolveIfReady() {
        guard resolvePhase == .waiting, hasEntered, !hasCaptured,
              viewModel.previewFrame != nil else { return }

        let duration = motionStore.tuning.cameraRevealTime
        guard !reduceMotion, duration > 0 else {
            finishResolve(fade: false)
            return
        }

        resolvePhase = .running
        // Ended by the clock rather than left to the timeline, so an interruption can never
        // strand a half-resolved overlay across the feed.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            finishResolve(fade: true)
        }
    }

    /// Every terminal path funnels here: the sweep's own clock, a session failure, and the
    /// no-frame fallback timeout. The fade hides the seam between the tapped frames and the
    /// live layer; failure paths skip it.
    private func finishResolve(fade: Bool) {
        guard resolvePhase != .done else { return }
        guard fade else {
            resolvePhase = .done
            viewModel.endIntroFrames()
            return
        }
        withAnimation(.easeOut(duration: 0.12)) { resolveVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            resolvePhase = .done
            viewModel.endIntroFrames()
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

                // The resolve intro, over the feed and under the controls. Before the first
                // frame it is opaque black — indistinguishable from the card behind a
                // not-yet-running feed, so a missing tap costs nothing visually.
                if resolvePhase != .done {
                    CameraResolveOverlay(
                        frame: viewModel.previewFrame,
                        cellSize: motionStore.tuning.cameraRevealCell,
                        duration: motionStore.tuning.cameraRevealTime,
                        running: resolvePhase == .running
                    )
                    .opacity(resolveVisible ? 1 : 0)
                }

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
            // The living gradient inside a transparent Liquid Glass rim *(user's call,
            // 2026-08-26, superseding the spec's flat mint)* — in the camera role, so it wears
            // GRADIENT LAB's camera poles and matches the gallery button it grew out of.
            ZStack {
                ButtonGradientBackground(role: .camera)
                    .clipShape(RoundedRectangle(cornerRadius: AppConstants.Spacing.grid, style: .continuous))
                    .frame(width: 55, height: 55)
                Image("icon-camera-sharp")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .gradientButtonLabel(role: .camera)
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
