import SwiftUI

/// A small fanned stack of photos that demonstrates the app: every few seconds the front photo
/// leans toward Delete, flies off, and the stack moves up. Decorative only.
///
/// The loop pauses while the app is in the background and stops when the screen goes. With
/// Reduce Motion it's a still stack.
struct StackedPhotosIllustration: View {
    /// Drawn at the mockup's 250×240 and scaled to fit the rest of the screen above the fold.
    var scale: CGFloat = 0.82
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Neighbors contrast, so each photo reads as a new one.
    private static let photos = ["photo-coast", "photo-sunset", "photo-hills", "photo-pink", "photo-desert", "photo-beach"]

    /// Front, middle, back.
    @State private var stack = Array(photos.prefix(3))
    @State private var nextPhoto = 3
    /// How far the front photo leans toward Delete, 0...1.
    @State private var lean = 0.0
    /// The photo flying off, still drawn until it's out of sight.
    @State private var departing: String?

    private struct Slot {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
        var rotation: Double
    }

    /// The mockup's fan: front at the left, back tilted at the right.
    private static let slots = [
        Slot(x: 0, y: 0, width: 130, height: 170, rotation: 0),
        Slot(x: 74, y: 24, width: 160, height: 210, rotation: 0),
        Slot(x: 100, y: 40, width: 150, height: 190, rotation: 8),
    ]
    private static let leaning = Slot(x: -28, y: 6, width: 130, height: 170, rotation: -7)
    private static let gone = Slot(x: -320, y: 40, width: 130, height: 170, rotation: -18)

    private var isRunning: Bool { !reduceMotion && scenePhase == .active }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isRunning)) { context in
            cards
                .modifier(Drift(time: isRunning ? context.date.timeIntervalSinceReferenceDate : 0))
        }
        .frame(width: 250, height: 240, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: 250 * scale, height: 240 * scale, alignment: .topLeading)
        .accessibilityHidden(true)
        .task(id: isRunning) {
            guard isRunning else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2.5))
                    try await cycle()
                } catch {
                    break
                }
            }
        }
    }

    private var cards: some View {
        ZStack(alignment: .topLeading) {
            ForEach(drawn, id: \.self) { name in
                let slot = slot(for: name)
                photo(name, isFront: name == departing || name == stack.first)
                    .frame(width: slot.width, height: slot.height)
                    .rotationEffect(.degrees(slot.rotation))
                    .offset(x: slot.x, y: slot.y)
                    .zIndex(zIndex(for: name))
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.9)), removal: .identity))
            }
        }
    }

    /// One ForEach for the departing photo and the stack, so a photo keeps its identity as it leaves.
    private var drawn: [String] {
        (departing.map { [$0] } ?? []) + stack.filter { $0 != departing }
    }

    private func slot(for name: String) -> Slot {
        if name == departing { return Self.gone }
        guard let i = stack.firstIndex(of: name) else { return Self.slots[0] }
        if i == 0, lean > 0 { return Self.interpolate(Self.slots[0], Self.leaning, lean) }
        return Self.slots[i]
    }

    private func zIndex(for name: String) -> Double {
        if name == departing { return 10 }
        return Double(Self.slots.count - (stack.firstIndex(of: name) ?? 0))
    }

    private func photo(_ name: String, isFront: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous)
        return Image(name)
            .resizable()
            .scaledToFill()
            .overlay {
                if isFront {
                    SwipeStamp(kind: .delete, text: "Delete", isCompact: true)
                        .opacity(name == departing ? 1 : lean)
                }
            }
            .clipShape(shape)
            .contentShape(shape)
            .cardShadow()
    }

    /// Lean toward Delete with the stamp coming up, fly off, then promote the stack.
    private func cycle() async throws {
        withAnimation(DS.Motion.calm) { lean = 1 }
        try await Task.sleep(for: .seconds(0.85))
        guard let front = stack.first else { return }
        withAnimation(DS.Motion.flyOut) { departing = front }
        try await Task.sleep(for: .seconds(0.06))
        withAnimation(DS.Motion.calm) {
            stack.removeFirst()
            stack.append(Self.photos[nextPhoto % Self.photos.count])
            nextPhoto += 1
            lean = 0
        }
        try await Task.sleep(for: .seconds(0.45))
        departing = nil
    }

    private static func interpolate(_ a: Slot, _ b: Slot, _ t: Double) -> Slot {
        let t = CGFloat(t)
        return Slot(
            x: a.x + (b.x - a.x) * t,
            y: a.y + (b.y - a.y) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t,
            rotation: a.rotation + (b.rotation - a.rotation) * Double(t)
        )
    }
}

/// A slow float, so the stack feels alive between cycles.
private struct Drift: ViewModifier {
    let time: TimeInterval

    func body(content: Content) -> some View {
        let phase = time * 2 * .pi / 6
        content
            .offset(y: 3 * sin(phase))
            .rotationEffect(.degrees(0.6 * sin(phase + 1)))
    }
}

#Preview {
    StackedPhotosIllustration()
        .padding(40)
        .background(DS.Palette.paper)
}
