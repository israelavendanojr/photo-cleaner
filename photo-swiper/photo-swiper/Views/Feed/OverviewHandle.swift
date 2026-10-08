import SwiftUI

/// Grab handle at the top of the feed. Tap or pull down to open the overview.
struct OverviewHandle: View {
    let onOpen: () -> Void

    @State private var pull: CGFloat = 0

    var body: some View {
        VStack(spacing: 2) {
            Capsule()
                .fill(DS.Palette.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.secondary)
        }
        .offset(y: pull)
        .padding(.horizontal, 48)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { pull = min(max($0.translation.height, 0), 40) * 0.4 }
                .onEnded { value in
                    if value.translation.height > 30 { onOpen() }
                    withAnimation(DS.Motion.snapBack) { pull = 0 }
                }
        )
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Open library overview")
        .accessibilityAction(.default, onOpen)
    }
}

#Preview {
    OverviewHandle { print("open") }
        .padding()
        .background(DS.Palette.paper)
}
