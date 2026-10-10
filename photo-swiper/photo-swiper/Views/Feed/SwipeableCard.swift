import SwiftUI

/// Wraps a card face with the drag gesture, tilt, overlay stamps, and fly-out.
///
/// The card commits once it is dragged far enough or flicked. A light haptic marks the
/// moment it crosses a threshold, so the user feels the decision before letting go.
struct SwipeableCard<Content: View>: View {
    /// False while the card waits behind the top card.
    let isEnabled: Bool
    /// Overlay text for each direction.
    let label: (SwipeDirection) -> String
    /// Set by the action buttons to swipe programmatically. Reset to nil once handled.
    @Binding var request: SwipeDirection?
    /// 0 at rest, 1 when fully committed. Drives the card behind.
    @Binding var progress: Double
    /// Undo's entrance side. A new one while the card is still flying brings it back from mid-flight.
    let entrance: SwipeDirection?
    /// Called the moment the card commits, as the fly-out starts.
    let onRelease: (SwipeDirection) -> Void
    /// Called after the fly-out animation finishes.
    let onSwipe: (SwipeDirection) -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGSize
    @State private var armed: SwipeDirection?
    @State private var isFlying = false
    /// Bumped per fly-out so a cancelled flight's completion is ignored.
    @State private var flight = 0

    /// - Parameter entrance: When set, the card starts off-screen on that side and springs in (undo).
    init(
        isEnabled: Bool = true,
        entrance: SwipeDirection? = nil,
        label: @escaping (SwipeDirection) -> String,
        request: Binding<SwipeDirection?>,
        progress: Binding<Double>,
        onRelease: @escaping (SwipeDirection) -> Void = { _ in },
        onSwipe: @escaping (SwipeDirection) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isEnabled = isEnabled
        self.entrance = entrance
        self.onRelease = onRelease
        self.label = label
        _request = request
        _progress = progress
        self.onSwipe = onSwipe
        self.content = content()
        _offset = State(initialValue: entrance.map { Self.offscreen($0, from: .zero) } ?? .zero)
    }

    var body: some View {
        content
            .overlay {
                if isEnabled || isFlying { SwipeOverlay(offset: offset, label: label) }
            }
            .rotationEffect(.degrees(rotation), anchor: .center)
            .offset(offset)
            .gesture(drag, including: isEnabled ? .all : .subviews)
            .onAppear {
                guard offset != .zero else { return }
                withAnimation(DS.Motion.calm) { offset = .zero }
            }
            .onChange(of: entrance) { _, direction in
                guard direction != nil, isFlying else { return }
                flight += 1
                isFlying = false
                armed = nil
                withAnimation(DS.Motion.calm) { offset = .zero }
            }
            .onChange(of: request) { _, direction in
                guard let direction else { return }
                request = nil
                fly(direction)
            }
            .accessibilityActions {
                if isEnabled {
                    ForEach(SwipeDirection.allCases, id: \.self) { direction in
                        Button(label(direction)) { fly(direction) }
                    }
                }
            }
    }

    // MARK: Gesture

    private var rotation: Double {
        let degrees = offset.width / 32
        return min(max(degrees, -12), 12)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isFlying else { return }
                offset = value.translation
                progress = Self.progress(for: value.translation)
                let direction = SwipeThresholds.armed(value.translation)
                if direction != armed {
                    armed = direction
                    if direction != nil { Haptics.threshold() }
                }
            }
            .onEnded { value in
                guard !isFlying else { return }
                if let direction = SwipeThresholds.commit(value.translation, predicted: value.predictedEndTranslation) {
                    fly(direction)
                } else {
                    armed = nil
                    withAnimation(DS.Motion.snapBack) {
                        offset = .zero
                        progress = 0
                    }
                }
            }
    }

    private func fly(_ direction: SwipeDirection) {
        guard isEnabled, !isFlying else { return }
        isFlying = true
        flight += 1
        let current = flight
        withAnimation(DS.Motion.flyOut) {
            offset = Self.offscreen(direction, from: offset)
            progress = 1
        } completion: {
            guard flight == current else { return }
            onSwipe(direction)
        }
        onRelease(direction)
    }

    // MARK: Geometry

    private static func offscreen(_ direction: SwipeDirection, from offset: CGSize) -> CGSize {
        switch direction {
        case .left: CGSize(width: -640, height: offset.height + 60)
        case .right: CGSize(width: 640, height: offset.height + 60)
        case .up: CGSize(width: offset.width, height: -1100)
        }
    }

    private static func progress(for translation: CGSize) -> Double {
        let distance = max(abs(translation.width) / SwipeThresholds.horizontal, -translation.height / SwipeThresholds.up)
        return min(max(distance, 0), 1)
    }
}

/// Distances and flick speeds that turn a drag into a decision.
enum SwipeThresholds {
    static let horizontal: CGFloat = 110
    static let up: CGFloat = 120
    /// Predicted travel that counts as a flick even if the finger didn't go far.
    static let horizontalFlick: CGFloat = 260
    static let upFlick: CGFloat = 300

    /// The direction the drag has already committed to, if any.
    static func armed(_ t: CGSize) -> SwipeDirection? {
        if abs(t.width) >= abs(t.height) {
            if t.width <= -horizontal { return .left }
            if t.width >= horizontal { return .right }
        } else if t.height <= -up {
            return .up
        }
        return nil
    }

    /// Final decision on release, allowing quick flicks.
    static func commit(_ t: CGSize, predicted p: CGSize) -> SwipeDirection? {
        if let direction = armed(t) { return direction }
        if abs(p.width) >= abs(p.height) {
            if p.width <= -horizontalFlick, t.width < -24 { return .left }
            if p.width >= horizontalFlick, t.width > 24 { return .right }
        } else if p.height <= -upFlick, t.height < -24 {
            return .up
        }
        return nil
    }
}

#Preview {
    @Previewable @State var request: SwipeDirection?
    @Previewable @State var progress = 0.0
    @Previewable @State var cardID = 0

    VStack {
        SwipeableCard(
            label: { $0 == .left ? "Delete · 3.4 MB" : $0 == .right ? "Keep" : "Later" },
            request: $request,
            progress: $progress,
            onSwipe: { _ in
                progress = 0
                cardID += 1
            }
        ) {
            PhotoCardView(item: PreviewSamples.blurryPhoto)
        }
        .id(cardID)
        .padding(14)

        HStack {
            Button("Delete") { request = .left }
            Button("Later") { request = .up }
            Button("Keep") { request = .right }
        }
    }
    .background(DS.Palette.paper)
}
