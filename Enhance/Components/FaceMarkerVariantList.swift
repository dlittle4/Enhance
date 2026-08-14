import SwiftUI

/// The four face-marker rows: DEFAULT, then the three variants.
///
/// One component used by **both** Settings and FACE MARKER LAB, deliberately. The two surfaces
/// govern the same four flags, and the moment they render as two separate lists they can disagree
/// about what a state means — which is the exact confusion DEFAULT was added to remove.
///
/// DEFAULT leads because it is what the app does today: a list of experiments that never names the
/// status quo makes "all off" an invisible state, and someone reading it has no way to tell whether
/// the current approach is on, off, or not represented at all.
struct FaceMarkerVariantList: View {
    @Binding var options: FaceMarkerOptions

    /// Shown under the rows when nothing is selected, so the empty state explains itself instead of
    /// looking like a bug.
    var showsHiddenNote: Bool = true

    private let mintGreen = Color.enhanceMint

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("DEFAULT", isOn: options.isDefault) {
                options.toggleDefault()
            }
            row("CALM", isOn: options.calm) {
                options.toggle(\.calm)
            }
            row("RETICLE", isOn: options.reticle) {
                options.toggle(\.reticle)
            }
            row("SPOTLIGHT", isOn: options.spotlight) {
                options.toggle(\.spotlight)
            }
            row("SCANLINE", isOn: options.scanline) {
                options.toggle(\.scanline)
            }

            if showsHiddenNote && options.hidden {
                Text("NO MARKERS — FACES STAY TAPPABLE")
                    .font(.silkscreenSmall)
                    .foregroundColor(.textPrimary)
                    .padding(.top, 6)
            }
        }
    }

    /// The same checkmark idiom as every other row in Settings — `icon-check` rather than an SF
    /// Symbol, because the app's chrome is pixel art and a system glyph reads as foreign here.
    private func row(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticService.selection()
            action()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    if isOn {
                        Image("icon-check")
                            .resizable()
                            .frame(width: 24, height: 24)
                    }
                }
                .frame(width: 24, height: 24)

                Text(title)
                    .font(.silkscreenLabel)
                    .foregroundColor(isOn ? mintGreen : .textPrimary)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct Harness: View {
        @State private var options = FaceMarkerOptions.legacy
        var body: some View {
            FaceMarkerVariantList(options: $options)
                .padding()
                .background(Color.surfacePrimary)
        }
    }
    return Harness()
}
