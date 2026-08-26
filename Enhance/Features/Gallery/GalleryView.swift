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
    @AppStorage(FeatureFlags.motionParallaxKey) private var motionParallax = false
    @AppStorage(FeatureFlags.motionSharedZoomKey) private var motionSharedZoom = false

    /// Which grid index the editor is currently showing, so that cell can hand over its
    /// `matchedGeometryEffect` source for the duration. `nil` whenever the editor is closed or
    /// was opened on a newly-picked photo, which has no originating cell.
    @State private var zoomingIndex: Int?

    /// The in-app camera experiment. Scaffolding — see `FeatureFlags.cameraCapture`.
    @AppStorage(FeatureFlags.cameraCaptureKey) private var cameraCapture = false
    @State private var isCameraPresented = false
    @State private var cameraViewModel: CameraViewModel?

    /// Bumped on every `openCamera()` and used as the overlay's `.id`, so each presentation
    /// is structurally a new view with fresh `@State` — see `closeCamera()` for the revival
    /// failure this forecloses.
    @State private var cameraLaunchToken = 0

    /// True from the moment the captured photo's geometry id is handed to the editor until the
    /// camera overlay is torn down — the freeze frame yields `isSource` on this, the same
    /// one-owner rule `zoomingIndex` implements for grid cells.
    @State private var cameraZoomHandoff = false

    @StateObject private var deviceMotion = DeviceMotionService()

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
        // Above the editor on purpose: after a capture the frozen photo flies from the
        // viewfinder to the canvas, and it must pass *over* the incoming editor.
        .overlay { cameraOverlay }
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
            // The parallax normally starts from `isIdleForAmbience` *changing* — but on a fresh
            // launch the gallery can arrive already idle, in which case that transition never
            // happens and the accelerometer never starts until something else toggles the state.
            if isIdleForAmbience { startDeviceMotionIfWanted() }
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
    
    /// One row of the grid's data, carrying a *stable identity* for SwiftUI alongside the index
    /// the arrays are keyed by. The identifier is preferred; the URL stands in when the id list
    /// runs short (they are appended independently in `performFetch`), and the index is the
    /// fallback of last resort.
    private struct GridEntry: Identifiable {
        let index: Int
        let id: String
    }

    private var gridEntries: [GridEntry] {
        let count = min(photoManager.myGifs.count, photoManager.myGifURLs.count)
        let entries = (0..<count).map { index in
            GridEntry(
                index: index,
                id: photoManager.myGifAssetIdentifiers[safe: index]
                    ?? photoManager.myGifURLs[safe: index]?.absoluteString
                    ?? "index-\(index)"
            )
        }
        // A just-saved GIF stays out of the grid until the editor is off screen. The library
        // refresh lands ~1s before the overlay closes, so without this the shift-over and the
        // insertion both play *behind the editor* and all the user sees is the pixel fill.
        // Holding the entry back moves the whole choreography — neighbours sliding over, the
        // placeholder scaling in, the pixels assembling — to after the gallery is visible.
        if motionSaveReveal, !reduceMotion, isEditorPresented,
           let pending = photoManager.justSavedIdentifier {
            return entries.filter { $0.id != pending }
        }
        return entries
    }

    private var gridLayer: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 16)

                LazyVGrid(columns: gridColumns, spacing: 10) {
                    // Keyed by asset identity, not by position. With `id: \.self` on indices, a
                    // save inserting at the front re-rendered every cell in place and the grid
                    // never *moved* — identity is what lets the existing cells slide over to
                    // make room while the newcomer transitions in.
                    ForEach(gridEntries) { entry in
                        let index = entry.index
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
                            // The newcomer's arrival: the empty box scales in first (phase 1),
                            // then `GifGridItem`'s reveal fills it with pixels (phase 2).
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                            // Per-cell rather than one transform on the whole grid *(user's
                            // call, 2026-08-14)*: each GIF drifts at its own depth, so the tilt
                            // reads as looking into a stack of cards rather than the grid
                            // sliding as a plane.
                            .offset(cellParallax(for: entry.id))
                        }
                    }
                }
                // Animates insertions — the shift-over plus the newcomer's transition. Scoped to
                // the *visible* entries so scrolling and selection cannot trigger it, and inert
                // without the flag so the shipped gallery still snaps.
                .animation(
                    motionSaveReveal && !reduceMotion
                        ? .spring(response: 0.45, dampingFraction: 0.8)
                        : nil,
                    value: gridEntries.map(\.id)
                )

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.86), value: gridColumnCount)
        }
    }

    // MARK: - Ambient motion

    /// This GIF's tilt drift. `parallaxMagnitude` is the *deepest* cell's travel; every cell
    /// gets a stable fraction of it derived from its identity, so neighbours separate under
    /// tilt and the same GIF keeps the same depth across re-renders.
    private func cellParallax(for id: String) -> CGSize {
        guard motionParallax, !reduceMotion else { return .zero }
        let magnitude = motionStore.tuning.parallaxMagnitude * cellDepth(for: id)
        return CGSize(
            width: deviceMotion.tilt.width * magnitude,
            height: deviceMotion.tilt.height * magnitude
        )
    }

    /// A stable 0.35…1.0 per identity. Hand-rolled rather than `Hasher`, which is seeded per
    /// launch — a depth that reshuffled on every cold start would make the same gallery feel
    /// subtly different each time for no reason.
    private func cellDepth(for id: String) -> Double {
        var hash: UInt64 = 1469598103934665603
        for byte in id.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return 0.35 + 0.65 * Double(hash % 1000) / 999
    }

    /// Whether the gallery is quiet enough for the ambient motion to run.
    private var isIdleForAmbience: Bool {
        scenePhase == .active
            && !isSelectMode
            && !isPinching
            && !isEditorPresented
            && !isCameraPresented
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
        return .init(
            cellSize: tuning.revealCellSize,
            duration: tuning.revealDuration,
            delay: tuning.revealDelay
        )
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
        // The grid's own margin, so MAKE A GIF lines up with the cells above it rather than
        // running 6pt wider than the content it belongs to *(user's call, 2026-08-15)*.
        .padding(.horizontal, AppConstants.Spacing.grid)
        .padding(.vertical, AppConstants.Spacing.grid)
        .background(Color.surfacePrimary)
    }
    
    private var normalBottomBar: some View {
        HStack(spacing: 8) {
            if cameraCapture {
                cameraButton
                    .transition(.scale.combined(with: .opacity))
            }

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
        // Animated on the flag so toggling IN-APP CAMERA repaints live under the settings
        // sheet, which floats over the gallery rather than replacing it.
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: cameraCapture)
    }

    private var cameraButton: some View {
        Button {
            HapticService.selection()
            openCamera()
        } label: {
            Image("icon-camera-sharp")
                .renderingMode(.template)
                .resizable()
                .frame(width: 24, height: 24)
                .gradientButtonLabel()
                .frame(width: 60, height: 60)
                .background(
                    ButtonGradientBackground()
                        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
                )
        }
        .buttonStyle(EnhancePressButtonStyle())
        // No matched geometry here: the overlay's scale transition is anchored on this
        // button's spot instead (`CameraOverlayView.launchAnchor`). The button stays mounted
        // and visible under the scrim the whole time the camera is up — an extra
        // always-mounted source in the shared namespace destabilized the other
        // view-transition experiments, and hiding the button read as it vanishing.
        .accessibilityLabel("Open camera")
        .accessibilityIdentifier("gallery-camera-button")
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
                    sharedZoomID: zoomingIndex.map { "gif\($0)" }
                        ?? (cameraZoomHandoff ? CameraOverlayView.captureGeometryID : nil)
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
    
    // MARK: - Camera Overlay

    private var cameraOverlay: some View {
        Group {
            if isCameraPresented, let vm = cameraViewModel {
                CameraOverlayView(
                    viewModel: vm,
                    namespace: animation,
                    hasYieldedGeometry: cameraZoomHandoff,
                    // Capture the birth token: this instance may ask to close after a
                    // reopen has already replaced it, and that request must die stale.
                    onClose: { [token = cameraLaunchToken] in closeCameraIfCurrent(token) },
                    onCapture: presentEditorFromCamera
                )
                .id(cameraLaunchToken)
            }
        }
    }

    // MARK: - Actions

    private func openCamera() {
        // A reopen can land inside the previous overlay's exit beat — it stays mounted,
        // invisible and inert, until its shrink-out settles and it asks to be closed. Tear
        // any remnant down instantly (closeCamera is idempotent) so the fresh presentation
        // starts from nothing; bumping the token right after orphans that instance's still
        // pending close (`closeCameraIfCurrent`), which must not kill the new camera.
        if isCameraPresented { closeCamera() }
        // A new identity per presentation, so SwiftUI can never hand a fresh open the
        // previous overlay's dying render tree (whose `hasEntered` state is spent).
        cameraLaunchToken += 1
        // Both writes in ONE animated transaction: the overlay's insertion is gated on the
        // pair (`if isCameraPresented, let vm`), and when the view-model write landed in its
        // own unanimated transaction first, the insertion could ride that one and pop.
        // The card's transition is a scale anchored on the button's spot plus a fade —
        // just the fade under Reduce Motion. See `CameraOverlayView.cardTransition`.
        // Curve and start scale are MOTION LAB knobs (`MotionTuning.cameraScaleFrom` /
        // `.cameraCurve`), tuned live like the editor experiments.
        withAnimation(motionStore.tuning.cameraEffective.animation) {
            cameraViewModel = CameraViewModel()
            isCameraPresented = true
        }
    }

    /// The overlay's own close path. Each overlay instance closes with the token it was
    /// born under — an instance replaced by a reopen still has a delayed close in flight,
    /// and letting that stale request through would tear down its successor.
    private func closeCameraIfCurrent(_ token: Int) {
        guard token == cameraLaunchToken else { return }
        closeCamera()
    }

    private func closeCamera() {
        cameraViewModel?.close()
        // The overlay has already animated itself out (`CameraOverlayView.dismiss()` shrinks
        // the card back into the button before calling this), so the unmount is invisible
        // and happens in one dead transaction. Leaving an animated removal running here kept
        // a dying instance alive in the branch — a reopen inside that window could revive
        // it, dismissed and inert, instead of inserting a fresh overlay.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCameraPresented = false
            cameraViewModel = nil
        }
    }

    /// The captured photo's flight into the editor. Same destination as `selectPhoto(_:)`,
    /// with the viewfinder's freeze frame as the geometry source the `.newImage` path never
    /// had — see `FEATURE-CAMERA.md`.
    private func presentEditorFromCamera(_ image: UIImage) {
        guard !isEditorPresented else { return }

        if reduceMotion {
            // No flight: the editor fades in on its own and the camera goes quietly.
            selectPhoto(image)
            dismissCameraAfterHandoff()
            return
        }

        // The freeze frame mounted this runloop; it needs one rendered frame as `isSource`
        // before yielding, or there is no established geometry to fly from. The short delay
        // also lets the chrome/scrim fade read as its own beat.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard isCameraPresented else { return }
            // Yield outside the animation, then present inside it — `selectGif(at:)`'s
            // one-owner ordering, in the same two transactions.
            cameraZoomHandoff = true
            editorViewModel = EditorViewModel(content: .newImage(image))
            withAnimation(.spring(response: AppConstants.Animation.standard, dampingFraction: 0.8)) {
                isEditorPresented = true
            }
            dismissCameraAfterHandoff()
        }
    }

    /// Tears the camera down once the flight has settled — without animation, because by then
    /// the freeze frame sits pixel-identical over the editor's own canvas.
    private func dismissCameraAfterHandoff() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isCameraPresented = false
                cameraViewModel = nil
                cameraZoomHandoff = false
            }
        }
    }

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
