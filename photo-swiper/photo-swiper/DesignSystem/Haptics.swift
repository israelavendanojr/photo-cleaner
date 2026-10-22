import UIKit

/// The app's haptic moments.
@MainActor
enum Haptics {
    /// A drag crosses a commit threshold.
    static func threshold() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Moving on to the next onboarding step.
    static func advance() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Photo access was granted (full or limited).
    static func accessGranted() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Something was added to the "to clear" pile.
    static func delete() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
    }

    /// The final, confirmed delete.
    static func confirm() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// The unlock was bought or restored.
    static func unlocked() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// A different tab was picked.
    static func tabChange() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
