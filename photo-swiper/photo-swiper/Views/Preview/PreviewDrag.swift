import SwiftUI

/// Swipe up or down to close a full-screen preview. The content follows the finger and shrinks
/// a little while the backdrop fades, revealing the feed underneath.
///
/// Feed the preview's drag into `track` and `end`; it only claims mostly-vertical drags.
struct DismissDrag {
    private(set) var offset: CGFloat = 0
    private var isTracking = false

    private static let distanceToClose: CGFloat = 120
    private static let flickToClose: CGFloat = 300
    private static let fullFade: CGFloat = 300

    var isActive: Bool { isTracking || offset != 0 }
    var progress: CGFloat { min(abs(offset) / Self.fullFade, 1) }
    var contentScale: CGFloat { 1 - progress * 0.15 }
    var backdropOpacity: Double { 1 - progress }
    /// Chrome gets out of the way almost immediately.
    var chromeOpacity: Double { max(1 - progress * 4, 0) }

    mutating func track(_ value: DragGesture.Value) {
        if !isTracking {
            // Decide once per drag, so a sideways start never turns into a dismiss.
            guard abs(value.translation.height) > abs(value.translation.width) else { return }
            isTracking = true
        }
        offset = value.translation.height
    }

    /// Whether the drag went far or fast enough to close. Otherwise springs back.
    mutating func end(_ value: DragGesture.Value) -> Bool {
        defer { isTracking = false }
        guard isTracking else { return false }
        if abs(value.translation.height) > Self.distanceToClose
            || abs(value.predictedEndTranslation.height) > Self.flickToClose {
            return true
        }
        withAnimation(DS.Motion.snapBack) { offset = 0 }
        return false
    }

    /// Lets go of a drag that was taken over by another gesture, like a pinch.
    mutating func cancel() {
        isTracking = false
        withAnimation(DS.Motion.snapBack) { offset = 0 }
    }
}
