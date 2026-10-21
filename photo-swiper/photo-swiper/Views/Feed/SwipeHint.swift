import SwiftUI

/// Shown on the very first card: which way each decision goes. Fades as the card is dragged.
struct SwipeHint: View {
    var body: some View {
        VStack(spacing: DS.Spacing.xxs) {
            Text("← Delete · Keep →")
            Text("↑ Later")
                .opacity(0.8)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.s)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Swipe left to delete, right to keep, or up for later")
    }
}

/// One gentle left-then-right sway, so a first-time user sees the card moves. Off with Reduce Motion.
struct SwipeNudge: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trigger = false

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, x in
                view
                    .rotationEffect(.degrees(x / 32))
                    .offset(x: x)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(-24, duration: 0.35)
                    SpringKeyframe(0, duration: 0.3)
                    SpringKeyframe(24, duration: 0.35)
                    SpringKeyframe(0, duration: 0.45)
                }
            }
            .task(id: isActive) {
                guard isActive, !reduceMotion else { return }
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                trigger.toggle()
            }
    }
}

#Preview {
    PhotoCardView(item: PreviewSamples.plainPhoto)
        .overlay { SwipeHint() }
        .modifier(SwipeNudge(isActive: true))
        .padding(14)
        .background(DS.Palette.paper)
}
