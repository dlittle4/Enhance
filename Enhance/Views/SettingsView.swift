import SwiftUI

struct SettingsView: View {
    @Binding var isPresented: Bool
    @Binding var autoPlayGifs: Bool
    @AppStorage("appTheme") private var selectedTheme: String = "PIXEL"
    @AppStorage("selectedAppIcon") private var selectedAppIcon: String = "AppIcon"

    private let mintGreen = Color(hex: 0x60FFA8)
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

                    appIconSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 48)
            }
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
                    .font(.custom("Silkscreen-Regular", size: 16))
                    .foregroundColor(autoPlayGifs ? mintGreen : .white.opacity(0.5))
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Themes

    private var themesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THEMES")
                .font(.custom("Silkscreen-Bold", size: 16))
                .foregroundColor(.white)

            ForEach(themes, id: \.self) { theme in
                Button {
                    HapticService.selection()
                    selectedTheme = theme
                } label: {
                    HStack(spacing: 10) {
                        checkmark(isSelected: selectedTheme == theme)
                        Text(theme)
                            .font(.custom("Silkscreen-Regular", size: 16))
                            .foregroundColor(selectedTheme == theme ? mintGreen : .white.opacity(0.5))
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
                .font(.custom("Silkscreen-Bold", size: 16))
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(mintGreen, lineWidth: isSelected ? 4 : 0)
        )
        .shadow(color: Color(white: 0.12, opacity: 0.15), radius: 22, x: 0, y: 22)
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
            .fill(Color(hex: 0xD9D9D9))
            .frame(height: 1)
    }
}
