import SwiftUI

struct SegmentedBar<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    var onChange: (() -> Void)? = nil

    private let mintGreen = Color(red: 96/255, green: 255/255, blue: 168/255)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let isSelected = selection == item
                Button {
                    withAnimation(.easeOut(duration: AppConstants.Animation.quick)) {
                        selection = item
                    }
                    onChange?()
                } label: {
                    Text(label(item))
                        .font(.silkscreenControl)
                        .foregroundColor(isSelected ? mintGreen : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(isSelected ? Color(red: 100/255, green: 148/255, blue: 122/255).opacity(0.7) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(isSelected ? mintGreen : .clear, lineWidth: 1)
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