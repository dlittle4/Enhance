import SwiftUI

struct SettingsView: View {
    @Binding var isPresented: Bool
    @Binding var autoPlayGifs: Bool
    @AppStorage("appTheme") private var selectedTheme: String = "PIXEL"
    @AppStorage("selectedAppIcon") private var selectedAppIcon: String = "AppIcon"

    /// Bound straight to the flag's own key rather than passed down like `autoPlayGifs`, because
    /// its reader is `EditorViewModel` — which is not a view and cannot hold an `@AppStorage`.
    /// `UserDefaults` is the shared surface between the two; see `FeatureFlags`.
    @AppStorage(FeatureFlags.zoomOptionalKey) private var zoomOptional: Bool = false

    /// These three are read by views rather than by a view model, so they could have been passed
    /// down — but `ButtonGradientBackground` is instantiated at seven unrelated call sites, and
    /// threading a binding to all of them would put the flag in every intermediate signature.
    /// `@AppStorage` on both ends republishes without that.
    @AppStorage(FeatureFlags.staticGradientKey) private var staticGradient: Bool = false
    @AppStorage(FeatureFlags.ditherGradientKey) private var ditherGradient: Bool = false
    @AppStorage(FeatureFlags.staticBorderKey) private var staticBorder: Bool = false

    @State private var showGradientLab = false

    /// The three face-marker experiments. Bound here and in `EditorView` to the same keys —
    /// `@AppStorage` on both ends republishes, so a toggle repaints the canvas with no plumbing
    /// between the two screens.
    @AppStorage(FeatureFlags.faceMarkersCalmKey) private var faceMarkersCalm: Bool = false
    @AppStorage(FeatureFlags.faceMarkersReticleKey) private var faceMarkersReticle: Bool = false
    @AppStorage(FeatureFlags.faceMarkersSpotlightKey) private var faceMarkersSpotlight: Bool = false
    @AppStorage(FeatureFlags.faceMarkersScanlineKey) private var faceMarkersScanline: Bool = false
    @AppStorage(FeatureFlags.faceMarkersHiddenKey) private var faceMarkersHidden: Bool = false

    @State private var showFaceMarkerLab = false

    private let mintGreen = Color.enhanceMint
    private let themes = ["PIXEL", "THEME 2", "THEME 3"]
    private let appIcons: [(name: String, preview: String, identifier: String?)] = [
        ("AppIcon", "icon-preview-default", nil),
        ("AppIcon-Alt1", "icon-preview-alt1", "AppIcon-Alt1"),
        ("AppIcon-Alt2", "icon-preview-alt2", "AppIcon-Alt2")
    ]

