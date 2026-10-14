import SwiftUI

/// The swipes a full-screen preview understands: down to close, and left, right, or up to
/// decide, exactly as on the card.
///
/// Closing: the content follows the finger and shrinks a little while the backdrop fades,
/// revealing the feed underneath. Deciding: the content tilts like a card and flies off.
/// Feed the preview's drag into `track` and `end`.
///
/// A class rather than a struct so changes made inside `withAnimation` animate: a struct in
/// `@State` is only written back after the mutating call returns, outside the animation.
@Observable
@MainActor
final class PreviewDrag {
    enum Outcome {
        case dismiss
        case decide(SwipeDirection)
    }

    private enum Mode { case dismiss, decide }

    private(set) var dismissOffset: CGFloat = 0
    /// Where a deciding drag has taken the content. Drives the Delete / Keep / Later stamps.
    private(set) var decideOffset: CGSize = .zero
    @ObservationIgnored private var mode: Mode?
    @ObservationIgnored private var armed: SwipeDirection?
    @ObservationIgnored private var isFlying = false

    private static let distanceToClose: CGFloat = 120
    private static let flickToClose: CGFloat = 300
    private static let fullFade: CGFloat = 300

    var offset: CGSize { CGSize(width: decideOffset.width, height: decideOffset.height + dismissOffset) }
    var rotation: Double { min(max(decideOffset.width / 32, -12), 12) }

    private var dismissProgress: CGFloat { min(abs(dismissOffset) / Self.fullFade, 1) }
    private var decideProgress: CGFloat {
        let distance = max(abs(decideOffset.width) / SwipeThresholds.horizontal, -decideOffset.height / SwipeThresholds.up)
        return min(max(distance, 0), 1)
    }

    var contentScale: CGFloat { 1 - dismissProgress * 0.15 }
    var backdropOpacity: Double { 1 - dismissProgress }
    /// Chrome gets out of the way almost immediately.
    var chromeOpacity: Double { max(1 - max(dismissProgress * 4, decideProgress * 2), 0) }

    func track(_ value: DragGesture.Value) {
        guard !isFlying else { return }
        let translation = value.translation
        if mode == nil {
            // Decide once per drag, so a sideways start never turns into a close and vice versa.
            guard translation != .zero else { return }
            mode = translation.height > abs(translation.width) ? .dismiss : .decide
        }
        switch mode {
        case .dismiss:
            dismissOffset = translation.height
        case .decide:
            decideOffset = translation
            let direction = SwipeThresholds.armed(translation)
            if direction != armed {
                armed = direction
                if direction != nil { Haptics.threshold() }
            }
        case nil:
            break
        }
    }

    /// What the drag amounts to once released. With no outcome, springs back.
    func end(_ value: DragGesture.Value) -> Outcome? {
        defer {
            mode = nil
            armed = nil
        }
        guard !isFlying else { return nil }
        switch mode {
        case .dismiss:
            if value.translation.height > Self.distanceToClose
                || value.predictedEndTranslation.height > Self.flickToClose {
                return .dismiss
            }
        case .decide:
            if let direction = SwipeThresholds.commit(value.translation, predicted: value.predictedEndTranslation) {
                return .decide(direction)
            }
        case nil:
            return nil
        }
        springBack()
        return nil
    }

    /// Sends the content off screen like a swiped card, then calls `completion`.
    func flyOut(_ direction: SwipeDirection, completion: @escaping () -> Void) {
        guard !isFlying else { return }
        isFlying = true
        withAnimation(DS.Motion.flyOut) {
            decideOffset = SwipeThresholds.offscreen(direction, from: decideOffset)
        } completion: {
            completion()
        }
    }

    /// Lets go of a drag that was taken over by another gesture, like a pinch.
    func cancel() {
        mode = nil
        armed = nil
        springBack()
    }

    private func springBack() {
        withAnimation(DS.Motion.snapBack) {
            dismissOffset = 0
            decideOffset = .zero
        }
    }
}
