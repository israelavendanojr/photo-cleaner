import UIKit

/// The app's three haptic moments.
@MainActor
enum Haptics {
    /// A drag crosses a commit threshold.
    static func threshold() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Something was added to the "to clear" pile.
    static func delete() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
    }

    /// The final, confirmed delete.
    static func confirm() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
