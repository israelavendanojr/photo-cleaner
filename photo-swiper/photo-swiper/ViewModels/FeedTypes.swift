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

/// "Edit queued · saves ~335 MB · Undo", shown for a few seconds after an edit from the feed.
struct TrimToast: Equatable {
    let id = UUID()
    let savedBytes: Int64
    /// A Live Photo's flatten (JUN-79) rather than a video's edit, which the toast names.
    var isFlatten = false
}

/// What a card's Share button shows (JUN-8). No button at all is nil: the feature is off, or it's an Admin
/// Tools mock card that isn't in the library.
enum ShareButtonState: Equatable {
    case ready
    /// Tapping opens the paywall.
    case locked
    /// The file is being prepared; tapping again cancels.
    case preparing
}

/// A prepared file waiting for the share sheet. Its folder is removed when the sheet closes (`shareFinished`).
struct SharePayload: Identifiable, Equatable {
    let id = UUID()
    let itemID: LibraryItem.ID
    let url: URL
}

/// Why a share didn't happen, shown as a toast for a few seconds.
struct ShareNotice: Equatable {
    let id = UUID()
    let text: String
}

/// Where clearing the bin is in making the edited copies: copy `index` of `count` (a video's or a flattened still), `fraction` of the way through it.
struct EditProgress: Equatable {
    let index: Int
    let count: Int
    var fraction: Double
}

/// A locked feature the user tried to commit, which opens the paywall. `cardID` is the bundle card that
/// was swiped or reviewed, or nil for a feature that isn't a card.
struct LockedPrompt: Equatable {
    let feature: TierFeature
    let cardID: FeedCard.ID?
}

/// What the full-screen video offers for editing: trimming and compressing (each a feature that can be
/// off), whether either is locked (shown and previewed, but saving it opens the paywall), and the
/// compression levels' current settings.
struct VideoEditOptions: Equatable {
    var canTrim = true
    var canCompress = true
    var trimLocked = false
    var compressLocked = false
    var levels = CompressionLevels.standard

    /// Saving `edit` needs the unlock first: it trims with the trimmer locked, or compresses with
    /// compression locked. The viewer opens the paywall instead of saving it.
    func needsUnlock(_ edit: PendingEdit?) -> Bool {
        guard let edit else { return false }
        return (trimLocked && edit.range != nil) || needsUnlock(level: edit.compression)
    }

    /// Applying `level` needs the unlock first. Choosing none never does.
    func needsUnlock(level: CompressionLevel?) -> Bool { compressLocked && level != nil }
}

/// What the full-screen photo offers a Live Photo (JUN-79): Flatten, unless it's off for this plan. Locked,
/// it's still shown, and committing opens the paywall over the viewer instead.
struct PhotoEditOptions: Equatable {
    var canFlatten = false
    var flattenLocked = false
}

/// The card an undo just restored, and the side it left from.
struct ReturningCard: Equatable {
    let cardID: FeedCard.ID
    let direction: SwipeDirection
}
