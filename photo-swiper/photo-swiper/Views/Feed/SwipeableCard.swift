import SwiftUI

/// Wraps a card face with the drag gesture, tilt, overlay stamps, and fly-out.
///
/// The card commits once it is dragged far enough or flicked. A light haptic marks the
/// moment it crosses a threshold, so the user feels the decision before letting go.
/// A swipe that can't go through flies out all the same, then rewinds back into place.
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
    /// Plays the first-time swipe demo (`SwipeNudge`) while the card sits untouched.
    let nudges: Bool
    /// False when a swipe that way can't go through (out of free swipes). Asked as the swipe
    /// commits. The card then flies out, comes back from the same side, and reports `onRefused`
    /// once it's in place. Nothing is released or swiped.
    let canCommit: (SwipeDirection) -> Bool
    let onRefused: (SwipeDirection) -> Void
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var offset: CGSize
    @State private var armed: SwipeDirection?
    /// Flying out, or rewinding after a refused swipe. Drags and requests are ignored meanwhile.
    @State private var isFlying = false
    /// Where a drag that began mid-flight started. That drag is ignored to the end, so it can't
    /// jump the card once the rewind is over. Keyed by start point, since a cancelled drag never ends.
    @State private var staleDragStart: CGPoint?
    /// Reduce Motion's stand-in for the rewind: the card fades out and back in place.
    @State private var opacity = 1.0
    /// Bumped per fly-out so a cancelled flight's completion is ignored.
    @State private var flight = 0
    @State private var isDragging = false
    @State private var lastTouch: ContinuousClock.Instant?

    /// - Parameter entrance: When set, the card starts off-screen on that side and springs in (undo).
    init(
        isEnabled: Bool = true,
        entrance: SwipeDirection? = nil,
        label: @escaping (SwipeDirection) -> String,
        request: Binding<SwipeDirection?>,
        progress: Binding<Double>,
        onRelease: @escaping (SwipeDirection) -> Void = { _ in },
        onSwipe: @escaping (SwipeDirection) -> Void,
        nudges: Bool = false,
        canCommit: @escaping (SwipeDirection) -> Bool = { _ in true },
        onRefused: @escaping (SwipeDirection) -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) {
        self.canCommit = canCommit
        self.onRefused = onRefused
        self.isEnabled = isEnabled
        self.entrance = entrance
        self.onRelease = onRelease
        self.label = label
        _request = request
        _progress = progress
        self.onSwipe = onSwipe
        self.nudges = nudges
        self.content = content()
        _offset = State(initialValue: entrance.map { SwipeThresholds.offscreen($0, from: .zero) } ?? .zero)
    }

    var body: some View {
        content
            .overlay {
                if isEnabled || isFlying { SwipeOverlay(offset: offset, label: label) }
            }
            .rotationEffect(.degrees(rotation), anchor: .center)
            .offset(offset)
            .opacity(opacity)
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
                withAnimation(DS.Motion.calm) {
                    offset = .zero
                    opacity = 1
                }
            }
            .onChange(of: request) { _, direction in
                guard let direction else { return }
                request = nil
                attempt(direction)
            }
            .task(id: nudges && isEnabled && !reduceMotion) {
                guard nudges, isEnabled, !reduceMotion else { return }
                await runNudges()
            }
            .accessibilityActions {
                if isEnabled {
                    ForEach(SwipeDirection.allCases, id: \.self) { direction in
                        Button(label(direction)) { attempt(direction) }
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
                isDragging = true
                lastTouch = .now
                if isFlying { staleDragStart = value.startLocation }
                guard value.startLocation != staleDragStart else { return }
                // Follows the finger even when out of swipes; refusal waits for the release.
                offset = value.translation
                progress = Self.progress(for: value.translation)
                let direction = SwipeThresholds.armed(value.translation)
                if direction != armed {
                    armed = direction
                    if direction != nil { Haptics.threshold() }
                }
            }
            .onEnded { value in
                isDragging = false
                lastTouch = .now
                guard value.startLocation != staleDragStart else {
                    staleDragStart = nil
                    return
                }
                guard !isFlying else { return }
                if let direction = SwipeThresholds.commit(value.translation, predicted: value.predictedEndTranslation) {
                    attempt(direction)
                } else {
                    armed = nil
                    withAnimation(DS.Motion.snapBack) {
                        offset = .zero
                        progress = 0
                    }
                }
            }
    }

    /// Flies off, or rewinds when the swipe can't go through.
    private func attempt(_ direction: SwipeDirection) {
        guard isEnabled, !isFlying else { return }
        guard canCommit(direction) else {
            rewind(direction)
            return
        }
        fly(direction)
    }

    /// A refused swipe: flies out like a real one, then comes back from the same side, with the
    /// refused haptic as it turns. `onRefused` waits until the card is back, so the rewind is
    /// seen before the wall's sheet covers it. Never releases or swipes, so nothing is decided.
    private func rewind(_ direction: SwipeDirection) {
        isFlying = true
        flight += 1
        let current = flight
        armed = nil
        // The card behind settles back at once: it isn't coming up.
        withAnimation(DS.Motion.calm) { progress = 0 }
        guard !reduceMotion else {
            fadeBack(direction, flight: current)
            return
        }
        withAnimation(DS.Motion.flyOut) {
            offset = SwipeThresholds.offscreen(direction, from: offset)
        } completion: {
            guard flight == current else { return }
            Haptics.refused()
            withAnimation(DS.Motion.calm, completionCriteria: .logicallyComplete) {
                offset = .zero
            } completion: {
                guard flight == current else { return }
                isFlying = false
                onRefused(direction)
            }
        }
    }

    /// Reduce Motion's rewind: a quick fade out and back in place, with no travel.
    private func fadeBack(_ direction: SwipeDirection, flight current: Int) {
        withAnimation(.easeIn(duration: 0.12)) {
            opacity = 0
        } completion: {
            guard flight == current else { return }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { offset = .zero }
            Haptics.refused()
            withAnimation(.easeOut(duration: 0.2)) {
                opacity = 1
            } completion: {
                guard flight == current else { return }
                isFlying = false
                onRefused(direction)
            }
        }
    }

    private func fly(_ direction: SwipeDirection) {
        guard isEnabled, !isFlying else { return }
        isFlying = true
        flight += 1
        let current = flight
        withAnimation(DS.Motion.flyOut) {
            offset = SwipeThresholds.offscreen(direction, from: offset)
            progress = 1
        } completion: {
            guard flight == current else { return }
            onSwipe(direction)
        }
        onRelease(direction)
    }

    // MARK: Nudge

    /// Plays the demo after a short pause, then again whenever the card has been left alone a while.
    private func runNudges() async {
        var wait = SwipeNudge.firstDelay
        for _ in 0..<SwipeNudge.maxRuns {
            do {
                try await Task.sleep(for: wait)
                while isDragging || isFlying || lastTouch.map({ .now - $0 < SwipeNudge.idleBeforeReplay }) == true {
                    try await Task.sleep(for: .milliseconds(250))
                }
                try await SwipeNudge.perform { position in
                    guard !isDragging, !isFlying else { return false }
                    offset = position
                    return true
                }
            } catch {
                return
            }
            wait = SwipeNudge.idleBeforeReplay
        }
    }

    // MARK: Geometry

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

    /// Where a swiped card flies to, starting from its current drag `offset`.
    static func offscreen(_ direction: SwipeDirection, from offset: CGSize) -> CGSize {
        switch direction {
        case .left: CGSize(width: -640, height: offset.height + 60)
        case .right: CGSize(width: 640, height: offset.height + 60)
        case .up: CGSize(width: offset.width, height: -1100)
        }
    }
}

#if DEBUG
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
#endif
