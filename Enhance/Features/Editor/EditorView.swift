import SwiftUI

struct EditorView: View {
    @Bindable var viewModel: EditorViewModel
    @Binding var isPresented: Bool
    let namespace: Namespace.ID

    @EnvironmentObject var photoManager: PhotoManager

    /// Looping card previews are decorative motion, so they hold on their settled frame when the
    /// user has asked the system for less of it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Phase 1 of the text editor: `textDraft` is the live field, committed to the overlay on
    /// DONE so a cancel can discard cleanly. Whether the keyboard is up lives on the view model,
    /// because `wantsLiveCanvas` depends on it and that answer must be shared.
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
            Color.surfaceBase.ignoresSafeArea()

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
            // The keyboard slides *over* the editor rather than shoving it upward. SwiftUI's
            // default avoidance lifted the whole column, so ENHANCE and SHARE rode up above the
            // keyboard and stayed tappable while typing. Opting out leaves them where they are,
            // covered by the keyboard, which is what a text-entry sheet should do.
            .ignoresSafeArea(.keyboard, edges: .bottom)

            if viewModel.isEnteringText {
                textEntryOverlay
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.12), value: viewModel.isEnteringText)
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
        .onChange(of: viewModel.pixelShape) { _, _ in
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
            ParameterPickerRow(label: "FILL") {
                SegmentedBar(
                    items: TextFillMode.allCases,
                    selection: textFillModeBinding,
                    label: { $0.rawValue }
                )
            }
            // Unlabelled: the FILL row above already names what these are, and a second label
            // would repeat it while stealing width from the swatches.
            ParameterPickerRow(label: "") {
                if viewModel.textOverlay?.fillMode == .gradient {
                    textGradientSwatchContent()
                } else {
                    textColorSwatchContent()
                }
            }
            // One slot, two possible controls: SLIDE picks a travel direction, GRID picks the
            // origin its fill spreads from. They never both apply.
            if viewModel.textOverlay?.animation.usesDirection == true {
                ParameterPickerRow(label: "FROM") {
                    SegmentedBar(
                        items: TextSlideDirection.allCases,
                        selection: textDirectionBinding,
                        label: { $0.rawValue }
                    )
                }
            } else if viewModel.textOverlay?.animation.usesGridOrigin == true {
                ParameterPickerRow(label: "FROM") {
                    SegmentedBar(
                        items: TextGridOrigin.allCases,
                        selection: textGridOriginBinding,
                        label: { $0.rawValue }
                    )
                }
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
                            .font(.silkscreenSectionTitle)
                            .foregroundColor(historyEnabled ? .textPrimary : .contentInactive)
                    }
                    .disabled(!historyEnabled)
                }

                Button {
                    viewModel.undo()
                } label: {
                    Image("icon-undo")
                        .renderingMode(.template)
                        .foregroundColor(historyEnabled && viewModel.canUndo ? .textPrimary : .contentInactive)
                }
                .disabled(!historyEnabled || !viewModel.canUndo)

                Button {
                    viewModel.redo()
                } label: {
                    Image("icon-redo")
                        .renderingMode(.template)
                        .foregroundColor(historyEnabled && viewModel.canRedo ? .textPrimary : .contentInactive)
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
                    .font(.silkscreenTitle)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 32)
        .padding(.bottom, 8)
    }

    // MARK: - Canvas

    private var canvasSection: some View {
        ZStack {
            switch viewModel.content {
            case .existingGif(let url, _, _):
                if viewModel.showsLiveCanvas, let source = viewModel.sourceImage {
                    liveCanvas(image: source)
                } else {
                    borderedCanvas {
                        let displayURL = viewModel.generatedGifURL ?? url
                        GIFPreviewView(url: displayURL, isPlaying: viewModel.isPlaying, playbackSpeed: viewModel.playbackSpeed)
                            .frame(width: canvasSize, height: canvasSize)
                    }
                }

            case .newImage(let image):
                if !viewModel.showsLiveCanvas, let gifURL = viewModel.generatedGifURL {
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
                onTextGestureBegan: {
                    viewModel.noteTextInteraction()
                    viewModel.beginTextGesture()
                },
                onTextGestureEnded: { viewModel.endTextGesture() },
                onRequestTextEditing: {
                    viewModel.noteTextInteraction()
                    openTextEntry()
                },
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
        .onAppear { viewModel.generateTextThumbnails() }
    }

    private func textPresetCard(_ preset: TextAnimationType, cardSize: CGFloat) -> some View {
        let isActive = viewModel.textOverlay?.animation == preset
        return EffectCardView(
            title: preset.rawValue,
            isActive: isActive,
            isBlocked: viewModel.isRegenerating,
            size: cardSize,
            background: {
                textPresetPreview(preset, isActive: isActive, cardSize: cardSize)
            }
        ) {
            HapticService.selection()
            selectTextPreset(preset)
        }
    }

    /// The card's backdrop: the preset's entrance played on a loop.
    ///
    /// A still cannot tell these presets apart honestly — POP and SPIN both read as "big text" at
    /// their peak, and TYPEWRITER *is* its reveal — so the card plays the frames the view model
    /// pre-rendered. Under Reduce Motion it holds the settled frame instead, and before the frames
    /// arrive it falls back to the plain thumbnail so the carousel never flashes empty.
    @ViewBuilder
    private func textPresetPreview(_ preset: TextAnimationType,
                                   isActive: Bool,
                                   cardSize: CGFloat) -> some View {
        let frames = viewModel.textThumbnailFrames[preset] ?? []

        if frames.isEmpty {
            EffectCardThumbnail(image: nil, isActive: isActive, size: cardSize)
        } else if reduceMotion {
            EffectCardThumbnail(image: frames.last, isActive: isActive, size: cardSize)
        } else {
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let index = Int(elapsed * Self.textPreviewFPS) % frames.count
                EffectCardThumbnail(image: frames[index], isActive: isActive, size: cardSize)
            }
        }
    }

    /// Slow enough to read the reveal, fast enough that the loop does not feel stalled.
    private static let textPreviewFPS: Double = 12

    /// Selecting a preset.
    ///
    /// **Only the first selection opens the keyboard**, because that is the only time there is
    /// nothing to type over. Once words exist, tapping another card is a request to change the
    /// *effect*, not to retype — so it swaps the animation and opens the settings panel, exactly as
    /// tapping a card does in every other category. Double-tapping the text on the canvas is what
    /// reopens the keyboard.
    private func selectTextPreset(_ preset: TextAnimationType) {
        viewModel.pushUndo()
        // Gates the "double tap to edit" hint: it only makes sense once an effect is chosen.
        viewModel.noteTextPresetChosen()

        guard var overlay = viewModel.textOverlay, overlay.isActive else {
            viewModel.textOverlay = TextOverlay.makeDefault(animation: preset)
            openTextEntry()
            return
        }

        overlay.animation = preset
        viewModel.textOverlay = overlay
        viewModel.regenerateIfNeeded()
        viewModel.beginEditing()
    }

    /// Phase 1: the keyboard. Seeds the field from the current overlay and focuses it.
    private func openTextEntry() {
        textDraft = viewModel.textOverlay?.text ?? ""
        viewModel.isEnteringText = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { textFieldFocused = true }
    }

    /// Phase-1 DONE (Return on the keyboard): commit the typed text and advance to phase 2, the
    /// settings panel. An empty or whitespace-only draft is treated as "never mind" — the overlay
    /// is discarded and the session ends without a panel.
    private func commitTextEntry() {
        textFieldFocused = false
        viewModel.isEnteringText = false

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

    /// Solid colour or gradient. Both choices persist independently, so toggling back returns the
    /// colour or the gradient the user last picked rather than resetting it.
    private var textFillModeBinding: Binding<TextFillMode> {
        Binding(
            get: { viewModel.textOverlay?.fillMode ?? .color },
            set: { newValue in
                guard var overlay = viewModel.textOverlay else { return }
                overlay.fillMode = newValue
                viewModel.textOverlay = overlay
                viewModel.regenerateIfNeeded()
            }
        )
    }

    /// The gradient's two endpoints, as native colour wells — the same affordance the Gradient Map
    /// effect uses. Written straight onto the overlay; the model stores components rather than
    /// `Color`, so undo and persistence still work (see `TextGradient`).
    private var textGradientStartBinding: Binding<Color> {
        Binding(
            get: { viewModel.textOverlay?.gradient.startColor ?? TextGradient.default.startColor },
            set: { newValue in
                guard var overlay = viewModel.textOverlay else { return }
                overlay.gradient.startColor = newValue
                viewModel.textOverlay = overlay
                // A colour well emits on every drag frame of the system wheel, so this coalesces
                // rather than kicking off a regeneration per frame.
                viewModel.scheduleRegenerate()
            }
        )
    }

    private var textGradientMidBinding: Binding<Color> {
        Binding(
            get: { viewModel.textOverlay?.gradient.midColor ?? TextGradient.default.midColor },
            set: { newValue in
                guard var overlay = viewModel.textOverlay else { return }
                overlay.gradient.midColor = newValue
                viewModel.textOverlay = overlay
                viewModel.scheduleRegenerate()
            }
        )
    }

    private var textGradientEndBinding: Binding<Color> {
        Binding(
            get: { viewModel.textOverlay?.gradient.endColor ?? TextGradient.default.endColor },
            set: { newValue in
                guard var overlay = viewModel.textOverlay else { return }
                overlay.gradient.endColor = newValue
                viewModel.textOverlay = overlay
                viewModel.scheduleRegenerate()
            }
        )
    }

    /// Three wells, left to right along the ramp — the same three-stop shape as the Gradient Map
    /// effect's row. The colours in the wells are the preview; the canvas shows the real result.
    ///
    /// Zeroed spacing and `minLength: 0` for the same reason `colorSwatchContent` documents: a bare
    /// `Spacer` carries its own intrinsic minimum *on top of* the stack spacing, which on a 4.7"
    /// screen pushed that row past both edges of the display.
    private func textGradientSwatchContent() -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ColorPicker("", selection: textGradientStartBinding, supportsOpacity: false)
                .labelsHidden()
            Spacer(minLength: 0)
            ColorPicker("", selection: textGradientMidBinding, supportsOpacity: false)
                .labelsHidden()
            Spacer(minLength: 0)
            ColorPicker("", selection: textGradientEndBinding, supportsOpacity: false)
                .labelsHidden()
            Spacer(minLength: 0)
        }
    }

    /// SLIDE's entry edge. "UP" means the text travels up into place from below.
    private var textDirectionBinding: Binding<TextSlideDirection> {
        Binding(
            get: { viewModel.textOverlay?.slideDirection ?? .up },
            set: { newValue in
                guard var overlay = viewModel.textOverlay else { return }
                overlay.slideDirection = newValue
                viewModel.textOverlay = overlay
                viewModel.regenerateIfNeeded()
            }
        )
    }

    /// Where GRID's fill starts — top, bottom, or opening outward from the middle.
    private var textGridOriginBinding: Binding<TextGridOrigin> {
        Binding(
            get: { viewModel.textOverlay?.gridOrigin ?? .top },
            set: { newValue in
                guard var overlay = viewModel.textOverlay else { return }
                overlay.gridOrigin = newValue
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

    /// The two PIXELATE cell shapes. Same zero-spacing Spacer distribution as the colour
    /// swatches — see `colorSwatchContent` for why both the spacing and the `minLength`
    /// have to be zero.
    private var pixelShapeContent: some View {
        HStack(spacing: 0) {
            ForEach(PixelShape.allCases) { shape in
                Spacer(minLength: 0)
                Button {
                    viewModel.pushUndo()
                    HapticService.light()
                    viewModel.pixelShape = shape
                } label: {
                    Text(shape.rawValue)
                        .font(.silkscreenBody)
                        .foregroundColor(viewModel.pixelShape == shape ? .enhanceMint : .textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(viewModel.pixelShape == shape ? Color.enhanceMint : .clear,
                                        lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
    }

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
            case .pixelShape:
                ParameterPickerRow(label: param.label) {
                    pixelShapeContent
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
                        .foregroundColor(Color.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: buttonHeight)
                        .background(SimpleGradientBackground())
                        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
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
                        .foregroundColor(viewModel.isSaveEnabled ? .textPrimary : .contentInactive)
                        .frame(maxWidth: .infinity)
                        .frame(height: buttonHeight)
                        .surface(.raised, opacity: 0.8)
                }
                .enhanceButtonAnimation()
                .disabled(!viewModel.isSaveEnabled)
            }

            Button {
                viewModel.showShareSheet = true
            } label: {
                Text("SHARE")
                    .font(.silkscreenButtonLabel)
                    .foregroundColor(Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: buttonHeight)
                    .background(SimpleGradientBackground())
                    .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
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
                        .surface(.raised, opacity: 0.8)
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
                        .surface(.raised, opacity: 0.8)
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
        // Boxes belong to the editable photo, so they follow it rather than guessing from
        // `isSplit` — which stopped meaning "the GIF is showing" once the panel could bring the
        // live canvas back after ENHANCE.
        guard viewModel.showsLiveCanvas else { return [] }
        let singleSelected = viewModel.selectedFaceIndex
        return viewModel.detectedFaces.enumerated().map { index, face in
            let isSelected = singleSelected == nil || singleSelected == index
            return (id: face.id, rect: face.normalizedBoundingBox, isSelected: isSelected)
        }
    }

    /// Shows a loading spinner while face detection is in progress.
    private var faceStatusOverlay: some View {
        Group {
            if viewModel.selectedEffectCategory == .faceFilters, viewModel.showsLiveCanvas {
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
            } else if viewModel.showsTextHint {
                // Same one-slot rule as above. Ranked below the zoom hint because the two cannot
                // both apply — zoom's is `.newImage`-only and pre-generation, this one needs an
                // existing overlay — but the ordering keeps the invariant obvious.
                toastLabel(EditorViewModel.textHintMessage)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: AppConstants.Animation.standard), value: viewModel.showSaveMessage)
        .animation(.easeInOut(duration: AppConstants.Animation.standard), value: viewModel.showsZoomHint)
        .animation(.easeInOut(duration: AppConstants.Animation.standard), value: viewModel.showsTextHint)
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
