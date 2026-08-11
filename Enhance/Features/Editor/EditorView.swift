import SwiftUI

struct EditorView: View {
    @Bindable var viewModel: EditorViewModel
    @Binding var isPresented: Bool
    let namespace: Namespace.ID

    @EnvironmentObject var photoManager: PhotoManager

    /// Phase 1 of the text editor: the keyboard. `textDraft` is the live field, committed to the
    /// overlay on DONE so a cancel can discard cleanly.
    @State private var isEnteringText = false
    @State private var textDraft = ""
    @FocusState private var textFieldFocused: Bool

    private let canvasSize: CGFloat = 325
    private let borderInset: CGFloat = 5
    private let outerRadius: CGFloat = 28
    private var innerRadius: CGFloat { outerRadius - borderInset }
    private var borderedSize: CGFloat { canvasSize + borderInset * 2 }

    /// Gap between the screen edge and the canvas. The carousel spans the full width and
    /// insets its content by this, so cards line up with the canvas at rest while still
    /// being able to scroll out to the edge.
    private let canvasInset: CGFloat = 20

    private let mintGreen = Color.enhanceMint
    private let buttonHeight: CGFloat = 60

    var body: some View {
        ZStack {
            Color(red: 18/255, green: 14/255, blue: 10/255).ignoresSafeArea()

            VStack(spacing: 16) {
                topBar
                canvasSection

                // Removed from the hierarchy rather than faded, so the panel can grow
                // into the space the tabs and card gallery were using.
                //
                // GeometryReader is greedy, so it claims the space a `Spacer` used to
                // absorb and reports it — which is exactly the card gallery's vertical
                // budget. Cards size themselves from it rather than from a constant, so
                // one layout fits every device. In the editing state the panel takes
                // this slot and does the same thing.
                if !viewModel.isEditingEffect {
                    GeometryReader { geo in
                        controlsSection(
                            cardSize: AppConstants.Layout.effectCardSize(forControlsHeight: geo.size.height)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .opacity(viewModel.showControls ? 1 : 0)
                }
                // No `Spacer` in the editing branch. A Spacer and the panel's
                // `.frame(maxHeight: .infinity)` are both fully flexible, so SwiftUI
                // splits the remaining column between them and the panel gets roughly
                // half the space it appears to claim — on a short device that clips the
                // last row straight off the screen.
                

                if viewModel.isEditingEffect {
                    // Same measured-space pattern as the card gallery: GeometryReader is
                    // greedy, so it reports exactly the panel's vertical budget and the
                    // rows size themselves to fit it.
                    GeometryReader { geo in
                        effectDetailPanel(availableHeight: geo.size.height)
                            .frame(width: borderedSize)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    bottomButtons
                        .opacity(viewModel.showControls ? 1 : 0)
                        .frame(width: borderedSize)
                        .padding(.bottom, 16)
                        .transition(.opacity)
                }
            }
            // One animation for the whole swap. The panel moves; the tabs, cards and
            // buttons only fade — a simultaneous vertical move on both halves fights
            // itself and reads as a stutter.
            .animation(
                .spring(response: AppConstants.Animation.standard, dampingFraction: 0.85),
                value: viewModel.isEditingEffect
            )

            if isEnteringText {
                textEntryOverlay
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isEnteringText)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Animation.standard) {
                withAnimation { viewModel.showControls = true }
            }
            viewModel.onSaveComplete = {
                withAnimation(.spring(response: AppConstants.Animation.standard, dampingFraction: 0.8)) {
                    isPresented = false
                }
            }
        }
        .onChange(of: viewModel.selectedAnimatorType) { _, _ in
            viewModel.regenerateIfNeeded()
        }
        .onChange(of: viewModel.selectedModifier) { _, _ in
            viewModel.regenerateIfNeeded()
        }
        .onChange(of: viewModel.selectedVisualEffect) { _, _ in
            viewModel.updatePreviewImage()
            viewModel.regenerateIfNeeded()
        }
        .onChange(of: viewModel.visibleRect) { _, _ in
            guard viewModel.selectedVisualEffect != nil else { return }
            viewModel.updatePreviewImage(debounce: true)
        }
        .onChange(of: viewModel.selectedEffectCategory) { _, newValue in
            viewModel.cancelEditing()
            if newValue == .faceFilters {
                viewModel.detectFacesIfNeeded()
            }
            if newValue == .visualEffects {
                viewModel.generateEffectThumbnails()
            }
        }
        .onChange(of: viewModel.selectedFaceFilter) { _, _ in
            viewModel.updateFaceFilterPreview()
            viewModel.regenerateIfNeeded()
        }
        .onChange(of: viewModel.laserColor) { _, _ in
            viewModel.updateFaceFilterPreview()
            viewModel.regenerateIfNeeded()
        }
        .onChange(of: viewModel.tintColor) { _, _ in
            viewModel.updatePreviewImage()
            viewModel.regenerateIfNeeded()
        }
        // ColorPicker emits on every drag frame of the system colour wheel, so both
        // the undo push and the regeneration are coalesced rather than fired per
        // change. `old` is the pre-change value, which is what an undo snapshot needs.
        .onChange(of: viewModel.gradientStops) { old, _ in
            viewModel.pushUndoCoalesced(previousStops: old)
            viewModel.updatePreviewImage(debounce: true)
            viewModel.scheduleRegenerate()
        }
        .sheet(isPresented: $viewModel.showSaveSheet) {
            saveSheetContent
        }
        .sheet(isPresented: $viewModel.showShareSheet) {
            if let gifData = viewModel.generatedGIF {
                ShareSheet(gifData: gifData)
            } else if let gifURL = viewModel.existingGifURL, let gifData = try? Data(contentsOf: gifURL) {
                ShareSheet(gifData: gifData)
            }
        }
    }

    // MARK: - Effect Detail Panel

    private func effectDetailPanel(availableHeight: CGFloat) -> some View {
        EffectDetailPanel(
            title: viewModel.editingTitle,
            availableHeight: availableHeight,
            rowCount: viewModel.editingRowCount,
            onCancel: { viewModel.cancelEditing() },
            onConfirm: { viewModel.commitEditing() }
        ) {
            editingRows
        }
    }

    /// Rows for whichever effect the panel has open, resolved from the active category.
    @ViewBuilder
    private var editingRows: some View {
        switch viewModel.selectedEffectCategory {
        case .visualEffects:
            if let effect = viewModel.selectedVisualEffect {
                parameterRows(for: effect, colorSelection: $viewModel.tintColor)
            }
        case .faceFilters:
            if let filter = viewModel.selectedFaceFilter {
                parameterRows(for: filter, colorSelection: $viewModel.laserColor)
            }
        case .text:
            // Two rows for V1: COLOR and the preset's tunable. STYLE (SHADOW/BLOCK/OUTLINE) is
            // deliberately not shipped yet — the rasterizer fills one coverage mask with a single
            // colour, so a shadow renders in the text's own colour and a block plate fills solid
            // over the glyphs. Those decorations need a second, contrasting fill pass before they
            // are worth a control. `TextDecoration` stays in the model for that work.
            ParameterPickerRow(label: "COLOR") {
                textColorSwatchContent()
            }
            ParameterSliderRow(
                label: viewModel.textOverlay?.animation.parameterLabel ?? "AMOUNT",
                value: textTuningBinding,
                onCommit: { viewModel.regenerateIfNeeded() },
                valueText: "\(Int((viewModel.textOverlay?.tuning ?? 0.5) * 100))"
            )
        case .zoomEffects:
            // Built directly rather than through `parameterRows`. Speed and pause are
            // *output* settings that shape the whole GIF, not per-effect parameters —
            // keeping them as named view-model properties avoids per-zoom-type storage
            // (switching ZOOM IN -> PULSE would silently reset them) and sidesteps the
            // 0…1 lattice, whose one-step floor cannot express a 0s pause.
            ParameterSliderRow(
                label: "SPEED",
                value: $viewModel.speedUnit,
                onCommit: { viewModel.onParameterDragEnded() },
                valueText: viewModel.speedLabel
            )
            ParameterSliderRow(
                label: "PAUSE",
                value: $viewModel.pauseUnit,
                onCommit: { viewModel.onParameterDragEnded() },
                allowsZero: true,
                valueText: viewModel.pauseLabel
            )
            ParameterPickerRow(label: "MOTION") {
                SegmentedBar(
                    items: ModifierType.allCases,
                    selection: $viewModel.modifierSelection,
                    label: { $0.rawValue }
                )
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 24) {
                // Disabled while the panel is open: it owns history there via its own
                // back/confirm. A global undo could otherwise restore state *older* than
                // the panel's entry snapshot, after which back would restore forward.
                let historyEnabled = !viewModel.isEditingEffect && !viewModel.isTextGestureActive

                if viewModel.hasNonDefaultSettings {
                    Button {
                        viewModel.resetEffects()
                    } label: {
                        Text("RESET")
                            .font(.custom("Silkscreen-Bold", size: 16))
                            .foregroundColor(.white.opacity(historyEnabled ? 1.0 : 0.3))
                    }
                    .disabled(!historyEnabled)
                }

                Button {
                    viewModel.undo()
                } label: {
                    Image("icon-undo")
                        .renderingMode(.template)
                        .foregroundColor(.white.opacity(historyEnabled && viewModel.canUndo ? 1.0 : 0.3))
                }
                .disabled(!historyEnabled || !viewModel.canUndo)

                Button {
                    viewModel.redo()
                } label: {
                    Image("icon-redo")
                        .renderingMode(.template)
                        .foregroundColor(.white.opacity(historyEnabled && viewModel.canRedo ? 1.0 : 0.3))
                }
                .disabled(!historyEnabled || !viewModel.canRedo)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: AppConstants.Animation.standard, dampingFraction: 0.8)) {
                    isPresented = false
                }
            } label: {
                Text("X")
                    .font(.custom("Silkscreen-Regular", size: 24))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 32)
        .padding(.bottom, 8)
    }

    // MARK: - Canvas

    /// Whether the canvas shows the editable photo rather than the rendered GIF.
    ///
    /// FACE FILTERS always needs it, to hit-test face boxes. TEXT needs it **only while the user is
    /// actually editing** — typing, or with the settings panel open, which is when the text is
    /// dragged and scaled. Once the visit is confirmed the GIF takes the canvas back, so ENHANCE
    /// shows the rendered result like every other category. Keeping the live canvas up permanently
    /// under TEXT meant a generated GIF never appeared in the preview at all.
    private var wantsLiveCanvas: Bool {
        if viewModel.selectedEffectCategory == .faceFilters { return true }
        return viewModel.selectedEffectCategory == .text
            && (isEnteringText || viewModel.isEditingEffect)
    }

    private var canvasSection: some View {
        ZStack {
            switch viewModel.content {
            case .existingGif(let url, _, _):
                if wantsLiveCanvas, let source = viewModel.sourceImage {
                    liveCanvas(image: source)
                } else {
                    borderedCanvas {
                        let displayURL = viewModel.generatedGifURL ?? url
                        GIFPreviewView(url: displayURL, isPlaying: viewModel.isPlaying, playbackSpeed: viewModel.playbackSpeed)
                            .frame(width: canvasSize, height: canvasSize)
                    }
                }

            case .newImage(let image):
                if viewModel.isSplit, let gifURL = viewModel.generatedGifURL, !wantsLiveCanvas {
                    borderedCanvas {
                        GIFPreviewView(url: gifURL, isPlaying: viewModel.isPlaying, playbackSpeed: viewModel.playbackSpeed)
                            .frame(width: canvasSize, height: canvasSize)
                    }
                } else {
                    liveCanvas(image: image)
                }
            }
        }
        .overlay(faceStatusOverlay)
        .overlay(regeneratingOverlay)
        .overlay(toastOverlay)
    }

    /// The editable canvas, shared by the face-filter and text categories. Face boxes and the text
    /// overlay are both wired in; each is inert unless its own category is active.
    private func liveCanvas(image: UIImage) -> some View {
        borderedCanvas {
            ImageCanvasView(
                image: viewModel.previewImage ?? image,
                scale: $viewModel.currentScale,
                visibleRect: $viewModel.visibleRect,
                faceOverlays: activeFaceOverlays,
                onFaceSelected: { index in
                    viewModel.pushUndo()
                    HapticService.selection()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleFaceSelection(index)
                    }
                    viewModel.updateFaceFilterPreview()
                },
                textOverlay: $viewModel.textOverlay,
                isTextInteractive: viewModel.selectedEffectCategory == .text,
                onTextGestureBegan: { viewModel.beginTextGesture() },
                onTextGestureEnded: { viewModel.endTextGesture() },
                onRequestTextEditing: { openTextEntry() },
                onInteraction: { viewModel.noteCanvasInteraction() },
                onInteractionEnded: { viewModel.commitZoomCardFraming() }
            )
            .frame(width: canvasSize, height: canvasSize)
        }
    }

