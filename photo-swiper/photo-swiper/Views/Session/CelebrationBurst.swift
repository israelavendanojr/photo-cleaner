import SwiftUI

/// A quiet rise of brick dots, played once when the delete is confirmed.
struct CelebrationBurst: View {
    var dotCount = 16
    @State private var trigger = false

    var body: some View {
        GeometryReader { proxy in
            ForEach(0..<dotCount, id: \.self) { i in
                Circle()
                    .fill(DS.Palette.brick)
                    .frame(width: i.isMultiple(of: 3) ? 6 : 8, height: i.isMultiple(of: 3) ? 6 : 8)
                    .keyframeAnimator(initialValue: Dot(), trigger: trigger) { dot, value in
                        dot
                            .opacity(value.opacity)
                            .scaleEffect(value.scale)
                            .offset(x: value.x, y: value.y)
                    } keyframes: { _ in
                        let delay = Double(i) * 0.05
                        let rise = -40 - CGFloat(i % 4) * 14
                        let drift = CGFloat((i * 37) % 21) - 10
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0, duration: delay)
                            LinearKeyframe(1, duration: 0.35)
                            LinearKeyframe(1, duration: 0.3)
                            LinearKeyframe(0, duration: 0.95)
                        }
                        KeyframeTrack(\.scale) {
                            LinearKeyframe(0, duration: delay)
                            SpringKeyframe(1, duration: 0.5, spring: .smooth)
                        }
                        KeyframeTrack(\.y) {
                            LinearKeyframe(0, duration: delay)
                            CubicKeyframe(rise, duration: 1.6)
                        }
                        KeyframeTrack(\.x) {
                            LinearKeyframe(0, duration: delay)
                            CubicKeyframe(drift, duration: 1.6)
                        }
                    }
                    .position(
                        x: proxy.size.width * CGFloat((i * 7) % 100) / 100 + 6,
                        y: proxy.size.height * 0.8
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { trigger.toggle() }
    }

    private struct Dot {
        var opacity = 0.0
        var scale = 0.0
        var x: CGFloat = 0
        var y: CGFloat = 0
    }
}

#Preview {
    @Previewable @State var replay = 0

    VStack {
        CelebrationBurst()
            .id(replay)
            .frame(height: 96)
        Button("Replay") { replay += 1 }
    }
    .padding(26)
    .background(DS.Palette.paper)
}
