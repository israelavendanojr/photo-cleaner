import SwiftUI

/// A short burst of brick confetti falling over the screen, about two seconds, then `onFinish`.
/// Never takes touches. Under Reduce Motion a small message fades in and out instead.
/// Either way VoiceOver hears `message`.
struct ConfettiView: View {
    /// What the moment means, e.g. "Every photo reviewed". Read by VoiceOver, and shown under Reduce Motion.
    let message: String
    var duration: TimeInterval = 2
    var onFinish: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var pieces = Piece.burst(count: 90)
    @State private var isMessageShown = false

    var body: some View {
        ZStack {
            if reduceMotion {
                gentle
            } else {
                confetti
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .task {
            AccessibilityNotification.Announcement(message).post()
            if reduceMotion {
                withAnimation(DS.Motion.gentle) { isMessageShown = true }
                try? await Task.sleep(for: .seconds(duration + 0.5))
                guard !Task.isCancelled else { return }
                withAnimation(DS.Motion.gentle) { isMessageShown = false }
                try? await Task.sleep(for: .seconds(0.7))
            } else {
                try? await Task.sleep(for: .seconds(duration))
            }
            guard !Task.isCancelled else { return }
            onFinish()
        }
    }

    private var confetti: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start)
            Canvas { canvas, size in
                for piece in pieces {
                    piece.draw(in: &canvas, size: size, elapsed: elapsed, duration: duration)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// No movement: a quiet note near the top that fades in, then out.
    private var gentle: some View {
        VStack {
            Label(message, systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.brick)
                .padding(.horizontal, DS.Spacing.m)
                .padding(.vertical, DS.Spacing.s)
                .background(DS.Palette.brickTint, in: Capsule())
                .opacity(isMessageShown ? 1 : 0)
                .padding(.top, DS.Spacing.xl)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One scrap of confetti. Positions are fractions of the canvas, so any size works.
private struct Piece {
    static let colors: [Color] = [DS.Palette.brick, DS.Palette.brick.opacity(0.7), DS.Palette.brickTint, DS.Palette.ink.opacity(0.75)]

    var x: Double
    /// How far above the top it starts, as a fraction of the height.
    var lift: Double
    /// Fall speed, in heights per second.
    var speed: Double
    var sway: Double
    var swayRate: Double
    var phase: Double
    var spin: Double
    var flutter: Double
    var size: CGSize
    var color: Color

    static func burst(count: Int) -> [Piece] {
        (0..<count).map { _ in
            Piece(
                x: .random(in: 0...1),
                lift: .random(in: 0.02...0.45),
                speed: .random(in: 0.45...0.8),
                sway: .random(in: 8...26),
                swayRate: .random(in: 2...5),
                phase: .random(in: 0...(2 * .pi)),
                spin: .random(in: -6...6),
                flutter: .random(in: 4...10),
                size: CGSize(width: .random(in: 6...10), height: .random(in: 9...15)),
                color: colors.randomElement() ?? DS.Palette.brick
            )
        }
    }

    func draw(in canvas: inout GraphicsContext, size canvasSize: CGSize, elapsed t: TimeInterval, duration: TimeInterval) {
        // A little gravity on top of each piece's own speed.
        let y = (-lift + speed * t + 0.18 * t * t) * canvasSize.height
        let x = x * canvasSize.width + sin(t * swayRate + phase) * sway
        guard y > -size.height, y < canvasSize.height + size.height else { return }
        var piece = canvas
        // Fades out over the last half second.
        piece.opacity = max(0, min(1, (duration - t) / 0.5))
        piece.translateBy(x: x, y: y)
        piece.rotate(by: .radians(phase + spin * t))
        piece.scaleBy(x: cos(t * flutter + phase), y: 1)
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        piece.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
    }
}

#if DEBUG
#Preview {
    ConfettiView(message: "Every photo reviewed", duration: 4)
        .background(DS.Palette.paper)
}
#endif
