import SwiftUI

struct EditorView: View {
    @Bindable var viewModel: EditorViewModel
    @Binding var isPresented: Bool
    let namespace: Namespace.ID

    @EnvironmentObject var photoManager: PhotoManager

    private let canvasSize: CGFloat = 325
    private let borderInset: CGFloat = 5
    private let outerRadius: CGFloat = 28
    private var innerRadius: CGFloat { outerRadius - borderInset }
    private var borderedSize: CGFloat { canvasSize + borderInset * 2 }

    private let mintGreen = Color(red: 96/255, green: 255/255, blue: 168/255)
    private let buttonHeight: CGFloat = 60
    @State private var sliderUndoPushed = false

    var body: some View {
        ZStack {
            Color(red: 18/255, green: 14/255, blue: 10/255).ignoresSafeArea()

            VStack(spacing: 16) {
                topBar
                canvasSection
                controlsSection
                    .opacity(viewModel.showControls ? 1 : 0)
                Spacer(minLength: 0)
                bottomButtons
                    .opacity(viewModel.showControls ? 1 : 0)
                    .frame(width: borderedSize)
                    .padding(.bottom, 16)
            }

        }
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
            guard !viewModel.isRegenerating else { return }
            if case .existingGif = viewModel.content {
                viewModel.hasModifiedSettings = true
                viewModel.regenerateGIF()
            } else if viewModel.isSplit {
                viewModel.regenerateGIF()
            }
        }
        .onChange(of: viewModel.selectedModifier) { _, _ in
            guard !viewModel.isRegenerating else { return }
            if case .existingGif = viewModel.content {
                viewModel.hasModifiedSettings = true
                viewModel.regenerateGIF()
            } else if viewModel.isSplit {
                viewModel.regenerateGIF()
            }
        }
        .onChange(of: viewModel.playbackSpeed) { _, _ in
            guard !viewModel.isRegenerating else { return }
            if case .existingGif = viewModel.content {
                viewModel.hasModifiedSettings = true
                viewModel.regenerateGIF()
            } else if viewModel.isSplit {
                viewModel.regenerateGIF()
            }
        }
        .onChange(of: viewModel.selectedVisualEffect) { _, _ in
            viewModel.updatePreviewImage()
            guard !viewModel.isRegenerating else { return }
            if case .existingGif = viewModel.content {
                viewModel.hasModifiedSettings = true
                viewModel.regenerateGIF()
            } else if viewModel.isSplit {
                viewModel.regenerateGIF()
            }
        }
        .onChange(of: viewModel.pauseDuration) { _, _ in
            guard !viewModel.isRegenerating else { return }
            if case .existingGif = viewModel.content {
                viewModel.hasModifiedSettings = true
                viewModel.regenerateGIF()
            } else if viewModel.isSplit {
                viewModel.regenerateGIF()
            }
        }
        .onChange(of: viewModel.visibleRect) { _, _ in
            guard viewModel.selectedVisualEffect != nil else { return }
            viewModel.updatePreviewImage(debounce: true)
        }
        .onChange(of: viewModel.selectedEffectCategory) { _, newValue in
            if newValue == .faceFilters {
                viewModel.detectFacesIfNeeded()
            }
            if newValue == .visualEffects {
                viewModel.generateEffectThumbnails()
            }
        }
        .onChange(of: viewModel.selectedFaceFilter) { _, _ in
            viewModel.updateFaceFilterPreview()
            guard !viewModel.isRegenerating else { return }
            if case .existingGif = viewModel.content {
                viewModel.hasModifiedSettings = true
                viewModel.regenerateGIF()
            } else if viewModel.isSplit {
                viewModel.regenerateGIF()
            }
        }
        .onChange(of: viewModel.laserColor) { _, _ in
            viewModel.updateFaceFilterPreview()
            guard !viewModel.isRegenerating else { return }
            if case .existingGif = viewModel.content {
                viewModel.hasModifiedSettings = true
                viewModel.regenerateGIF()
            } else if viewModel.isSplit {
                viewModel.regenerateGIF()
            }
        }
        .onChange(of: viewModel.tintColor) { _, _ in
            viewModel.updatePreviewImage()
            guard !viewModel.isRegenerating else { return }
            if case .existingGif = viewModel.content {
                viewModel.hasModifiedSettings = true
                viewModel.regenerateGIF()
            } else if viewModel.isSplit {
                viewModel.regenerateGIF()
            }
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

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 24) {
                if viewModel.hasNonDefaultSettings {
                    Button {
                        viewModel.resetEffects()
                    } label: {
                        Text("RESET")
                            .font(.custom("Silkscreen-Bold", size: 16))
                            .foregroundColor(.white)
                    }
                }

                Button {
                    viewModel.undo()
                } label: {
                    Image("icon-undo")
                        .renderingMode(.template)
                        .foregroundColor(.white.opacity(viewModel.canUndo ? 1.0 : 0.3))
                }
                .disabled(!viewModel.canUndo)

                Button {
                    viewModel.redo()
                } label: {
                    Image("icon-redo")
                        .renderingMode(.template)
                        .foregroundColor(.white.opacity(viewModel.canRedo ? 1.0 : 0.3))
                }
                .disabled(!viewModel.canRedo)
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

    private var canvasSection: some View {
        ZStack {
            switch viewModel.content {
            case .existingGif(let url, _, _):
                if viewModel.selectedEffectCategory == .faceFilters,
                   let source = viewModel.sourceImage {
                    borderedCanvas {
                        ImageCanvasView(
                            image: viewModel.previewImage ?? source,
                            scale: $viewModel.currentScale,
                            visibleRect: $viewModel.visibleRect,
                            faceOverlays: activeFaceOverlays,
                            onFaceSelected: { index in
                                viewModel.pushUndo()
                                HapticService.selection()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if viewModel.selectedFaceIndex == index {
                                        viewModel.selectedFaceIndex = nil
                                        viewModel.clearSingleFaceFilterIfNeeded()
                                    } else {
                                        viewModel.selectedFaceIndex = index
                                    }
                                }
                                viewModel.updateFaceFilterPreview()
                            }
                        )
                        .frame(width: canvasSize, height: canvasSize)
                    }
                } else {
                    borderedCanvas {
                        let displayURL = viewModel.generatedGifURL ?? url
                        GIFPreviewView(url: displayURL, isPlaying: viewModel.isPlaying, playbackSpeed: viewModel.playbackSpeed)
                            .frame(width: canvasSize, height: canvasSize)
                    }
                }

            case .newImage(let image):
                if viewModel.isSplit, let gifURL = viewModel.generatedGifURL {
                    borderedCanvas {
                        GIFPreviewView(url: gifURL, isPlaying: viewModel.isPlaying, playbackSpeed: viewModel.playbackSpeed)
                            .frame(width: canvasSize, height: canvasSize)
                    }
                } else {
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
                                    if viewModel.selectedFaceIndex == index {
                                        viewModel.selectedFaceIndex = nil
                                        viewModel.clearSingleFaceFilterIfNeeded()
                                    } else {
                                        viewModel.selectedFaceIndex = index
                                    }
                                }
                                viewModel.updateFaceFilterPreview()
                            }
                        )
                        .frame(width: canvasSize, height: canvasSize)
                    }
                }
            }
        }
        .overlay(faceStatusOverlay)
        .overlay(regeneratingOverlay)
        .overlay(toastOverlay)
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

    private var controlsSection: some View {
        VStack(spacing: 8) {
            effectCategoryTabs

            switch viewModel.selectedEffectCategory {
            case .zoomEffects:
                zoomControlsBars
                    .transition(.opacity)
            case .visualEffects:
                VStack(spacing: 8) {
                    visualEffectsGrid

                    if let effect = viewModel.selectedVisualEffect {
                        if effect.supportsSizeControl {
                            HStack(spacing: 8) {
                                intensitySlider
                                sizeSlider
                            }
                            .transition(.opacity)
                        } else {
                            intensitySlider
                                .transition(.opacity)
                        }

                        switch effect.colorPickerKind {
                        case .tintColor:
                            colorSwatchRow(selection: $viewModel.tintColor)
                                .transition(.opacity)
                        case .gradientStops:
                            gradientStopsPicker
                                .transition(.opacity)
                        case .none:
                            EmptyView()
                        }
                    }
                }
                .transition(.opacity)
            case .faceFilters:
                VStack(spacing: 8) {
                    faceFiltersGrid

                    if let filter = viewModel.selectedFaceFilter {
                        if filter.supportsSecondSlider {
                            HStack(spacing: 8) {
                                faceFilterIntensitySlider
                                faceFilterSecondSlider
                            }
                            .transition(.opacity)
                        } else {
                            faceFilterIntensitySlider
                                .transition(.opacity)
                        }

                        if filter == .lazerEyes {
                            colorSwatchRow(selection: $viewModel.laserColor)
                                .transition(.opacity)
                        }
                    }
                }
                .transition(.opacity)
            }

        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.selectedEffectCategory)
        .frame(width: borderedSize)
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

    private var zoomControlsBars: some View {
        Group {
            HStack(spacing: 8) {
                ForEach(AnimatorType.allCases) { animType in
                    zoomToggle(animType)
                }
            }
            .disabled(viewModel.isRegenerating)

            HStack(spacing: 8) {
                ForEach(ModifierType.allCases) { modType in
                    modifierToggle(modType)
                }
            }
            .disabled(viewModel.isRegenerating)

            speedPauseRow
        }
    }

    private func zoomToggle(_ animType: AnimatorType) -> some View {
        let isActive = viewModel.selectedAnimatorType == animType
        return Button {
            viewModel.pushUndo()
            HapticService.light()
            withAnimation(.easeOut(duration: AppConstants.Animation.quick)) {
                viewModel.selectedAnimatorType = isActive ? nil : animType
            }
        } label: {
            Text(animType.rawValue.uppercased())
                .font(.silkscreenControl)
                .foregroundColor(isActive ? mintGreen : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isActive ? Color(red: 100/255, green: 148/255, blue: 122/255).opacity(0.7) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isActive ? mintGreen : .clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    private func modifierToggle(_ modType: ModifierType) -> some View {
        let isActive = viewModel.selectedModifier == modType
        return Button {
            viewModel.pushUndo()
            HapticService.light()
            withAnimation(.easeOut(duration: AppConstants.Animation.quick)) {
                viewModel.selectedModifier = isActive ? nil : modType
            }
        } label: {
            Text(modType.rawValue)
                .font(.silkscreenControl)
                .foregroundColor(isActive ? mintGreen : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isActive ? Color(red: 100/255, green: 148/255, blue: 122/255).opacity(0.7) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isActive ? mintGreen : .clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pickers

    /// Shared colour swatch row. Used by visual effects (writing `tintColor`) and
    /// face filters (writing `laserColor`) — previously two near-identical copies.
    private func colorSwatchRow(selection: Binding<LaserColor>) -> some View {
        HStack {
            ForEach(LaserColor.allCases) { color in
                Spacer()
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
                Spacer()
            }
        }
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    /// Gradient Map stop pickers — three native `ColorPicker`s for unrestricted
    /// colour choice. Left to right is shadows → midtones → highlights, which the
    /// swatch colours themselves make obvious enough without labels.
    private var gradientStopsPicker: some View {
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
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var speedPauseRow: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.pushUndo()
                HapticService.light()
                viewModel.cycleSpeed()
            } label: {
                VStack(spacing: 2) {
                    Text("SPEED")
                        .font(.silkscreenControl)
                        .foregroundColor(.white)
                    Text(viewModel.speedLabel)
                        .font(.silkscreenControl)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(hex: 0x202020))
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRegenerating)

            Button {
                viewModel.pushUndo()
                HapticService.light()
                viewModel.cyclePause()
            } label: {
                VStack(spacing: 2) {
                    Text("PAUSE")
                        .font(.silkscreenControl)
                        .foregroundColor(.white)
                    Text(viewModel.pauseLabel)
                        .font(.silkscreenControl)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(hex: 0x202020))
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRegenerating)
        }
    }

    // MARK: - Visual Effects Grid

    private var visualEffectsGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VisualEffectType.selectable) { effectType in
                        visualEffectToggle(effectType)
                            .id(effectType)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
            }
            .onAppear {
                if let selected = viewModel.selectedVisualEffect {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(selected, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func visualEffectToggle(_ effectType: VisualEffectType) -> some View {
        let isActive = viewModel.selectedVisualEffect == effectType
        let thumbnail = viewModel.effectThumbnails[effectType]
        return Button {
            viewModel.pushUndo()
            HapticService.light()
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedVisualEffect = isActive ? nil : effectType
            }
        } label: {
            Text(effectType.rawValue)
                .font(.silkscreenControl)
                .foregroundColor(isActive ? mintGreen : .white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 16)
                .frame(height: 60)
                .background(
                    GeometryReader { geo in
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .overlay(Color.black.opacity(isActive ? 0.3 : 0.5))
                        } else {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(isActive ? Color(hex: 0x323232) : Color.white.opacity(0.04))
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isActive ? mintGreen : .clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRegenerating)
    }

    // MARK: - Intensity Slider

    private var intensitySlider: some View {
        GeometryReader { geo in
            let fillWidth = geo.size.width * viewModel.effectIntensity

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: 0x323232))

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(mintGreen.opacity(0.3))
                        .frame(width: fillWidth)

                    Spacer(minLength: 0)
                }

                VStack(spacing: 2) {
                    Text("INTENSITY")
                        .font(.silkscreenControl)
                        .foregroundColor(mintGreen)
                    Text(viewModel.intensityLabel)
                        .font(.silkscreenControl)
                        .foregroundColor(mintGreen)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !sliderUndoPushed {
                            viewModel.pushUndo()
                            sliderUndoPushed = true
                        }
                        let newIntensity = max(0.05, min(1.0, value.location.x / geo.size.width))
                        viewModel.effectIntensity = newIntensity
                    }
                    .onEnded { _ in
                        sliderUndoPushed = false
                        viewModel.onIntensityDragEnded()
                    }
            )
        }
        .frame(height: 60)
        .animation(.easeOut(duration: 0.1), value: viewModel.effectIntensity)
    }

    // MARK: - Size Slider

    private var sizeSlider: some View {
        GeometryReader { geo in
            let fillWidth = geo.size.width * viewModel.effectSize

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: 0x323232))

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(mintGreen.opacity(0.3))
                        .frame(width: fillWidth)

                    Spacer(minLength: 0)
                }

                VStack(spacing: 2) {
                    Text(viewModel.selectedVisualEffect?.secondSliderLabel ?? "SIZE")
                        .font(.silkscreenControl)
                        .foregroundColor(mintGreen)
                    Text(viewModel.sizeLabel)
                        .font(.silkscreenControl)
                        .foregroundColor(mintGreen)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !sliderUndoPushed {
                            viewModel.pushUndo()
                            sliderUndoPushed = true
                        }
                        let newSize = max(0.05, min(1.0, value.location.x / geo.size.width))
                        viewModel.effectSize = newSize
                    }
                    .onEnded { _ in
                        sliderUndoPushed = false
                        viewModel.onSizeDragEnded()
                    }
            )
        }
        .frame(height: 60)
        .animation(.easeOut(duration: 0.1), value: viewModel.effectSize)
    }

    // MARK: - Face Filters Grid

    private var faceFiltersGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FaceFilterType.allCases) { filterType in
                        faceFilterToggle(filterType)
                            .id(filterType)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
            }
            .onAppear {
                if let selected = viewModel.selectedFaceFilter {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(selected, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func faceFilterToggle(_ filterType: FaceFilterType) -> some View {
        let isActive = viewModel.selectedFaceFilter == filterType
        let noFaces = viewModel.detectedFaces.isEmpty && !viewModel.isDetectingFaces
        let singleFaceBlocked = filterType.requiresSingleFace && viewModel.activeFaces.count != 1
        let isBlocked = noFaces || singleFaceBlocked
        return Button {
            viewModel.pushUndo()
            HapticService.light()
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedFaceFilter = isActive ? nil : filterType
            }
        } label: {
            Text(filterType.rawValue)
                .font(.silkscreenControl)
                .foregroundColor(isActive ? mintGreen : .white)
                .padding(.horizontal, 16)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isActive ? Color(hex: 0x323232) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isActive ? mintGreen : .clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRegenerating || isBlocked)
        .opacity(isBlocked ? 0.35 : 1.0)
    }

    // MARK: - Face Filter Intensity Slider

    private var faceFilterIntensitySlider: some View {
        GeometryReader { geo in
            let fillWidth = geo.size.width * viewModel.faceFilterIntensity

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: 0x323232))

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(mintGreen.opacity(0.3))
                        .frame(width: fillWidth)

                    Spacer(minLength: 0)
                }

                VStack(spacing: 2) {
                    Text(viewModel.faceFilterSliderLabel)
                        .font(.silkscreenControl)
                        .foregroundColor(mintGreen)
                    Text(viewModel.faceFilterIntensityLabel)
                        .font(.silkscreenControl)
                        .foregroundColor(mintGreen)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !sliderUndoPushed {
                            viewModel.pushUndo()
                            sliderUndoPushed = true
                        }
                        let newVal = max(0.05, min(1.0, value.location.x / geo.size.width))
                        viewModel.faceFilterIntensity = newVal
                    }
                    .onEnded { _ in
                        sliderUndoPushed = false
                        viewModel.onFaceFilterIntensityDragEnded()
                    }
            )
        }
        .frame(height: 60)
        .animation(.easeOut(duration: 0.1), value: viewModel.faceFilterIntensity)
    }

    // MARK: - Face Filter Second Slider

    private var faceFilterSecondSlider: some View {
        GeometryReader { geo in
            let fillWidth = geo.size.width * viewModel.faceFilterSpeed

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: 0x323232))

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(mintGreen.opacity(0.3))
                        .frame(width: fillWidth)

                    Spacer(minLength: 0)
                }

                VStack(spacing: 2) {
                    Text(viewModel.selectedFaceFilter?.secondSliderLabel ?? "")
                        .font(.silkscreenControl)
                        .foregroundColor(mintGreen)
                    Text(viewModel.faceFilterSecondLabel)
                        .font(.silkscreenControl)
                        .foregroundColor(mintGreen)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !sliderUndoPushed {
                            viewModel.pushUndo()
                            sliderUndoPushed = true
                        }
                        let newVal = max(0.05, min(1.0, value.location.x / geo.size.width))
                        viewModel.faceFilterSpeed = newVal
                    }
                    .onEnded { _ in
                        sliderUndoPushed = false
                        viewModel.onFaceFilterSpeedDragEnded()
                    }
            )
        }
        .frame(height: 60)
        .animation(.easeOut(duration: 0.1), value: viewModel.faceFilterSpeed)
    }

    // MARK: - Effect Category Icon Tabs

    private var effectCategoryTabs: some View {
        HStack(spacing: 48) {
            effectCategoryIcon("icon-zoom-in", category: .zoomEffects)
            effectCategoryIcon("icon-smile", category: .faceFilters)
            effectCategoryIcon("icon-image", category: .visualEffects)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 42)
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
                Text(viewModel.saveMessage)
                    .font(.silkscreenBody)
                    .foregroundColor(.white)
                    .padding(.horizontal, AppConstants.Spacing.grid)
                    .padding(.vertical, AppConstants.Spacing.small)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black)
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { viewModel.showSaveMessage = false }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: AppConstants.Animation.standard), value: viewModel.showSaveMessage)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, AppConstants.Spacing.grid)
    }
}
