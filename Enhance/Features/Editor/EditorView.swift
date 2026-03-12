import SwiftUI

struct EditorView: View {
    @Bindable var viewModel: EditorViewModel
    @Binding var isPresented: Bool
    let namespace: Namespace.ID

    @EnvironmentObject var photoManager: PhotoManager

    private let canvasSize: CGFloat = 325
    private let borderInset: CGFloat = 10
    private let outerRadius: CGFloat = 28
    private var innerRadius: CGFloat { outerRadius - borderInset }
    private var borderedSize: CGFloat { canvasSize + borderInset * 2 }

    private let mintGreen = Color(red: 96/255, green: 255/255, blue: 168/255)
    private let buttonHeight: CGFloat = 60

    var body: some View {
        ZStack {
            Color(red: 18/255, green: 14/255, blue: 10/255).ignoresSafeArea()

            VStack(spacing: 16) {
                topBar
                canvasSection
                controlsSection
                    .opacity(viewModel.showControls ? 1 : 0)
                Spacer(minLength: 0)
            }

        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Animation.standard) {
                withAnimation { viewModel.showControls = true }
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
        .sheet(isPresented: $viewModel.showEffectsSheet) {
            effectsSheetContent
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
        HStack {
            Text(viewModel.existingGifURL != nil ? "EDIT GIF" : "EDIT PHOTO")
                .font(.custom("Silkscreen-Bold", size: 16))
                .foregroundColor(.white)

            Spacer()

            if viewModel.hasNonDefaultSettings {
                Button {
                    viewModel.resetEffects()
                } label: {
                    Text("RESET")
                        .font(.custom("Silkscreen-Regular", size: 16))
                        .foregroundColor(.white)
                }
            }

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
                borderedCanvas {
                    let displayURL = viewModel.generatedGifURL ?? url
                    GIFPreviewView(url: displayURL, isPlaying: viewModel.isPlaying, playbackSpeed: viewModel.playbackSpeed)
                        .frame(width: canvasSize, height: canvasSize)
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
                            visibleRect: $viewModel.visibleRect
                        )
                        .frame(width: canvasSize, height: canvasSize)
                    }
                }
            }
        }
        .overlay(regeneratingOverlay)
        .overlay(toastOverlay)
    }

    private func borderedCanvas<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            content()
                .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))

            SimpleGradientBackground()
                .frame(width: borderedSize, height: borderedSize)
                .mask(
                    RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                        .frame(width: borderedSize, height: borderedSize)
                )
                .reverseMask {
                    RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                        .frame(width: canvasSize, height: canvasSize)
                }
                .shadow(color: .black.opacity(0.15), radius: 22, x: 0, y: 22)
                .allowsHitTesting(false)
        }
        .frame(width: borderedSize, height: borderedSize)
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 8) {
            effectCategoryRow

            if viewModel.selectedEffectCategory == .zoomEffects {
                zoomControlsBars
                    .transition(.opacity)
            } else {
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
                    }
                }
                .transition(.opacity)
            }

            if case .newImage = viewModel.content {
                actionButtons
                    .padding(.top, 4)
            } else {
                saveShareButtons
                    .padding(.top, 4)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.selectedEffectCategory)
        .frame(width: borderedSize)
    }

    private var zoomControlsBars: some View {
        Group {
            SegmentedBar(
                items: AnimatorType.allCases,
                selection: $viewModel.selectedAnimatorType,
                label: { $0.rawValue.uppercased() }
            )
            .disabled(viewModel.isRegenerating)

            SegmentedBar(
                items: ModifierType.allCases,
                selection: $viewModel.selectedModifier,
                label: { $0.rawValue }
            )
            .disabled(viewModel.isRegenerating)

            speedPauseRow
        }
    }

    private var speedPauseRow: some View {
        HStack(spacing: 8) {
            Button {
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
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(VisualEffectType.allCases) { effectType in
                visualEffectToggle(effectType)
            }
        }
    }

    private func visualEffectToggle(_ effectType: VisualEffectType) -> some View {
        let isActive = viewModel.selectedVisualEffect == effectType
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedVisualEffect = isActive ? nil : effectType
            }
        } label: {
            Text(effectType.rawValue)
                .font(.silkscreenControl)
                .foregroundColor(isActive ? mintGreen : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isActive ? mintGreen.opacity(0.08) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                        let newIntensity = max(0.05, min(1.0, value.location.x / geo.size.width))
                        viewModel.effectIntensity = newIntensity
                    }
                    .onEnded { _ in
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
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(mintGreen.opacity(0.3))
                        .frame(width: fillWidth)

                    Spacer(minLength: 0)
                }

                VStack(spacing: 2) {
                    Text("SIZE")
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
                        let newSize = max(0.05, min(1.0, value.location.x / geo.size.width))
                        viewModel.effectSize = newSize
                    }
                    .onEnded { _ in
                        viewModel.onSizeDragEnded()
                    }
            )
        }
        .frame(height: 60)
        .animation(.easeOut(duration: 0.1), value: viewModel.effectSize)
    }

    // MARK: - Effect Category Dropdown

    private var effectCategoryRow: some View {
        Button {
            viewModel.showEffectsSheet = true
        } label: {
            HStack(spacing: 10) {
                Spacer()
                Text(viewModel.selectedEffectCategory.rawValue)
                    .font(.silkscreenControl)
                    .foregroundColor(.white)
                TriangleDown()
                    .fill(.white)
                    .frame(width: 8, height: 6)
                Spacer()
            }
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        ZStack {
            if !viewModel.isSplit {
                Button {
                    viewModel.generateGIF()
                } label: {
                    Text(viewModel.enhanceState == .generating ? "GENERATING..." : "ENHANCE")
                        .font(.silkscreenButtonLabel)
                        .foregroundColor(.white)
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

            Button {
                viewModel.showShareSheet = true
            } label: {
                Text("SHARE")
                    .font(.silkscreenButtonLabel)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: buttonHeight)
                    .background(SimpleGradientBackground())
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .enhanceButtonAnimation()
        }
    }

    // MARK: - Effects Sheet Content

    private var effectsSheetContent: some View {
        BottomSheet(isPresented: $viewModel.showEffectsSheet, title: "SELECT EFFECT") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(EffectCategory.allCases) { category in
                    let isActive = viewModel.selectedEffectCategory == category
                    Button {
                        viewModel.selectedEffectCategory = category
                        viewModel.showEffectsSheet = false
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.rawValue)
                                .font(.custom("Silkscreen-Regular", size: 16))
                                .foregroundColor(isActive ? mintGreen : .white)

                            Text(categorySubtitle(for: category))
                                .font(.custom("Silkscreen-Regular", size: 16))
                                .foregroundColor(isActive ? mintGreen.opacity(0.5) : .white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 16)
        }
    }

    private func categorySubtitle(for category: EffectCategory) -> String {
        switch category {
        case .zoomEffects:
            var parts: [String] = [viewModel.selectedAnimatorType.rawValue.uppercased()]
            if viewModel.selectedModifier != .straight {
                parts.append(viewModel.selectedModifier.rawValue)
            }
            if viewModel.playbackSpeed != 1.0 {
                parts.append(viewModel.speedLabel + " SPEED")
            }
            if viewModel.pauseDuration != 1 {
                parts.append("\(viewModel.pauseDuration)S PAUSE")
            }
            return parts.joined(separator: " - ")
        case .visualEffects:
            guard let effect = viewModel.selectedVisualEffect else { return "NONE" }
            if effect.supportsSizeControl {
                return "\(effect.rawValue) - \(viewModel.intensityLabel) - \(viewModel.sizeLabel)"
            }
            return "\(effect.rawValue) - \(viewModel.intensityLabel)"
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

// MARK: - Triangle Shape

private struct TriangleDown: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