    var body: some View {
        BottomSheet(isPresented: $isPresented, title: "GENERAL SETTINGS", expandable: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    divider
                    autoPlayRow
                    divider

                    // Face markers lead the two experiment sections. The sheet opens at the
                    // `.medium` detent, and adding this section pushed FACE MARKER LAB below that
                    // fold — a destination row you have to drag the sheet up to discover is a
                    // destination most people will not find. Verified on the simulator, both ways
                    // round.
                    faceMarkerSection
                    divider

                    experimentsSection
                    divider

                    appIconSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 48)
            }
        }
        .sheet(isPresented: $showGradientLab) {
            GradientLabView(isPresented: $showGradientLab)
        }
        .sheet(isPresented: $showFaceMarkerLab) {
            FaceMarkerLabView(isPresented: $showFaceMarkerLab)
        }
    }

    // MARK: - Auto-Play

    private var autoPlayRow: some View {
        Button {
            HapticService.selection()
            autoPlayGifs.toggle()
        } label: {
            HStack(spacing: 10) {
                checkmark(isSelected: autoPlayGifs)
                Text("AUTO PLAY GIFS IN GALLERY")
                    .font(.silkscreenLabel)
                    .foregroundColor(autoPlayGifs ? mintGreen : .textPrimary)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Experiments

    /// Behaviour still being evaluated, kept under its own heading so it is not mistaken for a
    /// settled preference. See `FeatureFlags` for what each one gates.
    private var experimentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("EXPERIMENTS")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            experimentRow("MAKE GIFS WITHOUT ZOOMING", isOn: $zoomOptional)
            experimentRow("STATIC BUTTON GRADIENT", isOn: $staticGradient)
            experimentRow("DITHERED BUTTON GRADIENT", isOn: $ditherGradient)
            experimentRow("STATIC BUTTON BORDER", isOn: $staticBorder)

            labRow("GRADIENT LAB →") { showGradientLab = true }
        }
    }

    // MARK: - Face markers

    /// Its own section rather than four more rows under EXPERIMENTS, because **DEFAULT is not an
    /// experiment** — it is what the app does today, and filing it under that heading would say the
    /// opposite. The four rows are one exclusive-ish group governing a single question (what the
    /// face overlay looks like), which is also why they share a component with the lab.
    private var faceMarkerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FACE MARKERS")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            FaceMarkerVariantList(options: faceMarkerOptions)

            labRow("FACE MARKER LAB →") { showFaceMarkerLab = true }
        }
    }

    /// A destination rather than a toggle. No checkmark, and an arrow — that contrast is what
    /// distinguishes the two in a list that is otherwise all toggles. The blank 24pt box keeps
    /// its label on the same left edge as every checkmarked row above it.
    private func labRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticService.selection()
            action()
        } label: {
            HStack(spacing: 10) {
                Color.clear.frame(width: 24, height: 24)
                Text(title)
                    .font(.silkscreenLabel)
                    .foregroundColor(mintGreen)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    /// Bridges the four `@AppStorage` booleans to the one value the shared list edits.
    ///
    /// The flags stay separate booleans in `UserDefaults` — `FeatureFlags` documents that
    /// convention, and each is read independently by `EditorView` — so this assembles and
    /// disassembles rather than storing the struct.
    private var faceMarkerOptions: Binding<FaceMarkerOptions> {
        Binding(
            get: {
                FaceMarkerOptions(
                    calm: faceMarkersCalm,
                    reticle: faceMarkersReticle,
                    spotlight: faceMarkersSpotlight,
                    scanline: faceMarkersScanline,
                    hidden: faceMarkersHidden
                )
            },
            set: { new in
                faceMarkersCalm = new.calm
                faceMarkersReticle = new.reticle
                faceMarkersSpotlight = new.spotlight
                faceMarkersScanline = new.scanline
                faceMarkersHidden = new.hidden
            }
        )
    }

    /// One toggle in EXPERIMENTS. Extracted once the section was several copies of the same
    /// fourteen lines.
    private func experimentRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            HapticService.selection()
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                checkmark(isSelected: isOn.wrappedValue)
                Text(title)
                    .font(.silkscreenLabel)
                    .foregroundColor(isOn.wrappedValue ? mintGreen : .textPrimary)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Themes

    private var themesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THEMES")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            ForEach(themes, id: \.self) { theme in
                Button {
                    HapticService.selection()
                    selectedTheme = theme
                } label: {
                    HStack(spacing: 10) {
                        checkmark(isSelected: selectedTheme == theme)
                        Text(theme)
                            .font(.silkscreenLabel)
                            .foregroundColor(selectedTheme == theme ? mintGreen : .textPrimary)
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - App Icon

    private var appIconSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("APP ICON")
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)

            HStack(spacing: 0) {
                ForEach(appIcons, id: \.name) { icon in
                    Button {
                        HapticService.selection()
                        changeAppIcon(to: icon.name, identifier: icon.identifier)
                    } label: {
                        appIconThumbnail(preview: icon.preview, isSelected: selectedAppIcon == icon.name)
                    }
                    .buttonStyle(.plain)

                    if icon.name != appIcons.last?.name {
                        Spacer()
                    }
                }
            }
        }
    }

    private func appIconThumbnail(preview: String, isSelected: Bool) -> some View {
        Image(preview)
            .resizable()
            .aspectRatio(contentMode: .fill)
        .frame(width: 100, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous)
                .strokeBorder(mintGreen, lineWidth: isSelected ? 4 : 0)
        )
        .shadow(color: Color.shadow, radius: 22, x: 0, y: 22)
    }

    // MARK: - Helpers

    private func checkmark(isSelected: Bool) -> some View {
        ZStack {
            if isSelected {
                Image("icon-check")
                    .resizable()
                    .frame(width: 24, height: 24)
            }
        }
        .frame(width: 24, height: 24)
    }

    private func changeAppIcon(to name: String, identifier: String?) {
        guard selectedAppIcon != name else { return }
        selectedAppIcon = name
        UIApplication.shared.setAlternateIconName(identifier) { error in
            if let error {
                print("Failed to change app icon: \(error.localizedDescription)")
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(height: 1)
    }
}
