import SwiftUI
import Photos
import PhotosUI
import UniformTypeIdentifiers

struct GalleryView: View {
    @EnvironmentObject private var photoManager: PhotoManager
    @State private var isEditorPresented = false
    @State private var editorViewModel: EditorViewModel?
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var isSelectMode = false
    @State private var selectedIndices: Set<Int> = []
    @State private var showDeleteConfirmation = false
    @State private var gridScale: CGFloat = 1.0
    @State private var lastGridScale: CGFloat = 1.0
    @State private var isPinching = false
    @State private var showCopiedToast = false
    @State private var showSettings = false
    @AppStorage("autoPlayGifs") private var autoPlayGifs = true
    @AppStorage("exportFormat") private var exportFormat = "gif"
    @Namespace private var animation

    private var gridColumns: [GridItem] {
        let count = gridColumnCount
        return (0..<count).map { i in
            GridItem(.flexible(), spacing: i < count - 1 ? 10 : 0)
        }
    }

    private var gridColumnCount: Int {
        if gridScale < 1.3 { return 3 }
        if gridScale < 2.0 { return 2 }
        return 1
    }

    
    var body: some View {
        ZStack {
            Color(hex: 0x171717).ignoresSafeArea()
            
            VStack(spacing: 0) {
                if !photoManager.hasLoadedGifs {
                    Spacer()
                } else if photoManager.myGifs.isEmpty || photoManager.myGifURLs.isEmpty {
                    nuxHeader
                    nuxView
                } else {
                    galleryContent
                }
            }
        }
        .preferredColorScheme(.dark)
        .overlay { editorOverlay }
        .overlay { loadingOverlay }
        .overlay(alignment: .top) {
            if showCopiedToast {
                Text("COPIED TO CLIPBOARD")
                    .font(.silkscreenControl)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: 0x202020).opacity(0.95))
                    )
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            isLoadingPhoto = true
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        isLoadingPhoto = false
                        selectedPhotoItem = nil
                        selectPhoto(image)
                    }
                } else {
                    await MainActor.run {
                        isLoadingPhoto = false
                        selectedPhotoItem = nil
                        errorMessage = "Could not load the selected photo."
                        showErrorAlert = true
                    }
                }
            }
        }
        .onAppear {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if status == .notDetermined {
                photoManager.requestAuthorization()
            } else {
                photoManager.checkAuthorizationStatus()
            }
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("An Error Occurred"),
                message: Text(errorMessage ?? "Something went wrong."),
                dismissButton: .default(Text("OK")) { errorMessage = nil }
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(isPresented: $showSettings, autoPlayGifs: $autoPlayGifs)
        }
        .alert("Delete \(selectedIndices.count) GIF\(selectedIndices.count == 1 ? "" : "s")?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelectedGifs() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the selected GIFs from your photo library.")
        }


    }
    
    // MARK: - NUX Header
    
    private var nuxHeader: some View {
        HStack {
            Text("ENHANCE")
                .font(.custom("Silkscreen-Bold", size: 16))
                .foregroundColor(.white)

            Spacer()

            Button { showSettings = true } label: {
                Image("icon-settings")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 17)
        .padding(.top, 32)
        .padding(.bottom, 8)
    }
    
    // MARK: - NUX (First-Run Empty State)
    
    private var nuxView: some View {
        VStack {
            Spacer()
            
            nuxStaircaseIcon
                .padding(.bottom, 40)
            
            Spacer()
            
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Text("CREATE YOUR FIRST GIF")
                    .font(.custom("Silkscreen-Regular", size: 17))
                    .foregroundColor(Color(red: 0.09, green: 0.09, blue: 0.09))
                    .frame(width: 361, height: 60)
                    .background(
                        SimpleGradientBackground()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 36)
        }
    }
    
    private var nuxStaircaseIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: 0x0D0B08))
                .frame(width: 224, height: 224)
            
            StaircaseSquares()
        }
    }
    
    // MARK: - Gallery Content (with GIFs)
    
    // MARK: - Gallery Header
    
    private var galleryHeader: some View {
        HStack {
            if isSelectMode {
                Text("\(selectedIndices.count) PHOTOS SELECTED")
                    .font(.custom("Silkscreen-Bold", size: 16))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
            } else {
                let count = min(photoManager.myGifs.count, photoManager.myGifURLs.count)
                Text("MY GIFS (\(count))")
                    .font(.custom("Silkscreen-Bold", size: 16))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
            }

            Spacer()

            if isSelectMode {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        exitSelectMode()
                    }
                } label: {
                    Text("X")
                        .font(.custom("Silkscreen-Regular", size: 24))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            } else {
                Button { showSettings = true } label: {
                    Image("icon-settings")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 32)
        .padding(.bottom, 8)
    }
    
    private var galleryContent: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                galleryHeader
                gridLayer
            }
            .simultaneousGesture(
                isSelectMode ? nil : MagnificationGesture()
                    .onChanged { value in
                        isPinching = true
                        let newScale = min(max(1.0, lastGridScale * value), 2.2)
                        gridScale = newScale
                    }
                    .onEnded { value in
                        let finalScale = min(max(1.0, lastGridScale * value), 2.2)

                        let snapped: CGFloat
                        if finalScale < 1.3 { snapped = 1.0 }
                        else if finalScale < 2.0 { snapped = 1.5 }
                        else { snapped = 2.0 }

                        HapticService.selection()
                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86)) {
                            gridScale = snapped
                        }
                        lastGridScale = snapped
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isPinching = false
                        }
                    }
            )

            floatingBottomBar
        }
    }
    
    private var gridLayer: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 16)

                LazyVGrid(columns: gridColumns, spacing: 10) {
                    let safeCount = min(photoManager.myGifs.count, photoManager.myGifURLs.count)
                    ForEach(0..<safeCount, id: \.self) { index in
                        if let url = photoManager.myGifURLs[safe: index] {
                            GifGridItem(
                                url: url, index: index,
                                namespace: animation,
                                onTap: {
                                    guard !isPinching else { return }
                                    if isSelectMode {
                                        toggleSelection(at: index)
                                    } else {
                                        selectGif(at: index)
                                    }
                                },
                                isSelected: selectedIndices.contains(index),
                                autoPlay: autoPlayGifs,
                                lowQuality: gridColumnCount > 1,
                                onLongPress: { enterSelectMode(at: index) }
                            )
                        }
                    }
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.86), value: gridColumnCount)
        }
    }

    // MARK: - Floating Bottom Bar
    
    private var floatingBottomBar: some View {
        Group {
            if isSelectMode {
                selectModeBottomBar
            } else {
                normalBottomBar
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .background(Color(hex: 0x171717))
    }
    
    private var normalBottomBar: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            Text("MAKE A GIF")
                .font(.custom("Silkscreen-Regular", size: 16))
                .foregroundColor(Color(red: 0.09, green: 0.09, blue: 0.09))
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    SimpleGradientBackground()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                )
        }
        .buttonStyle(.plain)
    }
    
    private var selectModeBottomBar: some View {
        HStack(spacing: 8) {
            Button { copySelectedGifs() } label: {
                Text("COPY")
                    .font(.silkscreenControl)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(hex: 0x202020))
                    )
            }
            .buttonStyle(.plain)

            Button { shareSelectedGifs() } label: {
                Text("SHARE")
                    .font(.silkscreenControl)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(hex: 0x202020))
                    )
            }
            .buttonStyle(.plain)

            Button { showDeleteConfirmation = true } label: {
                Text("DELETE")
                    .font(.silkscreenControl)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(hex: 0x202020))
                    )
            }
            .buttonStyle(.plain)
        }
        .disabled(selectedIndices.isEmpty)
        .opacity(selectedIndices.isEmpty ? 0.5 : 1.0)
    }
    
    // MARK: - Loading Overlay
    
    private var loadingOverlay: some View {
        Group {
            if isLoadingPhoto {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                }
                .transition(.opacity)
            }
        }
    }
    
    // MARK: - Editor Overlay
    
    private var editorOverlay: some View {
        Group {
            if isEditorPresented, let vm = editorViewModel {
                EditorView(viewModel: vm, isPresented: $isEditorPresented, namespace: animation)
                    .environmentObject(photoManager)
                    .onDisappear { editorViewModel = nil }
            }
        }
    }
    
    // MARK: - Actions
    
    private func selectPhoto(_ image: UIImage) {
        editorViewModel = EditorViewModel(content: .newImage(image))
        withAnimation(.spring(response: AppConstants.Animation.standard, dampingFraction: 0.8)) {
            isEditorPresented = true
        }
    }
    
    private func selectGif(at index: Int) {
        guard let url = photoManager.myGifURLs[safe: index] else {
            return
        }
        
        let assetId = photoManager.myGifAssetIdentifiers[safe: index] ?? ""
        editorViewModel = EditorViewModel(content: .existingGif(url, index, assetId))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isEditorPresented = true
        }
    }
    
    // MARK: - Selection Mode
    
    private func enterSelectMode(at index: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isSelectMode = true
            selectedIndices = [index]
        }
    }
    
    private func exitSelectMode() {
        isSelectMode = false
        selectedIndices = []
    }
    
    private func toggleSelection(at index: Int) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            if selectedIndices.contains(index) {
                selectedIndices.remove(index)
                if selectedIndices.isEmpty {
                    isSelectMode = false
                }
            } else {
                selectedIndices.insert(index)
            }
        }
    }
    
    private func deleteSelectedGifs() {
        let identifiers = selectedIndices.compactMap { photoManager.myGifAssetIdentifiers[safe: $0] }
        guard !identifiers.isEmpty else { return }
        
        photoManager.deleteGifAssets(identifiers: identifiers) { [self] success, _ in
            if success {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    exitSelectMode()
                }
            }
        }
    }

    private func copySelectedGifs() {
        let urls = selectedIndices.sorted().compactMap { photoManager.myGifURLs[safe: $0] }
        guard !urls.isEmpty else { return }

        let items = urls.compactMap { url -> [String: Any]? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return [UTType.gif.identifier: data]
        }
        UIPasteboard.general.setItems(items)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            exitSelectMode()
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.3)) {
                showCopiedToast = false
            }
        }
    }

    private func shareSelectedGifs() {
        let cacheURLs = selectedIndices.sorted().compactMap { photoManager.myGifURLs[safe: $0] }
        guard !cacheURLs.isEmpty else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let activityItems: [Any] = cacheURLs.compactMap { cacheURL -> Any? in
            guard let data = try? Data(contentsOf: cacheURL) else { return nil }
            let tempURL = tempDir.appendingPathComponent("enhance_\(UUID().uuidString).gif")
            try? data.write(to: tempURL)
            return tempURL
        }
        guard !activityItems.isEmpty else { return }

        let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var presenter = rootVC
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            activityVC.popoverPresentationController?.sourceView = presenter.view
            presenter.present(activityVC, animated: true)
        }
    }
}