    private func borderedCanvas<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            content()
                .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))

            TimelineView(.animation) { timeline in
                let angle = timeline.date.timeIntervalSinceReferenceDate.remainder(dividingBy: 4) * 90
                AngularGradient(
                    colors: [
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
                    ],
                    center: .center,
                    angle: .degrees(angle)
                )
                .frame(width: borderedSize, height: borderedSize)
                .layerEffect(
                    ShaderLibrary.pixellate(.float(CGFloat(8)), .float2(CGSize(width: borderedSize, height: borderedSize))),
                    maxSampleOffset: CGSize(width: 8, height: 8)
                )
                .clipShape(RoundedRectangle(cornerRadius: outerRadius, style: .continuous))
                .reverseMask {
                    RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                        .frame(width: canvasSize, height: canvasSize)
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 22, x: 0, y: 22)
            .allowsHitTesting(false)
        }
        .frame(width: borderedSize, height: borderedSize)
    }

    // MARK: - Controls

    private func controlsSection(cardSize: CGFloat) -> some View {
        VStack(spacing: 8) {
            effectCategoryTabs
                .frame(width: borderedSize)

            switch viewModel.selectedEffectCategory {
            case .zoomEffects:
                VStack(spacing: 8) {
                    zoomEffectsGrid(cardSize: cardSize)
                }
                .transition(.opacity)
            case .visualEffects:
                VStack(spacing: 8) {
                    visualEffectsGrid(cardSize: cardSize)

                }
                .transition(.opacity)
            case .faceFilters:
                VStack(spacing: 8) {
                    faceFiltersGrid(cardSize: cardSize)
                }
                .transition(.opacity)
            case .text:
                VStack(spacing: 8) {
                    textPresetsGrid(cardSize: cardSize)
                }
                .transition(.opacity)
            }

        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.selectedEffectCategory)
    }

    private var bottomButtons: some View {
        Group {
            if case .newImage = viewModel.content {
                actionButtons
            } else {
                saveShareButtons
            }
        }
    }

    // MARK: - Zoom Gallery

    private func zoomEffectsGrid(cardSize: CGFloat) -> some View {
        EffectCarousel(
            items: AnimatorType.allCases,
            scrollTo: viewModel.selectedAnimatorType,
            contentInset: canvasInset
        ) { animType in
            zoomToggle(animType, cardSize: cardSize)
        }
        .onAppear { viewModel.generateZoomPreviewImage() }
    }

    private func zoomToggle(_ animType: AnimatorType, cardSize: CGFloat) -> some View {
        let isActive = viewModel.selectedAnimatorType == animType
        let framing = viewModel.zoomCardFraming

        return EffectCardView(
            // Raw values are mixed case ("Zoom In") unlike every other family.
            title: animType.rawValue.uppercased(),
            isActive: isActive,
            isBlocked: viewModel.isRegenerating,
            size: cardSize,
            background: {
                // The photo cropped to where this zoom type ends, since the three differ
                // by framing rather than by any filter — see ZoomCardFraming. Falls back
                // to the flat fill until the photo has been downscaled for preview.
                if let preview = viewModel.zoomPreviewImage {
                    ZoomCardThumbnail(
                        image: preview,
                        type: animType,
                        zoomScale: framing.scale,
                        zoomCenter: framing.center,
                        size: cardSize
                    )
                    .effectCardScrim(isActive: isActive)
                } else {
                    EffectCardThumbnail(image: nil, isActive: isActive, size: cardSize)
                }
            }
        ) {
            HapticService.selection()
            if viewModel.selectedAnimatorType != animType {
                viewModel.pushUndo()
                viewModel.selectedAnimatorType = animType
            }
            viewModel.beginEditing()
        }
    }

    // MARK: - Text Gallery

    /// The five entrance presets. Selecting one *is* what creates the overlay — there is no
    /// separate ADD TEXT step, matching how selecting any effect card applies that effect (§4).
    private func textPresetsGrid(cardSize: CGFloat) -> some View {
        EffectCarousel(
            items: TextAnimationType.allCases,
            scrollTo: viewModel.textOverlay?.animation,
            contentInset: canvasInset
        ) { preset in
            textPresetCard(preset, cardSize: cardSize)
        }
    }

    private func textPresetCard(_ preset: TextAnimationType, cardSize: CGFloat) -> some View {
        let isActive = viewModel.textOverlay?.animation == preset
        return EffectCardView(
            title: preset.rawValue,
            isActive: isActive,
            isBlocked: viewModel.isRegenerating,
            size: cardSize,
            background: {
                EffectCardThumbnail(image: nil, isActive: isActive, size: cardSize)
            }
        ) {
            HapticService.selection()
            selectTextPreset(preset)
        }
    }

    /// Creates the overlay on first selection (or swaps the animation on later ones), then opens
    /// the keyboard so the first thing the user does is type.
    private func selectTextPreset(_ preset: TextAnimationType) {
        viewModel.pushUndo()
        if var overlay = viewModel.textOverlay {
            overlay.animation = preset
            viewModel.textOverlay = overlay
        } else {
            viewModel.textOverlay = TextOverlay.makeDefault(animation: preset)
        }
        openTextEntry()
    }

    /// Phase 1: the keyboard. Seeds the field from the current overlay and focuses it.
    private func openTextEntry() {
        textDraft = viewModel.textOverlay?.text ?? ""
        isEnteringText = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { textFieldFocused = true }
    }

    /// Phase-1 DONE (Return on the keyboard): commit the typed text and advance to phase 2, the
    /// settings panel. An empty or whitespace-only draft is treated as "never mind" — the overlay
    /// is discarded and the session ends without a panel.
    private func commitTextEntry() {
        textFieldFocused = false
        isEnteringText = false

        guard !textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            viewModel.textOverlay = nil
            return
        }

        if var overlay = viewModel.textOverlay {
            overlay.text = textDraft
            viewModel.textOverlay = overlay
        }
        viewModel.regenerateIfNeeded()
        // Phase 2: COLOR / STYLE / the preset tunable. CONFIRM closes the visit as one undo entry.
        viewModel.beginEditing()
    }

    /// The keyboard phase, presented over the canvas: a single borderless field. Return commits —
    /// its keyboard action label reads DONE — so there is no on-screen button to reach for. The
    /// text just appears on the photo when it is dismissed; the entrance itself is previewed there.
    private var textEntryOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { commitTextEntry() }

            TextField("", text: $textDraft, prompt:
                        Text("TYPE YOUR TEXT").foregroundColor(.white.opacity(0.4)))
                .font(.silkscreenButtonLabel)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .tint(.enhanceMint)
                .focused($textFieldFocused)
                .submitLabel(.done)
                .onSubmit { commitTextEntry() }
                .padding(.horizontal, 40)
                .onChange(of: textDraft) { _, newValue in
                    // No newlines — Return commits — and cap at the overlay's grapheme limit.
                    var cleaned = newValue.replacingOccurrences(of: "\n", with: "")
                    if cleaned.count > TextOverlay.maxGraphemeClusters {
                        cleaned = String(cleaned.prefix(TextOverlay.maxGraphemeClusters))
                    }
                    if cleaned != newValue { textDraft = cleaned }
                }
        }
    }

    // MARK: - Text settings panel bindings

    /// Panel controls edit the overlay in place. No per-change `pushUndo` here: the whole visit is
    /// one edit session (beginEditing → CONFIRM), so `commitEditing` records a single undo entry.
    private var textColorBinding: Binding<TextColorChoice> {
        Binding(
            get: { viewModel.textOverlay?.color ?? .white },
            set: { newValue in
                guard var overlay = viewModel.textOverlay else { return }
                overlay.color = newValue
                viewModel.textOverlay = overlay
                viewModel.regenerateIfNeeded()
            }
        )
    }

    /// The preset's single tunable. Updates the overlay live so the canvas preview reflects it as
    /// the knob moves; the GIF regenerates on drag-end via the row's `onCommit`.
    private var textTuningBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.textOverlay?.tuning ?? 0.5) },
            set: { newValue in
                guard var overlay = viewModel.textOverlay else { return }
                overlay.tuning = CGFloat(newValue)
                viewModel.textOverlay = overlay
            }
        )
    }

    /// Colour swatches for the text overlay — the same shape as `colorSwatchContent`, over the
    /// semantic `TextColorChoice` palette. A faint ring keeps white and black legible on the panel.
    private func textColorSwatchContent() -> some View {
        HStack(spacing: 0) {
            ForEach(TextColorChoice.allCases) { color in
                Spacer(minLength: 0)
                Button {
                    HapticService.light()
                    textColorBinding.wrappedValue = color
                } label: {
                    Circle()
                        .fill(color.swiftUIColor)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                        .overlay(
                            Circle()
                                .stroke(textColorBinding.wrappedValue == color ? mintGreen : .clear, lineWidth: 2)
                                .frame(width: 32, height: 32)
                        )
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Pickers

    /// Colour swatches for a `.tintColor` parameter. Used by visual effects (writing
    /// `tintColor`) and face filters (writing `laserColor`). Content only — the label
    /// column and row height come from `ParameterPickerRow`.
    private func colorSwatchContent(selection: Binding<LaserColor>) -> some View {
        // The zeroed spacing and `minLength` are both load-bearing. The
        // Spacer-on-both-sides pattern distributes the swatches evenly, but a bare
        // `Spacer()` carries its own ~8pt minimum *in addition to* the HStack's default
        // spacing, so six swatches cost 156pt of circles plus ~230pt of irreducible gap.
        // That exceeds the row's width on a 4.7" screen, and because it is an intrinsic
        // minimum rather than a preference, it pushed the whole panel past both edges of
        // the display. At zero, the swatches alone (156pt) set the floor and the Spacers
        // only distribute whatever is left over.
        HStack(spacing: 0) {
            ForEach(LaserColor.allCases) { color in
                Spacer(minLength: 0)
                Button {
                    viewModel.pushUndo()
                    HapticService.light()
                    selection.wrappedValue = color
                } label: {
                    Circle()
                        .fill(color.swiftUIColor)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .stroke(selection.wrappedValue == color ? mintGreen : .clear, lineWidth: 2)
                                .frame(width: 32, height: 32)
                        )
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
    }

    /// Gradient Map stop pickers — three native colour wells, left to right for
    /// shadows → midtones → highlights. The colours themselves make the order obvious
    /// enough without labels.
    ///
    /// Deliberately left unstyled, unlike `colorSwatchContent`'s mint-ringed swatches.
    /// Two attempts at matching that treatment both failed and are recorded in
    /// LEARNINGS (2026-08-07): painting a custom swatch over the well breaks hit
    /// testing, because a `UIColorWell`'s tap target is its own swatch rather than the
    /// SwiftUI frame around it; and merely ringing the well leaves Apple's spectrum
    /// ring visible inside the mint one, which cannot be hidden. Driving
    /// `UIColorPickerViewController` from a plain `Button` instead crashed, since that
    /// controller manages its own presentation and cannot be used as `.sheet` content.
    /// The system well's own affordance is the pragmatic answer here.
    private var gradientStopsContent: some View {
        HStack {
            Spacer()
            ColorPicker("", selection: $viewModel.gradientStops.dark, supportsOpacity: false)
                .labelsHidden()
            Spacer()
            ColorPicker("", selection: $viewModel.gradientStops.mid, supportsOpacity: false)
                .labelsHidden()
            Spacer()
            ColorPicker("", selection: $viewModel.gradientStops.light, supportsOpacity: false)
                .labelsHidden()
            Spacer()
        }
    }

    // MARK: - Declaration-driven parameter rows

    /// Renders one row per declared `EffectParameter`. This is what removes the old
    /// two-control ceiling: adding a parameter to an effect's `parameters` is now the
    /// only change needed for it to appear.
    ///
    /// `colorSelection` is passed in rather than derived because a `.tintColor`
    /// parameter writes `tintColor` for visual effects but `laserColor` for face filters.
    @ViewBuilder
    private func parameterRows<E: ParameterizedEffect>(
        for effect: E,
        colorSelection: Binding<LaserColor>
    ) -> some View {
        ForEach(effect.parameters) { param in
            switch param.kind {
            case .slider:
                // Deliberately no `onBeginDrag: { pushUndo() }`. These rows only exist
                // while the panel is open, and `commitEditing()` already records one
                // entry for the whole visit — a per-drag push on top of that leaves the
                // stack as [dragStart, entry], so the second undo steps the user
                // *forward*. Undo is disabled while the panel is open, so a push here
                // can only corrupt the stack, never help.
                ParameterSliderRow(
                    label: param.label,
                    value: parameterBinding(param, for: effect),
                    onCommit: { viewModel.onParameterDragEnded() }
                )
            case .tintColor:
                ParameterPickerRow(label: param.label) {
                    colorSwatchContent(selection: colorSelection)
                }
            case .gradientStops:
                ParameterPickerRow(label: param.label) {
                    gradientStopsContent
                }
            }
        }
    }

    private func parameterBinding<E: ParameterizedEffect>(
        _ param: EffectParameter,
        for effect: E
    ) -> Binding<Double> {
        Binding(
            get: { viewModel.value(param.id, for: effect, default: param.defaultValue) },
            set: { viewModel.setValue($0, param.id, for: effect) }
        )
    }

    // MARK: - Visual Effects Grid

    private func visualEffectsGrid(cardSize: CGFloat) -> some View {
        EffectCarousel(
            items: VisualEffectType.selectable,
            scrollTo: viewModel.selectedVisualEffect,
            contentInset: canvasInset
        ) { effectType in
            visualEffectToggle(effectType, cardSize: cardSize)
        }
    }

    private func visualEffectToggle(_ effectType: VisualEffectType, cardSize: CGFloat) -> some View {
        EffectCardView(
            title: effectType.rawValue,
            thumbnail: viewModel.effectThumbnails[effectType],
            isActive: viewModel.selectedVisualEffect == effectType,
            isBlocked: viewModel.isRegenerating,
            size: cardSize
        ) {
            HapticService.selection()
            // Tapping the selected effect re-opens its controls; deselecting is the top
            // bar's job (undo / RESET), which is why there is no toggle-off here.
            if viewModel.selectedVisualEffect != effectType {
                viewModel.pushUndo()
                viewModel.selectedVisualEffect = effectType
            }
            viewModel.beginEditing()
        }
    }

    // MARK: - Face Filters Grid

    private func faceFiltersGrid(cardSize: CGFloat) -> some View {
        EffectCarousel(
            items: FaceFilterType.allCases,
            scrollTo: viewModel.selectedFaceFilter,
            contentInset: canvasInset
        ) { filterType in
            faceFilterToggle(filterType, cardSize: cardSize)
        }
    }

    private func faceFilterToggle(_ filterType: FaceFilterType, cardSize: CGFloat) -> some View {
        let noFaces = viewModel.detectedFaces.isEmpty && !viewModel.isDetectingFaces
        let singleFaceBlocked = filterType.requiresSingleFace && viewModel.activeFaces.count != 1

        return EffectCardView(
            title: filterType.rawValue,
            // nil until detection completes, and stays nil when the photo has no
            // faces — where a thumbnail would be meaningless anyway.
            thumbnail: viewModel.faceFilterThumbnails[filterType],
            isActive: viewModel.selectedFaceFilter == filterType,
            isBlocked: viewModel.isRegenerating || noFaces || singleFaceBlocked,
            size: cardSize
        ) {
            HapticService.selection()
            if viewModel.selectedFaceFilter != filterType {
                viewModel.pushUndo()
                viewModel.selectedFaceFilter = filterType
            }
            viewModel.beginEditing()
        }
    }

    // MARK: - Effect Category Icon Tabs

    private var effectCategoryTabs: some View {
        HStack(spacing: 40) {
            effectCategoryIcon("icon-zoom-in", category: .zoomEffects)
            effectCategoryIcon("icon-smile", category: .faceFilters)
            effectCategoryIcon("icon-image", category: .visualEffects)
            effectCategoryIcon("icon-text", category: .text)
        }
        .frame(maxWidth: .infinity)
        .frame(height: AppConstants.Layout.categoryTabsHeight)
    }

    private func effectCategoryIcon(_ assetName: String, category: EffectCategory) -> some View {
        let isActive = viewModel.selectedEffectCategory == category
        return Button {
            guard viewModel.selectedEffectCategory != category else { return }
            viewModel.pushUndo()
            HapticService.selection()
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedEffectCategory = category
            }
        } label: {
            Image(assetName)
                .renderingMode(.template)
                .foregroundColor(isActive ? mintGreen : Color(white: 0.82))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        ZStack {
            if !viewModel.isSplit {
                Button {
                    HapticService.heavy()
                    viewModel.generateGIF()
                } label: {
                    Text(viewModel.enhanceState == .generating ? "GENERATING..." : "ENHANCE")
                        .font(.silkscreenButtonLabel)
                        .foregroundColor(Color(red: 0.09, green: 0.09, blue: 0.09))
                        .frame(maxWidth: .infinity)
                        .frame(height: buttonHeight)
                        .background(SimpleGradientBackground())
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .enhanceButtonAnimation()
                .disabled(viewModel.enhanceState == .generating)
                .opacity(viewModel.enhanceState == .generating ? 0.6 : 1.0)
                .transition(.opacity)
            }

            if viewModel.isSplit {
                saveShareButtons
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: viewModel.isSplit)
    }

    private var saveShareButtons: some View {
        HStack(spacing: 8) {
            if photoManager.isAuthorized {
                Button {
                    if case .existingGif = viewModel.content {
                        viewModel.showSaveSheet = true
                    } else {
                        viewModel.saveGIFToLibrary(photoManager: photoManager)
                    }
                } label: {
                    Text("SAVE")
                        .font(.silkscreenButtonLabel)
                        .foregroundColor(viewModel.isSaveEnabled ? .white : .white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .frame(height: buttonHeight)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(hex: 0x202020).opacity(0.8))
                        )
                }
                .enhanceButtonAnimation()
                .disabled(!viewModel.isSaveEnabled)
            }

            Button {
                viewModel.showShareSheet = true
            } label: {
                Text("SHARE")
                    .font(.silkscreenButtonLabel)
                    .foregroundColor(Color(red: 0.09, green: 0.09, blue: 0.09))
                    .frame(maxWidth: .infinity)
                    .frame(height: buttonHeight)
                    .background(SimpleGradientBackground())
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .enhanceButtonAnimation()
        }
    }

    // MARK: - Save Sheet Content

    private var saveSheetContent: some View {
        BottomSheet(isPresented: $viewModel.showSaveSheet, title: "SELECT AN OPTION") {
            VStack(spacing: 16) {
                Button {
                    viewModel.showSaveSheet = false
                    viewModel.updateOriginalGIF(photoManager: photoManager)
                } label: {
                    Text("UPDATE ORIGINAL GIF")
                        .font(.silkscreenButtonLabel)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(hex: 0x202020).opacity(0.8))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.showSaveSheet = false
                    viewModel.saveGIFToLibrary(photoManager: photoManager)
                } label: {
                    Text("SAVE NEW COPY")
                        .font(.silkscreenButtonLabel)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(hex: 0x202020).opacity(0.8))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    // MARK: - Face Detection Overlay

    /// Face overlay data passed into ImageCanvasView. Empty when not in face filter mode.
    private var activeFaceOverlays: [(id: UUID, rect: CGRect, isSelected: Bool)] {
        guard viewModel.selectedEffectCategory == .faceFilters else { return [] }
        if case .newImage = viewModel.content {
            guard !viewModel.isSplit else { return [] }
        }
        let singleSelected = viewModel.selectedFaceIndex
        return viewModel.detectedFaces.enumerated().map { index, face in
            let isSelected = singleSelected == nil || singleSelected == index
            return (id: face.id, rect: face.normalizedBoundingBox, isSelected: isSelected)
        }
    }

    /// Shows a loading spinner while face detection is in progress.
    private var faceStatusOverlay: some View {
        Group {
            if viewModel.selectedEffectCategory == .faceFilters && !viewModel.isSplit {
                if viewModel.isDetectingFaces {
                    ProgressView()
                        .tint(mintGreen)
                        .frame(width: canvasSize, height: canvasSize)
                }
            }
        }
    }

    // MARK: - Regenerating Overlay

    private var regeneratingOverlay: some View {
        Group {
            if viewModel.isRegenerating {
                RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.4))
                    .frame(width: borderedSize, height: borderedSize)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: AppConstants.Animation.quick), value: viewModel.isRegenerating)
    }

    // MARK: - Toast

    private var toastOverlay: some View {
        Group {
            if viewModel.showSaveMessage {
                toastLabel(viewModel.saveMessage)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { viewModel.showSaveMessage = false }
                        }
                    }
            } else if viewModel.showsZoomHint {
                // `else if`, so a real message always wins the slot. Two pills stacked in
                // the same corner would be worse than either alone — and the case is easy
                // to hit, since tapping ENHANCE without zooming is exactly what this hint
                // exists to prevent.
                toastLabel(EditorViewModel.zoomHintMessage)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: AppConstants.Animation.standard), value: viewModel.showSaveMessage)
        .animation(.easeInOut(duration: AppConstants.Animation.standard), value: viewModel.showsZoomHint)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, AppConstants.Spacing.grid)
    }

    /// Chrome shared by the transient toast and the persistent arrival hint. The hint's
    /// whole point is that it looks like the message ENHANCE would give you, so the two
    /// must not be able to drift apart.
    private func toastLabel(_ message: String) -> some View {
        Text(message)
            .font(.silkscreenBody)
            .foregroundColor(.white)
            // Silkscreen is wide and the canvas is only 325pt, so a longer message would
            // otherwise wrap or overflow rather than shrink.
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, AppConstants.Spacing.grid)
            .padding(.vertical, AppConstants.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black)
            )
    }
}
