import SwiftUI

/// Reusable bottom sheet content with a standard header (title + X close button).
/// Present using SwiftUI's native `.sheet` with `presentationDetents` for consistent
/// system-standard slide-up animation and drag-to-dismiss behavior.
///
/// Pass `expandable: true` for sheets with scrollable content (e.g. album picker).
/// Pass `expandable: false` (default) for sheets with fixed, short content that
/// should only appear at medium height.
struct BottomSheet<Content: View>: View {
    @Binding var isPresented: Bool
    let title: String
    let expandable: Bool
    @ViewBuilder let content: () -> Content

    init(isPresented: Binding<Bool>, title: String, expandable: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self._isPresented = isPresented
        self.title = title
        self.expandable = expandable
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .background(Color.surfaceCard)

            content()

            Spacer(minLength: 0)
        }
        .presentationDetents(expandable ? [.medium, .large] : [.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.surfaceCard)
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.silkscreenSectionTitle)
                .foregroundColor(.white)
            Spacer()
            Button { isPresented = false } label: {
                Text("X")
                    .font(.silkscreenTitle)
                    .foregroundColor(.white)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 16)
    }
}