// MARK: - Staircase Squares (NUX Animated Icon)

private struct StaircaseSquares: View {
    @State private var animate = false
    
    private let squareConfigs: [(size: CGFloat, offset: (x: CGFloat, y: CGFloat), delay: Double)] = [
        (size: 32.8, offset: (-40, 40),  delay: 0.0),
        (size: 43.8, offset: (-15, 15),  delay: 0.15),
        (size: 54.7, offset: (12, -12),  delay: 0.3),
        (size: 65.6, offset: (40, -40),  delay: 0.45),
    ]
    
    var body: some View {
        ZStack {
            ForEach(0..<squareConfigs.count, id: \.self) { i in
                let config = squareConfigs[i]
                SimpleGradientBackground(
                    primaryColors: gradientColors(for: i).primary,
                    secondaryColors: gradientColors(for: i).secondary,
                    positionAnimationDuration: 2.5,
                    colorAnimationDuration: 4.0
                )
                .frame(width: config.size, height: config.size)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .offset(x: config.offset.x, y: config.offset.y)
                .scaleEffect(animate ? 1.08 : 0.92)
                .animation(
                    .easeInOut(duration: 1.6)
                        .repeatForever(autoreverses: true)
                        .delay(config.delay),
                    value: animate
                )
            }
        }
        .onAppear { animate = true }
    }
    
