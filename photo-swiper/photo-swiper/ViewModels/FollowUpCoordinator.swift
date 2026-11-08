import Foundation
import Observation

/// What follows a delete once the pile closes: the unlock offer for a free user, or a review
/// prompt for an unlocked one. Never both. `FeedViewModel` owns it and passes in the unlock and wall state.
@Observable
@MainActor
final class FollowUpCoordinator {
    /// RootView should ask for a review now. Set once the freed confirmation has closed.
    private(set) var isReviewPromptDue = false
    /// The last delete earned a review prompt; it waits for the pile to close.
    private var isReviewPromptQueued = false
    /// RootView should offer the unlock now: a free user's delete went through and the pile has closed.
    private(set) var isDeleteUpsellDue = false
    /// What the free user's last delete freed, for the offer's headline.
    private(set) var upsellFreedBytes: Int64 = 0
    /// A free user's delete earned the unlock offer; it waits for the pile to close.
    private var isDeleteUpsellQueued = false
    /// The wall has shown since launch. Every wall ends in a dismiss or an unlock, so the delete
    /// offer stays away for the rest of the process.
    private var wasWallShownThisSession = false

    /// Holds the delete count, when the offer last showed, and which version was asked for a review.
    private let defaults: UserDefaults
    /// Where the offer's interval comes from.
    private let freeTier: FreeTierTunables
    private let now: () -> Date

    init(defaults: UserDefaults, freeTier: FreeTierTunables, now: @escaping () -> Date) {
        self.defaults = defaults
        self.freeTier = freeTier
        self.now = now
    }

    /// The wall opened. The delete offer stays away for the rest of the process.
    func wallShown() {
        wasWallShownThisSession = true
    }

    /// Counts the delete and queues what follows it once the pile closes: the unlock offer for a free
    /// user (throttled, see `isDeleteUpsellAllowed`), or a review prompt if the delete earned one (see `ReviewPrompt`). Never both.
    func queueFollowUp(freed: Int64, isUnlocked: Bool, isWallPresented: Bool, purchasedThisLaunch: Bool) {
        let prior = defaults.integer(forKey: DefaultsKey.deleteCount)
        defaults.set(prior + 1, forKey: DefaultsKey.deleteCount)
        isReviewPromptQueued = false
        isDeleteUpsellQueued = false
        guard !isWallPresented else { return }
        if !isUnlocked {
            // Free users never get the review prompt, offer or not.
            guard isDeleteUpsellAllowed else { return }
            upsellFreedBytes = freed
            isDeleteUpsellQueued = true
            return
        }
        guard !purchasedThisLaunch else { return }
        isReviewPromptQueued = ReviewPrompt.isEligible(
            freedBytes: freed,
            priorDeletes: prior,
            lastAskedVersion: defaults.string(forKey: DefaultsKey.reviewPromptVersion),
            currentVersion: AppInfo.version
        )
    }

    /// The pile's freed confirmation has closed: the review prompt or unlock offer the delete earned may show now.
    func releaseReviewPrompt() {
        if isDeleteUpsellQueued {
            isDeleteUpsellQueued = false
            isDeleteUpsellDue = true
        }
        if isReviewPromptQueued {
            isReviewPromptQueued = false
            isReviewPromptDue = true
        }
    }

    /// RootView showed the unlock offer after a delete, or decided not to. Only a shown offer
    /// starts the wait before the next one.
    func finishDeleteUpsell(shown: Bool) {
        isDeleteUpsellDue = false
        if shown { defaults.set(now(), forKey: DefaultsKey.deleteUpsellShownAt) }
    }

    /// The delete offer shows after the first delete, then at most once per `postDeleteUpsellInterval`,
    /// and never once the wall has shown this session.
    private var isDeleteUpsellAllowed: Bool {
        guard !wasWallShownThisSession else { return false }
        guard let last = defaults.object(forKey: DefaultsKey.deleteUpsellShownAt) as? Date else { return true }
        return now().timeIntervalSince(last) >= freeTier.limits.postDeleteUpsellInterval
    }

    /// RootView handled the due prompt. `asked` records this version, so it won't ask again until the next.
    func finishReviewPrompt(asked: Bool) {
        isReviewPromptDue = false
        if asked { defaults.set(AppInfo.version, forKey: DefaultsKey.reviewPromptVersion) }
    }

    // MARK: Admin Tools

    /// The next delete offers the unlock again: forgets when it last showed and that the wall showed this session.
    func adminResetDeleteUpsell() {
        defaults.removeObject(forKey: DefaultsKey.deleteUpsellShownAt)
        wasWallShownThisSession = false
    }

    /// Gives a raised post-delete offer a plausible headline.
    func adminPickFreedBytes() {
        upsellFreedBytes = Int64.random(in: 20_000_000...3_000_000_000)
    }
}
