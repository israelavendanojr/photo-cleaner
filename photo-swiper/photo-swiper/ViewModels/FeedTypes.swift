import Foundation

// The feed's small value types, at the top level so collaborators (`SwipeGate`, `OnboardingFlow`)
// and views name them without depending on `FeedViewModel`.

/// Where the app is: what `RootView` shows.
enum FeedPhase: Equatable {
    case loading
    /// First launch: explains the app before the system asks for photo access.
    case onboarding
    /// The user denied photo access.
    case noAccess
    case feed
    /// The whole library is reviewed: a page build found nothing to show.
    case caughtUp
}

/// Where a purchase or restore from the wall or Settings is.
enum PaywallStatus: Equatable {
    case idle, purchasing, restoring, purchaseFailed
    /// Ask to Buy: waiting for approval. Unlocks on its own if approved.
    case purchasePending
    /// Restore outcomes. A restore that unlocks also closes the wall.
    case restored, nothingToRestore, restoreFailed
}

/// Where onboarding is. `intro` is Welcome and the photo access primer, which the view steps between;
/// the rest follow once access is granted, each only when it applies.
enum OnboardingStep: Equatable {
    case intro
    /// Offers refill reminders, before the system has been asked.
    case notifications
    /// The unlock, with a way to carry on for free. Never shown once unlocked.
    case upsell
}

/// The "+3.4 MB" chip shown briefly after a delete.
struct DeleteChip: Equatable {
    let id = UUID()
    let bytes: Int64
}

/// The card an undo just restored, and the side it left from.
struct ReturningCard: Equatable {
    let cardID: FeedCard.ID
    let direction: SwipeDirection
}
