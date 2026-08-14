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
    @State private var showPhotoPicker = false
    @AppStorage("autoPlayGifs") private var autoPlayGifs = true
    @AppStorage("exportFormat") private var exportFormat = "gif"
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var animation

    /// MOTION LAB's live values, and the flags deciding which of them the gallery reads.
    /// Scaffolding — see `MotionTuning` for what graduation looks like.
    @ObservedObject private var motionStore = MotionTuningStore.shared
    @AppStorage(FeatureFlags.motionSaveRevealKey) private var motionSaveReveal = false
    @AppStorage(FeatureFlags.motionShimmerKey) private var motionShimmer = false
    @AppStorage(FeatureFlags.motionParallaxKey) private var motionParallax = false
    @AppStorage(FeatureFlags.motionSharedZoomKey) private var motionSharedZoom = false

    /// Which grid index the editor is currently showing, so that cell can hand over its
    /// `matchedGeometryEffect` source for the duration. `nil` whenever the editor is closed or
    /// was opened on a newly-picked photo, which has no originating cell.
    @State private var zoomingIndex: Int?

    @StateObject private var deviceMotion = DeviceMotionService()

    /// Bumped on each shimmer sweep. A counter rather than a bool because a second sweep needs
    /// somewhere to land while the first is still fading.
    @State private var shimmerToken = 0

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
            Color.surfacePrimary.ignoresSafeArea()
            
            VStack(spacing: 0) {
                if photoManager.isAuthorized && !photoManager.hasLoadedGifs {
                    loadingView
                } else if photoManager.hasLoadedGifs && !photoManager.myGifs.isEmpty && !photoManager.myGifURLs.isEmpty {
                    galleryContent
                } else if photoManager.isDenied {
                    permissionDeniedView
                } else {
                    onboardingView
                }
            }
        }
        .preferredColorScheme(.dark)
        .overlay { editorOverlay }
        .overlay { loadingOverlay }
        .overlay(alignment: .top) {
            if showCopiedToast {
                Text("COPIED TO CLIPBOARD")
                    .font(.silkscreenBody)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .surface(.card, opacity: 0.95, cornerRadius: AppConstants.CornerRadius.large)
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
            if status != .notDetermined {
                photoManager.checkAuthorizationStatus()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                if status != .notDetermined {
                    photoManager.checkAuthorizationStatus()
                }
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
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        // A single timer at a fixed 1s tick, counting up to the tuned interval, rather than a
        // publisher rebuilt whenever the interval slider moves — recreating the publisher mid-drag
        // restarts the countdown on every step, so the sweep would never fire while tuning it.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            tickShimmer()
        }
        .onChange(of: isIdleForAmbience) { _, idle in
            // The accelerometer is the one effect here with a running cost, so it is started and
            // stopped rather than left on and ignored.
            idle ? startDeviceMotionIfWanted() : deviceMotion.stop()
        }
        .onChange(of: motionParallax) { _, _ in
            isIdleForAmbience ? startDeviceMotionIfWanted() : deviceMotion.stop()
        }
        .onDisappear { deviceMotion.stop() }
    }

    // MARK: - Ambient lifecycle

    /// Seconds the gallery has been quiet. Reset by anything that makes a sweep unwelcome, so the
    /// interval measures *idle* time rather than wall-clock time.
    @State private var idleSeconds: Double = 0

    private func tickShimmer() {
        guard motionShimmer, !reduceMotion, isIdleForAmbience else {
            idleSeconds = 0
            return
        }
        idleSeconds += 1
        if idleSeconds >= motionStore.tuning.shimmerInterval {
            idleSeconds = 0
            shimmerToken += 1
        }
    }

    private func startDeviceMotionIfWanted() {
        guard motionParallax, !reduceMotion else {
            deviceMotion.stop()
            return
        }
        deviceMotion.start(smoothing: motionStore.tuning.parallaxSmoothing)
    }
    
    // MARK: - Showcase Header (shared by onboarding & denied)
    
    private var showcaseHeader: some View {
        Text("ENHANCE")
            .font(.silkscreenSectionTitle)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
    }
    
    private var showcaseItems: [ShowcaseCarousel.CarouselItem] {
        (0...7).compactMap { i in
            if let url = Bundle.main.url(forResource: "showcase\(i)", withExtension: "gif") {
                return .gif(url)
            }
            return nil
        }
    }
    
    // MARK: - Onboarding (First Launch)
    
    private var onboardingView: some View {
        VStack(spacing: 0) {
            showcaseHeader

            ShowcaseCarousel(items: showcaseItems)
                .padding(.top, 24)

            Spacer()

            VStack(spacing: 28) {
                Text("Create animated GIFs from your photos with dramatic zooms and special effects.")
                    .font(.silkscreenButton)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)

                Text("Enhance the moment.\nElevate the vibe.")
                    .font(.silkscreenButton)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
            }
            .padding(.horizontal, 27)

            Spacer()

            Button {
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                if status == .notDetermined {
                    photoManager.requestAuthorization { granted in
                        if granted {
                            showPhotoPicker = true
                        }
                    }
                } else {
                    showPhotoPicker = true
                }
            } label: {
                Text("MAKE YOUR FIRST GIF")
                    .font(.silkscreenButtonLabel)
                    .gradientButtonLabel()
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(
                        ButtonGradientBackground()
                            .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
                    )
            }
            .buttonStyle(EnhancePressButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
    
    // MARK: - Loading State
    
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
            Spacer()
        }
    }
    
    // MARK: - Permission Denied State
    
    private var permissionDeniedView: some View {
        VStack(spacing: 0) {
            showcaseHeader

            ShowcaseCarousel(items: showcaseItems)
                .padding(.top, 24)
            
            Spacer()
            
            Text("Allow photo access so\nENHANCE can save and display\nyour animated masterpieces")
                .font(.silkscreenButton)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.horizontal, 27)
            
            Spacer()
            
            VStack(spacing: 16) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("OPEN SETTINGS")
                        .font(.silkscreenButtonLabel)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            ButtonGradientBackground()
                                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
                        )
                }
                .buttonStyle(EnhancePressButtonStyle())
                
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Text("CREATE GIF WITHOUT SAVING")
                        .font(.silkscreenBody)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .surface(.card)
                }
                .buttonStyle(EnhancePressButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
    
    // MARK: - Gallery Content (with GIFs)
    
    // MARK: - Gallery Header
    
    private var galleryHeader: some View {
        HStack {
            Group {
                if isSelectMode {
                    Text("\(selectedIndices.count) PHOTOS SELECTED")
                        .contentTransition(.numericText())
                } else {
                    let count = min(photoManager.myGifs.count, photoManager.myGifURLs.count)
                    Text("MY GIFS (\(count))")
                        .contentTransition(.numericText())
                }
            }
            .font(.silkscreenSectionTitle)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSelectMode {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        exitSelectMode()
                    }
                } label: {
                    Text("X")
                        .font(.silkscreenTitle)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            } else {
                Button { showSettings = true } label: {
                    Image("icon-settings")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelectMode)
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
                                onLongPress: { enterSelectMode(at: index) },
                                reveal: revealMotion(forIndex: index),
                                onRevealComplete: {
                                    if let id = photoManager.myGifAssetIdentifiers[safe: index] {
                                        photoManager.clearJustSaved(id)
                                    }
                                },
                                // Handed to the editor while it is showing this cell, so only one
                                // view claims the geometry id at a time.
                                isMatchedGeometrySource: zoomingIndex != index
                            )
                        }
                    }
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.86), value: gridColumnCount)
            // **One transform for the whole grid, not one per cell.** Independent per-cell motion
            // reads as jitter; moving the grid as a plane is what reads as considered. Unanimated
            // on purpose — `DeviceMotionService` already smooths the signal, and layering a spring
            // on top of a filtered stream adds lag without adding calm.
            .offset(parallaxOffset)
            // Drawn over the grid rather than behind it, and non-interactive so it can never eat
            // a tap meant for a GIF.
            .overlay(shimmerOverlay.allowsHitTesting(false))
        }
    }

    // MARK: - Ambient motion

    private var parallaxOffset: CGSize {
        guard motionParallax, !reduceMotion else { return .zero }
        let magnitude = motionStore.tuning.parallaxMagnitude
        return CGSize(
            width: deviceMotion.tilt.width * magnitude,
            height: deviceMotion.tilt.height * magnitude
        )
    }

    /// A diagonal band that crosses the grid, keyed to `shimmerToken` so each tick re-inserts it
    /// and the transition plays the sweep.
    @ViewBuilder
    private var shimmerOverlay: some View {
        if motionShimmer, !reduceMotion {
            GeometryReader { geo in
                ShimmerSweep(
                    token: shimmerToken,
                    duration: motionStore.tuning.shimmerDuration,
                    size: geo.size
                )
            }
        }
    }

    /// Whether the gallery is quiet enough for a shimmer.
    ///
    /// A sweep crossing the grid behind an active edit, a pinch, or a selection reads as a
    /// rendering fault rather than as delight, so the effect skips those ticks entirely instead
    /// of queueing them up for later.
    private var isIdleForAmbience: Bool {
        scenePhase == .active
            && !isSelectMode
            && !isPinching
            && !isEditorPresented
            && !isLoadingPhoto
            && !showSettings
    }

    /// The cell that should build in, if any. Matched by identifier rather than by index so a
    /// concurrent refresh that reorders the grid cannot reveal the wrong GIF.
    private func revealMotion(forIndex index: Int) -> GifGridItem.RevealMotion? {
        guard motionSaveReveal,
              let pending = photoManager.justSavedIdentifier,
              photoManager.myGifAssetIdentifiers[safe: index] == pending,
              // Held back until the editor is out of the way: the array updates ~1s before the
              // overlay closes, and revealing underneath it would spend the animation off-screen.
              !isEditorPresented
        else { return nil }

        let tuning = motionStore.tuning
        return .init(cellSize: tuning.revealCellSize, duration: tuning.revealDuration)
    }

    // MARK: - Floating Bottom Bar
    
    private var floatingBottomBar: some View {
        Group {
            if isSelectMode {
                selectModeBottomBar
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
            } else {
                normalBottomBar
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSelectMode)
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .background(Color.surfacePrimary)
    }
    
    private var normalBottomBar: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            Text("MAKE A GIF")
                .font(.silkscreenButtonLabel)
                .gradientButtonLabel()
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    ButtonGradientBackground()
                        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
                )
        }
        .buttonStyle(EnhancePressButtonStyle())
    }
    
    private var selectModeBottomBar: some View {
        HStack(spacing: 8) {
            Button { copySelectedGifs() } label: {
                Text("COPY")
                    .font(.silkscreenBody)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .surface(.card)
            }
            .buttonStyle(EnhancePressButtonStyle())

            Button { shareSelectedGifs() } label: {
                Text("SHARE")
                    .font(.silkscreenBody)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .surface(.card)
            }
            .buttonStyle(EnhancePressButtonStyle())

            Button { showDeleteConfirmation = true } label: {
                Text("DELETE")
                    .font(.silkscreenBody)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .surface(.card)
            }
            .buttonStyle(EnhancePressButtonStyle())
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
                EditorView(
                    viewModel: vm,
                    isPresented: $isEditorPresented,
                    namespace: animation,
                    sharedZoomIndex: zoomingIndex
                )
                    .environmentObject(photoManager)
                    .onDisappear {
                        editorViewModel = nil
                        // Returned only once the editor is fully gone. Releasing it earlier would
                        // put the source back on a grid cell while the editor's copy still
                        // existed — the same two-owner problem, in the other direction.
                        zoomingIndex = nil
                    }
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
        // Set *before* the animation so the grid cell has already yielded its geometry source
        // when the editor's matching view is inserted — handing over in the same transaction
        // leaves both live for a frame, which is exactly the ambiguity the handover avoids.
        if motionSharedZoom, !reduceMotion {
            zoomingIndex = index
        }
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


/// One diagonal pass of light across the gallery.
///
/// Its own view so the sweep owns its animation state: re-inserted on each `token` change, it
/// animates from one edge to the other and then stops. Keeping this out of `GalleryView` means a
/// grid re-render for any other reason cannot restart or interrupt a sweep in progress.
private struct ShimmerSweep: View {
    let token: Int
    let duration: Double
    let size: CGSize

    @State private var travelled = false

    /// Width of the band, as a fraction of the view. Wide enough to read as light passing over
    /// rather than as a line crossing the screen.
    private var bandWidth: CGFloat { max(size.width * 0.35, 80) }

    var body: some View {
        LinearGradient(
            colors: [
                .clear,
                Color.white.opacity(0.10),
                Color.white.opacity(0.16),
                Color.white.opacity(0.10),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: bandWidth)
        .rotationEffect(.degrees(20))
        // Tall enough that the rotation cannot expose a corner as it crosses.
        .frame(height: size.height * 1.6)
        .offset(x: travelled ? size.width + bandWidth : -bandWidth)
        .blendMode(.plusLighter)
        .onAppear {
            // The band starts off the leading edge and is asked to travel in the same frame it
            // appears; a zero-duration first pass would otherwise show it already arrived.
            travelled = false
            withAnimation(.easeInOut(duration: duration)) {
                travelled = true
            }
        }
        .id(token)
    }
}
