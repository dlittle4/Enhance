import SwiftUI

struct SegmentedBar<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    var onChange: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                Button {
                    withAnimation(.easeOut(duration: AppConstants.Animation.quick)) {
                        selection = item
                    }
                    onChange?()
                } label: {
                    Text(label(item))
                        .font(.silkscreenControl)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(selection == item ? Color(hex: 0x323232) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}