    private func gradientColors(for index: Int) -> (primary: [Color], secondary: [Color]) {
        let palettes: [(primary: [Color], secondary: [Color])] = [
            (
                primary: [Color(hex: 0x18B273), Color(hex: 0x0D8A57), Color(hex: 0x18B273),
                          Color(hex: 0x0D8A57), Color(hex: 0x18B273), Color(hex: 0x0D8A57),
                          Color(hex: 0x18B273), Color(hex: 0x0D8A57), Color(hex: 0x18B273)],
                secondary: [Color(hex: 0x43AE8F), Color(hex: 0x18B273), Color(hex: 0x43AE8F),
                            Color(hex: 0x18B273), Color(hex: 0x43AE8F), Color(hex: 0x18B273),
                            Color(hex: 0x43AE8F), Color(hex: 0x18B273), Color(hex: 0x43AE8F)]
            ),
            (
                primary: [Color(hex: 0x43AE8F), Color(hex: 0x18B273), Color(hex: 0x43AE8F),
                          Color(hex: 0x18B273), Color(hex: 0x43AE8F), Color(hex: 0x18B273),
                          Color(hex: 0x43AE8F), Color(hex: 0x18B273), Color(hex: 0x43AE8F)],
                secondary: [Color(hex: 0x6EAAAC), Color(hex: 0x43AE8F), Color(hex: 0x6EAAAC),
                            Color(hex: 0x43AE8F), Color(hex: 0x6EAAAC), Color(hex: 0x43AE8F),
                            Color(hex: 0x6EAAAC), Color(hex: 0x43AE8F), Color(hex: 0x6EAAAC)]
            ),
            (
                primary: [Color(hex: 0x6EAAAC), Color(hex: 0x43AE8F), Color(hex: 0x6EAAAC),
                          Color(hex: 0x43AE8F), Color(hex: 0x6EAAAC), Color(hex: 0x43AE8F),
                          Color(hex: 0x6EAAAC), Color(hex: 0x43AE8F), Color(hex: 0x6EAAAC)],
                secondary: [Color(hex: 0x18B273), Color(hex: 0x6EAAAC), Color(hex: 0x18B273),
                            Color(hex: 0x6EAAAC), Color(hex: 0x18B273), Color(hex: 0x6EAAAC),
                            Color(hex: 0x18B273), Color(hex: 0x6EAAAC), Color(hex: 0x18B273)]
            ),
            (
                primary: [Color(hex: 0x6EAAAC), Color(hex: 0x6EAAAC), Color(hex: 0x6EAAAC),
                          Color(hex: 0x43AE8F), Color(hex: 0x6EAAAC), Color(hex: 0x43AE8F),
                          Color(hex: 0x6EAAAC), Color(hex: 0x6EAAAC), Color(hex: 0x6EAAAC)],
                secondary: [Color(hex: 0x43AE8F), Color(hex: 0x18B273), Color(hex: 0x43AE8F),
                            Color(hex: 0x18B273), Color(hex: 0x43AE8F), Color(hex: 0x18B273),
                            Color(hex: 0x43AE8F), Color(hex: 0x18B273), Color(hex: 0x43AE8F)]
            ),
        ]
        return palettes[index % palettes.count]
    }
}
