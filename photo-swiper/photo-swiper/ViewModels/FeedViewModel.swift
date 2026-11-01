import Foundation
import Observation

/// Owns the deck: cards, decisions, undo, and the running totals.
///
/// The deck is endless. When few cards are left ahead, the next page is built in the background
/// and appended; it only ends at caught up, when a page comes back empty.
/// Views read from it and call its intents. Animation and haptics stay in the views.
/// Every decision is written through to `store` as it happens, so relaunching resumes in place.
@Observable
@MainActor
final class FeedViewModel {
    enum Phase: Equatable {
        case loading
        /// First launch: explains the app before the system asks for photo access.
        case onboarding
        /// The user denied photo access.
        case noAccess
        case feed
        /// The whole library is reviewed: a page build found nothing to show.
        case caughtUp
    }

    enum PaywallStatus: Equatable {
        case idle, purchasing, restoring, purchaseFailed
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

    private struct Snapshot {
        var index: Int
        var decisions: [LibraryItem.ID: Decision]
        var marks: [SimilarGroup.ID: Set<LibraryItem.ID>]
        let drafts: [FeedCard.ID: [LibraryItem.ID: Decision]]
        let cardID: FeedCard.ID
        let direction: SwipeDirection
        /// Saved decisions for the card's items before the swipe; nil where there were none.
        var stored: [LibraryItem.ID: StoredDecision?]
        /// The swipe spent one from the allowance, so undo gives it back.
        let charged: Bool
    }

    // MARK: State

    private(set) var phase: Phase = .loading
    private(set) var session: Session?
    private(set) var index = 0
    private(set) var decisions: [LibraryItem.ID: Decision] = [:]
    private(set) var deleteChip: DeleteChip?
    private(set) var returningCard: ReturningCard?
    private(set) var stats = LibraryStats(totalItems: 0, reviewedItems: 0, freedBytes: 0)
    private(set) var access = LibraryAccess.full
    /// The system access prompt is up.
    private(set) var isRequestingAccess = false
    /// Access was just granted from onboarding and the first session is being built.
    /// Onboarding stays up meanwhile instead of a loading screen.
    private(set) var isPreparingFirstSession = false
    /// Photo access was granted from onboarding. The primer can't be left backward from here.
    private(set) var isOnboardingAccessGranted = false
    private(set) var onboardingStep = OnboardingStep.intro
    /// Onboarding will offer reminders after photo access. Re-checked when it gets there.
    private(set) var offersReminderStep = false
    /// Onboarding stays up after access is granted until its last step, while the deck is dealt underneath.
    private var holdsOnboarding = false
    /// Where the deck stands while onboarding holds the screen. Becomes `phase` when onboarding finishes.
    private var heldPhase: Phase?
    /// Debug builds: this onboarding is a replay, so every step shows whatever was decided before.
    private var isReplayingOnboarding = false
    private(set) var paywallStatus = PaywallStatus.idle
    /// The free swipes. Never spent or checked while unlocked.
    private(set) var allowance: SwipeAllowance
    /// "Out of swipes": the wall sheet over the feed, offering the unlock.
    var isWallPresented = false
    /// What's left to clear, worked out when the wall opens.
    private(set) var clutterEstimate: ClutterEstimate?
    /// The user tapped "Remind me" and the system said yes.
    private(set) var isRemindersOptedIn = false
    /// Notifications are turned off for the app, found on asking or by Settings checking.
    private(set) var areRemindersDenied = false
    /// Bought or restored since launch. The review prompt never follows a purchase.
    private(set) var purchasedThisLaunch = false
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
    /// A free user's swipe was refused because the pile is full. FeedView shows it.
    var isPileFullNoticePresented = false
    /// Something about the last delete the user should know, e.g. items the system refused.
    var deleteNotice: String?
    /// Applies to the next page built.
    var skipFavorites = true {
        didSet { store.skipFavorites = skipFavorites }
    }

    /// Similar-group overrides. Missing means "everything but the best pick".
    private var marks: [SimilarGroup.ID: Set<LibraryItem.ID>] = [:]
    /// One-by-one decisions for cards reviewed partway, by card. Applied when the card is swiped.
    private var drafts: [FeedCard.ID: [LibraryItem.ID: Decision]] = [:]
    private var history: [Snapshot] = []
    /// Pending deletes that are no longer in the deck: from earlier decks, or trimmed from behind this one.
    private var carriedPending: [LibraryItem] = []
    /// Items deleted, gone from the library, or undeletable. They stay decided but are no longer pending.
    private var settledIDs: Set<LibraryItem.ID> = []
    /// Totals the library reports itself; saved progress is added on top.
    private var libraryStats = LibraryStats(totalItems: 0, reviewedItems: 0, freedBytes: 0)
    private var chipTask: Task<Void, Never>?
    private var changesTask: Task<Void, Never>?
    /// A refill landed while no deck could take the strongest cards first; the next one dealt does.
    private var refilledSinceDeal = false
    /// Off while mocks play swipes through, so their setup doesn't spend the allowance.
    private var chargesSwipes = true
    /// The next page being built, while one is.
    private var pageTask: Task<Void, Never>?
    /// The last page build came back empty. No more are tried until the deck runs out.
    private var isLibraryExhausted = false
    /// Changes whenever a different deck is dealt, so a page built for the old one is dropped.
    private var deckGeneration = 0

    private let library: any PhotoLibraryProviding
    private let builder: any FeedBuilding
    private let store: any ProgressStoring
    private let entitlements: any EntitlementStore
    /// Runs the background feature index on the real library. Nil for mocks, previews, and tests.
    private let indexScheduler: IndexScheduler?
    /// Holds whether onboarding is done.
    private let defaults: UserDefaults
    /// Shortest time onboarding shows its "preparing" state, so the step change can be read.
    private let firstSessionMinimum: Duration
    private let now: () -> Date
    private let allowanceStore: SwipeAllowanceStore
    let allowanceTunables: SwipeAllowance.Tunables
    /// Nil where reminders can't be offered (tests, previews).
    private let notifier: RefillNotifier?

    /// - Parameter allowanceStore: Where the free swipes are saved. Nil keeps them in memory, starting full.
    init(
        library: any PhotoLibraryProviding,
        builder: any FeedBuilding,
        store: any ProgressStoring = InMemoryProgressStore(),
        entitlements: any EntitlementStore,
        indexScheduler: IndexScheduler? = nil,
        defaults: UserDefaults = .standard,
        firstSessionMinimum: Duration = .zero,
        allowanceStore: SwipeAllowanceStore? = nil,
        allowanceTunables: SwipeAllowance.Tunables = .standard,
        notifier: RefillNotifier? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.library = library
        self.builder = builder
        self.store = store
        self.entitlements = entitlements
        self.indexScheduler = indexScheduler
        self.defaults = defaults
        self.firstSessionMinimum = firstSessionMinimum
        self.now = now
        let allowanceStore = allowanceStore ?? SwipeAllowanceStore()
        self.allowanceStore = allowanceStore
        self.allowanceTunables = allowanceTunables
        self.notifier = notifier
        allowance = allowanceStore.load() ?? SwipeAllowance(tunables: allowanceTunables, now: now())
        isRemindersOptedIn = notifier?.isOptedIn ?? false
        skipFavorites = store.skipFavorites
    }

    /// Starts already loaded. Used by previews and launch-time setup.
    init(
        library: any PhotoLibraryProviding,
        builder: any FeedBuilding,
        store: any ProgressStoring = InMemoryProgressStore(),
        entitlements: any EntitlementStore,
        session: Session,
        stats: LibraryStats,
        allowanceStore: SwipeAllowanceStore? = nil,
        allowanceTunables: SwipeAllowance.Tunables = .standard,
        notifier: RefillNotifier? = nil
    ) {
        self.library = library
        self.builder = builder
        self.store = store
        self.entitlements = entitlements
        indexScheduler = nil
        defaults = .standard
        firstSessionMinimum = .zero
        now = Date.init
        let allowanceStore = allowanceStore ?? SwipeAllowanceStore()
        self.allowanceStore = allowanceStore
        self.allowanceTunables = allowanceTunables
        self.notifier = notifier
        allowance = allowanceStore.load() ?? SwipeAllowance(tunables: allowanceTunables, now: .now)
        isRemindersOptedIn = notifier?.isOptedIn ?? false
        skipFavorites = store.skipFavorites
        libraryStats = stats
        apply(session)
        refreshTotals()
    }

    // MARK: Derived

    var cards: [FeedCard] { session?.cards ?? [] }
    var currentCard: FeedCard? { cards.indices.contains(index) ? cards[index] : nil }
    var nextCard: FeedCard? { cards.indices.contains(index + 1) ? cards[index + 1] : nil }

    /// The deck ran out ahead of the next page; the deck shows "Finding more…" meanwhile.
    var isFindingMore: Bool { phase == .feed && currentCard == nil }

    /// "Still scanning" percentage, shown only early in the first deck.
    var scanningPercent: Int? {
        guard let start = session?.scanPercentAtStart, index < 10 else { return nil }
        return min(start + index * 4, 99)
    }

    var canUndo: Bool { !history.isEmpty && phase == .feed }

    var pendingItems: [LibraryItem] {
        let current = session?.items.filter { decisions[$0.id] == .delete } ?? []
        return (carriedPending + current).filter { !settledIDs.contains($0.id) }
    }
    var pendingBytes: Int64 { pendingItems.reduce(0) { $0 + $1.bytes } }
    var keptCount: Int { decisions.values.filter { $0 == .keep }.count }
    var laterCount: Int { decisions.values.filter { $0 == .later }.count }

    /// "Later" doesn't count as reviewed.
    var libraryReviewedCount: Int { stats.reviewedItems }
    var libraryReviewedFraction: Double {
        // Reviewed items deleted elsewhere still count, so this can overshoot a shrinking library.
        stats.totalItems == 0 ? 0 : min(1, Double(libraryReviewedCount) / Double(stats.totalItems))
    }
    var freedBytes: Int64 { stats.freedBytes }

    var isUnlocked: Bool { entitlements.isUnlocked }
    var displayPrice: String { entitlements.displayPrice }

    /// A card decision would go through. Unlocked, always.
    var canSwipe: Bool { isUnlocked || allowance.remaining > 0 }
    /// The most the pile holds before deleting, e.g. 50; nil when unlocked, where it has no limit.
    var pileLimit: Int? { isUnlocked ? nil : Self.freePileCap }
    /// A free user's pile is at its limit, so only keeps and laters go through.
    var isPileFull: Bool { pileLimit.map { pendingItems.count >= $0 } ?? false }
    /// Free swipes left; nil when unlocked, where nothing is counted.
    var swipesLeft: Int? { isUnlocked ? nil : allowance.remaining }
    /// When the next refill lands; nil when unlocked or full.
    var nextRefillAt: Date? { isUnlocked ? nil : allowance.nextRefillAt(allowanceTunables) }
    /// Days of free swipes it would take to get through the likely clears.
    var daysToFinish: Double? { clutterEstimate?.daysToFinish(swipesPerDay: allowanceTunables.swipesPerDay) }
    /// "Remind me when swipes are back" can be offered.
    var canRemind: Bool { notifier != nil }

    /// Onboarding's last step is done but the first deck is still being built. The step shows progress meanwhile.
    var isLeavingOnboarding: Bool { phase == .onboarding && isOnboardingAccessGranted && !holdsOnboarding }
    /// Onboarding will end on the unlock offer.
    var offersUpsellStep: Bool { !isUnlocked || isReplayingOnboarding }
    /// The deck's phase, even while onboarding holds the screen. Paging and reordering go by this;
    /// swiping still needs `phase` itself to be the feed.
    private var deckPhase: Phase { heldPhase ?? phase }

    /// The number the next page gets. Pages are numbered across decks, so saved decisions can tell them apart.
    private var nextPageNumber: Int { max(session?.number ?? 0, store.lastSessionNumber()) + 1 }

    // MARK: Card helpers

    /// Items in a similar group that a left swipe would clear.
    /// A partial one-by-one review overrides the marks of the shots it reached.
    func markedForClearing(in group: SimilarGroup) -> Set<LibraryItem.ID> {
        var marked = marks[group.id] ?? Set(group.others.map(\.id))
        for (id, decision) in drafts[group.id] ?? [:] {
            if decision == .delete { marked.insert(id) } else { marked.remove(id) }
        }
        return marked
    }

    /// Bytes a left swipe on this card would add to the pile.
    func bytesToClear(for card: FeedCard) -> Int64 {
        let outcome = itemDecisions(for: card, direction: .left)
        return card.items.filter { outcome[$0.id] == .delete }.reduce(0) { $0 + $1.bytes }
    }

    /// Overlay text while dragging, e.g. "Delete · 3.4 MB" or "Clear 5".
    func swipeLabel(_ direction: SwipeDirection, for card: FeedCard) -> String {
        switch (direction, card) {
        case (.up, _): "Later"
        case (.left, .photo(let item)), (.left, .video(let item)): "Delete · \(Format.size(item.bytes))"
        case (.left, .batch(let batch)) where drafts[batch.id] == nil: "Clear all \(batch.items.count)"
        case (.left, .similar), (.left, .batch):
            switch itemDecisions(for: card, direction: .left).values.filter({ $0 == .delete }).count {
            case 0: "Keep all \(card.items.count)"
            case let n: "Clear \(n)"
            }
        case (.right, .photo), (.right, .video): "Keep"
        case (.right, _): "Keep all \(card.items.count)"
        }
    }

    // MARK: Intents

    /// Called at launch, from onboarding's Allow button, and again from the no-access screen
    /// when the app returns from Settings. A first launch stops at onboarding without prompting.
    func start() async {
        guard phase == .loading || phase == .noAccess || phase == .onboarding, !isRequestingAccess,
              !isOnboardingAccessGranted else { return }
        if phase == .loading, needsOnboarding {
            #if DEBUG
            isReplayingOnboarding = defaults.bool(forKey: DefaultsKey.debugShowOnboarding)
            #endif
            phase = .onboarding
            // Settled long before the page dots fade in, without holding up onboarding at launch.
            offersReminderStep = await reminderStepApplies()
            return
        }
        let fromOnboarding = phase == .onboarding
        if fromOnboarding {
            // Written before access is asked for, so a relaunch from any later step opens the feed.
            defaults.set(true, forKey: DefaultsKey.hasOnboarded)
            defaults.removeObject(forKey: DefaultsKey.debugShowOnboarding)
        }
        isRequestingAccess = true
        access = await library.requestAccess()
        isRequestingAccess = false
        guard access != .denied else {
            phase = .noAccess
            return
        }
        if fromOnboarding {
            isPreparingFirstSession = true
            isOnboardingAccessGranted = true
            holdsOnboarding = true
        } else {
            phase = .loading
        }
        indexScheduler?.accessGranted()
        let clock = ContinuousClock()
        let started = clock.now
        libraryStats = await library.stats()
        observeLibraryChanges()
        // The saved deck always comes back, on the exact card. With nothing saved, or nothing in it, a fresh one is dealt.
        let saved = store.loadSession().flatMap { $0.session.cards.isEmpty ? nil : $0 }
        // Captions can do without place names for the first page; they arrive with the next.
        let next = saved == nil
            ? await makeSession(number: store.lastSessionNumber() + 1, placeBudget: fromOnboarding ? .zero : nil)
            : nil
        if fromOnboarding {
            let remaining = firstSessionMinimum - (clock.now - started)
            if remaining > .zero { try? await Task.sleep(for: remaining) }
        }
        if let saved {
            await restore(saved)
            // Saved with every card decided: the next page is dealt before the feed shows.
            if deckPhase == .feed, currentCard == nil { await appendPage() }
        } else if let next {
            apply(next)
        }
        isPreparingFirstSession = false
        refreshTotals()
        // Credits refills from time away, which also puts the strongest cards first.
        refreshAllowance()
        if isUnlocked { notifier?.cancelAll(now: now()) }
        fillIfNeeded()
    }

    /// Only before the user has been asked for photo access, unless a debug reset asked for it again.
    private var needsOnboarding: Bool {
        guard !defaults.bool(forKey: DefaultsKey.hasOnboarded) else { return false }
        #if DEBUG
        if defaults.bool(forKey: DefaultsKey.debugShowOnboarding) { return true }
        #endif
        return library.needsAccessPrompt()
    }

    /// Moves onboarding past photo access to the next step that applies, or finishes it.
    /// Each step is checked as it's reached, so e.g. a restore that lands meanwhile skips the offer.
    func advanceOnboarding() async {
        guard phase == .onboarding, isOnboardingAccessGranted else { return }
        if onboardingStep == .intro {
            // Once offered it stays, so coming back through after answering iOS still shows it.
            if !offersReminderStep { offersReminderStep = await reminderStepApplies() }
            if offersReminderStep {
                onboardingStep = .notifications
                return
            }
        }
        if onboardingStep != .upsell, offersUpsellStep {
            onboardingStep = .upsell
            return
        }
        finishOnboarding()
    }

    /// Back one step after photo access: the offer to reminders where they were shown, either to the primer.
    func goBackInOnboarding() {
        guard canGoBackInOnboarding else { return }
        onboardingStep = onboardingStep == .upsell && offersReminderStep ? .notifications : .intro
    }

    /// Onboarding can step back from where it is. Not mid-purchase, nor once the user has finished.
    var canGoBackInOnboarding: Bool {
        phase == .onboarding && holdsOnboarding && onboardingStep != .intro && !isPurchaseBusy
    }

    /// Lets the feed replace onboarding. If the first deck is still being built, `start()` shows it
    /// once it's ready, and `isLeavingOnboarding` holds meanwhile.
    private func finishOnboarding() {
        guard holdsOnboarding else { return }
        holdsOnboarding = false
        isReplayingOnboarding = false
        guard let held = heldPhase else { return }
        heldPhase = nil
        phase = held
        fillIfNeeded()
    }

    /// Reminders can be offered and the system hasn't asked yet, since iOS only asks once.
    /// A debug replay offers them regardless.
    private func reminderStepApplies() async -> Bool {
        guard let notifier else { return false }
        return isReplayingOnboarding ? true : await notifier.canAsk()
    }

    /// Sets the deck's phase, or holds it while onboarding is still up.
    private func enterDeckPhase(_ next: Phase) {
        if holdsOnboarding { heldPhase = next } else { phase = next }
    }

    /// Whether swiping the current card this way would go through. The deck asks before letting a card fly.
    /// False out of swipes, or for a free user when it would take the pile past `freePileCap`.
    func canDecide(_ direction: SwipeDirection) -> Bool {
        guard canSwipe || !chargesSwipes else { return false }
        guard let card = currentCard else { return true }
        return fitsInPile(itemDecisions(for: card, direction: direction))
    }

    /// Whether a finished one-by-one review of the current card would go through, like `canDecide`.
    func canDecideIndividually(_ outcome: [LibraryItem.ID: Decision]) -> Bool {
        guard canSwipe || !chargesSwipes else { return false }
        guard let card = currentCard, let complete = completed(outcome, for: card) else { return true }
        return fitsInPile(complete)
    }

    /// The deck refused a swipe: opens the wall when out of swipes, or says the pile is full.
    func refuse(_ direction: SwipeDirection) {
        refreshAllowance()
        if !canSwipe, chargesSwipes {
            presentWall()
        } else if !isUnlocked {
            isPileFullNoticePresented = true
        }
    }

    /// Out of free swipes, nothing is committed and the wall opens instead.
    /// A free user's delete that won't fit in the pile is refused whole, and says so.
    func decide(_ direction: SwipeDirection) {
        guard phase == .feed, let card = currentCard, admitSwipe() else { return }
        let outcome = itemDecisions(for: card, direction: direction)
        guard fitsInPile(outcome) else {
            isPileFullNoticePresented = true
            return
        }
        commit(outcome, card: card, direction: direction)
    }

    /// Settles the current batch or similar-shots card from a one-by-one review. Items left out
    /// count as "later" in a batch, and follow their marks in a similar set.
    /// It costs one swipe like any card; out of swipes, or past a free user's pile limit, the review
    /// is kept as a draft and the wall or the pile notice opens.
    func decideIndividually(_ outcome: [LibraryItem.ID: Decision]) {
        guard phase == .feed, let card = currentCard, let complete = completed(outcome, for: card) else { return }
        guard admitSwipe() else {
            saveDraft(outcome, for: card.id)
            return
        }
        guard fitsInPile(complete) else {
            saveDraft(outcome, for: card.id)
            isPileFullNoticePresented = true
            return
        }
        commit(complete, card: card, direction: complete.values.contains(.delete) ? .left : .right)
    }

    /// Decisions from an unfinished one-by-one review of this card.
    /// Batch drafts saved before similar sets had reviews are keyed by batch ID, which is the card ID.
    func draft(for cardID: FeedCard.ID) -> [LibraryItem.ID: Decision] {
        drafts[cardID] ?? [:]
    }

    func saveDraft(_ outcome: [LibraryItem.ID: Decision], for cardID: FeedCard.ID) {
        drafts[cardID] = outcome.isEmpty ? nil : outcome
        saveProgress()
    }

    /// Also changes a partial review's decision for the shot, so the card and the review agree.
    func toggleMark(_ itemID: LibraryItem.ID, in group: SimilarGroup) {
        var marked = markedForClearing(in: group)
        if marked.contains(itemID) { marked.remove(itemID) } else { marked.insert(itemID) }
        marks[group.id] = marked
        if drafts[group.id] != nil {
            drafts[group.id]?[itemID] = marked.contains(itemID) ? .delete : .keep
        }
        saveProgress()
    }

    func undo() {
        guard canUndo, let last = history.popLast() else { return }
        index = last.index
        decisions = last.decisions
        marks = last.marks
        drafts = last.drafts
        store.save(last.stored)
        if last.charged {
            allowance.refund(at: now(), allowanceTunables)
            allowanceStore.save(allowance)
        }
        returningCard = ReturningCard(cardID: last.cardID, direction: last.direction)
        dismissChip()
        phase = .feed
        saveProgress()
        refreshTotals(includingFreed: false)
    }

    /// Takes items out of the pile by keeping them instead, here, in the store, and in undo history.
    func keep(_ items: [LibraryItem]) {
        let pending = Set(pendingItems.map(\.id))
        let items = items.filter { pending.contains($0.id) }
        guard !items.isEmpty else { return }
        let ids = Set(items.map(\.id))
        for id in ids where decisions[id] == .delete { decisions[id] = .keep }
        carriedPending.removeAll { ids.contains($0.id) }

        let saved = store.decisions(for: ids)
        let decidedAt = now()
        store.save(Dictionary(uniqueKeysWithValues: items.map { item in
            let sessionNumber = saved[item.id]?.sessionNumber ?? session?.number ?? 0
            return (item.id, StoredDecision(decision: .keep, decidedAt: decidedAt, sessionNumber: sessionNumber, item: item))
        }))

        // Undoing a later swipe must not put them back in the pile.
        for i in history.indices {
            for id in ids {
                if history[i].decisions[id] == .delete { history[i].decisions[id] = .keep }
                if case .some(.some(var record)) = history[i].stored[id], record.decision == .delete {
                    record.decision = .keep
                    history[i].stored[id] = record
                }
            }
            for group in history[i].marks.keys { history[i].marks[group]?.subtract(ids) }
        }
        for group in marks.keys { marks[group]?.subtract(ids) }
        saveProgress()
        refreshTotals(includingFreed: false)
    }

    /// Deletes some of the pile, from the pending screen. The deck carries on,
    /// and the rest stays pending. Returns the bytes freed, or nil if nothing was deleted,
    /// including when the user cancels the system prompt.
    @discardableResult
    func deleteNow(_ items: [LibraryItem]) async -> Int64? {
        let pending = Set(pendingItems.map(\.id))
        guard let deletedItems = await delete(items.filter { pending.contains($0.id) }) else { return nil }
        let ids = Set(deletedItems.map(\.id))
        settle(ids, as: .deleted)
        carriedPending.removeAll { ids.contains($0.id) }
        // A deleted photo can't be swiped again.
        history.removeAll()
        saveProgress()
        refreshTotals()
        let freed = deletedItems.reduce(0) { $0 + $1.bytes }
        queueFollowUp(freed: freed)
        return freed
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

    /// RootView showed the unlock offer after a delete, or decided not to.
    func finishDeleteUpsell() {
        isDeleteUpsellDue = false
    }

    /// RootView handled the due prompt. `asked` records this version, so it won't ask again until the next.
    func finishReviewPrompt(asked: Bool) {
        isReviewPromptDue = false
        if asked { defaults.set(AppInfo.version, forKey: DefaultsKey.reviewPromptVersion) }
    }

    /// "Check again" from caught up: deals a fresh deck if anything turned up, e.g. new photos
    /// or "later" items back from their cooldown. Never gated: only swipes are.
    func checkAgain() async {
        guard phase == .caughtUp else { return }
        let next = await makeSession(number: nextPageNumber)
        guard !next.cards.isEmpty else { return }
        apply(next)
    }

    // MARK: Swipe allowance

    /// Opens the wall: the countdown, what's left, and the unlock. The deck stays underneath.
    func presentWall() {
        refreshAllowance()
        if !isWallPresented { paywallStatus = .idle }
        isWallPresented = true
        Task { await refreshEstimate() }
    }

    /// "Not now". The next refused swipe opens it again.
    func dismissWall() {
        guard !isPurchaseBusy else { return }
        isWallPresented = false
    }

    /// A purchase or restore is running. The wall and the Settings unlock can't close meanwhile.
    var isPurchaseBusy: Bool { paywallStatus == .purchasing || paywallStatus == .restoring }

    /// Buys the unlock, from the wall or Settings. Closes the wall, so the current card can be swiped
    /// straight away. False if it didn't go through.
    @discardableResult
    func purchaseUnlock() async -> Bool {
        guard !isPurchaseBusy else { return false }
        paywallStatus = .purchasing
        guard await entitlements.unlock(), entitlements.isUnlocked else {
            paywallStatus = .purchaseFailed
            return false
        }
        didUnlock()
        paywallStatus = .idle
        return true
    }

    /// Restores an earlier purchase, from the wall or Settings. True if the app is now unlocked;
    /// `paywallStatus` says what was found either way.
    @discardableResult
    func restorePurchases() async -> Bool {
        guard !isPurchaseBusy else { return false }
        paywallStatus = .restoring
        switch await entitlements.restore() {
        case .restored where entitlements.isUnlocked:
            didUnlock()
            paywallStatus = .restored
            return true
        case .nothingToRestore:
            paywallStatus = .nothingToRestore
        case .restored, .failed:
            paywallStatus = .restoreFailed
        }
        return false
    }

    /// Clears a finished purchase or restore message, e.g. when Settings opens. Not while one runs.
    func resetPurchaseStatus() {
        guard !isPurchaseBusy else { return }
        paywallStatus = .idle
    }

    /// Credits any refills owed by now. Called on returning to the app and while a countdown shows.
    /// When a refill lands, the strongest cards waiting move to the front.
    func refreshAllowance() {
        guard !isUnlocked else { return }
        var settled = allowance
        let refilled = settled.settle(at: now(), allowanceTunables)
        guard settled != allowance else { return }
        allowance = settled
        allowanceStore.save(settled)
        if refilled { frontLoad() }
    }

    /// "Remind me when swipes are back". Asks for notification permission, then schedules if already out.
    func remindWhenSwipesAreBack() async {
        guard let notifier else { return }
        isRemindersOptedIn = await notifier.optIn()
        areRemindersDenied = !isRemindersOptedIn
        if isRemindersOptedIn, allowance.remaining == 0 { await scheduleReminders() }
    }

    /// The Settings switch. On asks for permission the same way the wall does; off cancels what's scheduled.
    func setRemindersEnabled(_ on: Bool) async {
        guard let notifier else { return }
        if on {
            await remindWhenSwipesAreBack()
        } else {
            notifier.optOut(now: now())
            isRemindersOptedIn = false
        }
    }

    /// Reads whether notifications are off in the Settings app, which can change while the app is away.
    func refreshReminderPermission() async {
        guard let notifier else { return }
        areRemindersDenied = await notifier.isDenied()
    }

    func clearReturningCard() {
        returningCard = nil
    }

    // MARK: Internals

    /// Counts the delete and queues what follows it once the pile closes: the unlock offer for a free
    /// user, or a review prompt if the delete earned one (see `ReviewPrompt`). Never both.
    private func queueFollowUp(freed: Int64) {
        let prior = defaults.integer(forKey: DefaultsKey.deleteCount)
        defaults.set(prior + 1, forKey: DefaultsKey.deleteCount)
        isReviewPromptQueued = false
        isDeleteUpsellQueued = false
        guard !isWallPresented else { return }
        if !isUnlocked {
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

    /// Bought or restored: reminders are moot and the wall, if up, closes.
    private func didUnlock() {
        notifier?.cancelAll(now: now())
        purchasedThisLaunch = true
        isWallPresented = false
    }

    /// Lets a card decision through, or refuses it and opens the wall when no swipes are left.
    private func admitSwipe() -> Bool {
        refreshAllowance()
        guard canSwipe || !chargesSwipes else {
            presentWall()
            return false
        }
        return true
    }

    /// Spends one swipe for a card decision. Unlocked, nothing is counted. True if one was spent.
    private func spendSwipe() -> Bool {
        guard chargesSwipes, !isUnlocked, allowance.spend(at: now(), allowanceTunables) else { return false }
        allowanceStore.save(allowance)
        // Back and swiping before a reminder fired: it's no longer needed.
        notifier?.cancelAll(now: now())
        if allowance.remaining == 0, isRemindersOptedIn {
            Task { await scheduleReminders() }
        }
        return true
    }

    private func scheduleReminders() async {
        guard let notifier, !isUnlocked, let next = allowance.nextRefillAt(allowanceTunables) else { return }
        if clutterEstimate == nil { await refreshEstimate() }
        await notifier.scheduleOnEmpty(
            nextRefillAt: next,
            fullAt: allowance.fullAt(allowanceTunables),
            tunables: allowanceTunables,
            estimate: clutterEstimate,
            now: now()
        )
    }

    private func refreshEstimate() async {
        guard var estimate = await builder.clutterEstimate(excluding: store.excludedFromNewSession(asOf: now()), now: now()) else { return }
        // Similar sets still ahead in the deck count too.
        estimate.similarGroupCount += cards.dropFirst(index).filter { if case .similar = $0 { true } else { false } }.count
        clutterEstimate = estimate
    }

    /// Moves the strongest cards still to come to the front, or leaves it to the next deck dealt.
    private func frontLoad() {
        guard deckPhase == .feed, var current = session else {
            refilledSinceDeal = true
            return
        }
        refilledSinceDeal = false
        let reordered = FrontLoad.reordered(current.cards, from: index)
        guard reordered != current.cards else { return }
        current.cards = reordered
        session = current
        saveProgress()
    }

    /// Records per-item decisions for the current card and moves on.
    /// `direction` is the side the card left from, so undo brings it back the same way.
    private func commit(_ outcome: [LibraryItem.ID: Decision], card: FeedCard, direction: SwipeDirection) {
        let ids = card.items.map(\.id)
        let before = store.decisions(for: Set(ids))
        let stored = Dictionary(uniqueKeysWithValues: ids.map { ($0, before[$0]) })
        let charged = spendSwipe()
        history.append(Snapshot(index: index, decisions: decisions, marks: marks, drafts: drafts, cardID: card.id, direction: direction, stored: stored, charged: charged))
        decisions.merge(outcome) { _, new in new }
        drafts[card.id] = nil
        returningCard = nil

        let decidedAt = now()
        let sessionNumber = session?.number ?? 0
        store.save(Dictionary(uniqueKeysWithValues: card.items.compactMap { item in
            outcome[item.id].map { (item.id, StoredDecision(decision: $0, decidedAt: decidedAt, sessionNumber: sessionNumber, item: item)) }
        }))

        let cleared = card.items.filter { outcome[$0.id] == .delete }.reduce(0) { $0 + $1.bytes }
        if cleared > 0 { showChip(bytes: cleared) }

        index += 1
        saveProgress()
        refreshTotals(includingFreed: false)
        fillIfNeeded()
    }

    // MARK: Paging

    /// Returns once the page being built, if any, has landed. For tests.
    func waitForPage() async {
        while let task = pageTask { await task.value }
    }

    /// Starts building the next page once few undecided cards are left ahead.
    private func fillIfNeeded() {
        guard deckPhase == .feed, session != nil, pageTask == nil, cards.count - index <= Self.pageAhead else { return }
        // An empty build isn't retried while cards remain; running out tries once more.
        guard !isLibraryExhausted || currentCard == nil else { return }
        let generation = deckGeneration
        pageTask = Task { [weak self] in
            await self?.appendPage()
            // A different deck dealt meanwhile has its own paging.
            guard let self, deckGeneration == generation else { return }
            pageTask = nil
            fillIfNeeded()
        }
    }

    /// Builds the next page and adds it to the end of the deck, with nothing already in it.
    /// An empty page with nothing left ahead is caught up.
    private func appendPage() async {
        let generation = deckGeneration
        let inDeck = Set(session?.items.map(\.id) ?? [])
        var options = FeedOptions(skipFavorites: skipFavorites, excluding: store.excludedFromNewSession(asOf: now()))
        options.excluding.formUnion(inDeck)
        options.excluding.formUnion(decisions.keys)
        let page = await builder.makeSession(number: nextPageNumber, options: options)
        guard generation == deckGeneration, deckPhase == .feed, var current = session else { return }

        // Anything dealt meanwhile stays out, so no item is ever in the deck twice.
        let taken = Set(current.items.map(\.id))
        let fresh = page.cards.compactMap { $0.removing(taken) }
        guard !fresh.isEmpty else {
            isLibraryExhausted = true
            if currentCard == nil { enterDeckPhase(.caughtUp) }
            return
        }
        isLibraryExhausted = false
        current.number = page.number
        current.cards += fresh
        if refilledSinceDeal {
            current.cards = FrontLoad.reordered(current.cards, from: index)
            refilledSinceDeal = false
        }
        session = current
        trimBehind()
        saveProgress()
    }

    /// Lets go of decided cards well behind the current one so the saved deck stays small.
    /// Their decisions are already stored; pending ones carry on in the pile.
    private func trimBehind() {
        let drop = index - Self.keptBehind
        guard drop > 0, var current = session else { return }
        let gone = current.cards.prefix(drop)
        let ids = Set(gone.flatMap(\.items).map(\.id))
        let cardIDs = Set(gone.map(\.id))
        carriedPending += gone.flatMap(\.items).filter { decisions[$0.id] == .delete && !settledIDs.contains($0.id) }
        current.cards.removeFirst(drop)
        session = current
        index -= drop
        decisions = decisions.filter { !ids.contains($0.key) }
        marks = marks.filter { !cardIDs.contains($0.key) }
        drafts = drafts.filter { !cardIDs.contains($0.key) }
        history = history.compactMap { snapshot in
            guard snapshot.index >= drop else { return nil }
            var snapshot = snapshot
            snapshot.index -= drop
            snapshot.decisions = snapshot.decisions.filter { !ids.contains($0.key) }
            snapshot.marks = snapshot.marks.filter { !cardIDs.contains($0.key) }
            return snapshot
        }
    }

    /// Per-item outcome of swiping a card in a direction.
    /// Items from a partial one-by-one review keep their decision; the rest follow the swipe.
    private func itemDecisions(for card: FeedCard, direction: SwipeDirection) -> [LibraryItem.ID: Decision] {
        let draft = drafts[card.id] ?? [:]
        let marked: Set<LibraryItem.ID>? = if case .similar(let group) = card { markedForClearing(in: group) } else { nil }
        return Dictionary(uniqueKeysWithValues: card.items.map { item in
            if let drafted = draft[item.id] { return (item.id, drafted) }
            let decision: Decision = switch direction {
            case .up: .later
            case .right: .keep
            case .left: marked.map { $0.contains(item.id) ? .delete : .keep } ?? .delete
            }
            return (item.id, decision)
        })
    }

    /// A one-by-one review's outcome for every item on the card. Items left out count as "later" in
    /// a batch, and follow their marks in a similar set. Nil for single photos and videos.
    private func completed(_ outcome: [LibraryItem.ID: Decision], for card: FeedCard) -> [LibraryItem.ID: Decision]? {
        let rest: (LibraryItem.ID) -> Decision
        switch card {
        case .batch:
            rest = { _ in .later }
        case .similar(let group):
            let marked = markedForClearing(in: group)
            rest = { marked.contains($0) ? .delete : .keep }
        case .photo, .video:
            return nil
        }
        return Dictionary(uniqueKeysWithValues: card.items.map { ($0.id, outcome[$0.id] ?? rest($0.id)) })
    }

    /// The pile can take these deletes: always when unlocked, and up to `freePileCap` items otherwise.
    /// Keeps and laters add nothing, so they always fit unless a partial review drafted deletes.
    private func fitsInPile(_ outcome: [LibraryItem.ID: Decision]) -> Bool {
        guard let limit = pileLimit, chargesSwipes else { return true }
        let pending = pendingItems
        let pendingIDs = Set(pending.map(\.id))
        let added = outcome.filter { $0.value == .delete && !pendingIDs.contains($0.key) }.count
        return added == 0 || pending.count + added <= limit
    }

    /// Asks the library to delete these and settles the ones that can't be. Returns what was
    /// actually deleted, or nil if nothing was (cancelled, failed, or none deletable).
    private func delete(_ items: [LibraryItem]) async -> [LibraryItem]? {
        guard !items.isEmpty else { return nil }
        let outcome: DeletionOutcome
        do {
            outcome = try await library.delete(items)
        } catch DeletionError.cancelled {
            return nil
        } catch {
            deleteNotice = "Couldn't delete right now. Nothing was removed."
            return nil
        }

        // Gone or undeletable items can't be cleared, so they leave the pile without counting as freed.
        settle(Set(outcome.missing), as: .gone)
        settle(Set(outcome.undeletable), as: .undeletable)
        if !outcome.undeletable.isEmpty {
            let n = outcome.undeletable.count
            deleteNotice = "\(n) \(n == 1 ? "item" : "items") can't be deleted from this app and stayed in your library."
        }

        let deleted = Set(outcome.deleted)
        let deletedItems = items.filter { deleted.contains($0.id) }
        return deletedItems.isEmpty ? nil : deletedItems
    }

    /// Takes items out of the pile for good, here and in the store.
    private func settle(_ ids: Set<LibraryItem.ID>, as settlement: Settlement) {
        guard !ids.isEmpty else { return }
        settledIDs.formUnion(ids)
        store.settle(ids, as: settlement)
    }

    private func observeLibraryChanges() {
        guard changesTask == nil else { return }
        let changes = library.vanishedItems()
        changesTask = Task { [weak self] in
            for await ids in changes { self?.forget(ids) }
        }
    }

    /// Drops items deleted outside the app from the pile and from cards not yet shown.
    /// The current and earlier cards stay put so undo history remains valid.
    private func forget(_ ids: Set<LibraryItem.ID>) {
        // Our own confirmed deletes come back through here too; they're already settled.
        let gone = ids.subtracting(settledIDs)
        guard !gone.isEmpty else { return }
        settle(gone, as: .gone)
        guard var current = session, current.cards.count > index + 1 else { return }
        current.cards = Array(current.cards.prefix(index + 1))
            + current.cards.dropFirst(index + 1).compactMap { $0.removing(gone) }
        session = current
        saveProgress()
        fillIfNeeded()
    }

    /// - Parameter placeBudget: Overrides how long to wait on place names; nil keeps the default.
    private func makeSession(number: Int, placeBudget: Duration? = nil) async -> Session {
        var options = FeedOptions(skipFavorites: skipFavorites, excluding: store.excludedFromNewSession(asOf: now()))
        if let placeBudget { options.placeBudget = placeBudget }
        return await builder.makeSession(number: number, options: options)
    }

    private func apply(_ next: Session) {
        var next = next
        if refilledSinceDeal {
            next.cards = FrontLoad.reordered(next.cards, from: 0)
            refilledSinceDeal = false
        }
        deckGeneration += 1
        pageTask?.cancel()
        pageTask = nil
        isLibraryExhausted = false
        session = next
        index = 0
        decisions = [:]
        marks = [:]
        drafts = [:]
        history = []
        let ids = Set(next.items.map(\.id))
        carriedPending = store.pile().filter { !ids.contains($0.id) }
        returningCard = nil
        dismissChip()
        enterDeckPhase(next.cards.isEmpty ? .caughtUp : .feed)
        saveProgress()
        fillIfNeeded()
    }

    /// Picks up the saved deck on the card the user left it at, dropping anything deleted outside
    /// the app while it was closed.
    private func restore(_ saved: SavedSession) async {
        var restored = saved.session
        var position = saved.index
        let gone = await library.missing(from: Set(restored.items.map(\.id)).union(store.pile().map(\.id)))
        if !gone.isEmpty {
            // Undo history starts empty, so earlier cards can be pruned too.
            var cards: [FeedCard] = []
            position = 0
            for (offset, card) in restored.cards.enumerated() {
                guard let kept = card.removing(gone) else { continue }
                cards.append(kept)
                if offset < saved.index { position += 1 }
            }
            restored.cards = cards
            store.settle(gone, as: .gone)
        }

        position = min(position, restored.cards.count)

        let ids = Set(restored.items.map(\.id))
        // Every card before the current one was swiped in this deck, so its saved decision is this deck's.
        // Cards ahead are undecided, whatever an older deck said about them.
        let swiped = Set(restored.cards.prefix(position).flatMap(\.items).map(\.id))
        let records = store.decisions(for: swiped)
        deckGeneration += 1
        isLibraryExhausted = false
        session = restored
        index = position
        marks = saved.marks
        drafts = saved.drafts
        decisions = records.mapValues(\.decision)
        settledIDs = Set(records.filter { $0.value.settlement != nil }.keys).union(gone)
        carriedPending = store.pile().filter { !ids.contains($0.id) }
        history = []
        returningCard = nil
        enterDeckPhase(cards.isEmpty ? .caughtUp : .feed)
        if !gone.isEmpty || saved.finished { saveProgress() }
    }

    private func saveProgress() {
        guard let session else { return }
        store.saveSession(SavedSession(session: session, index: index, marks: marks, finished: false, drafts: drafts))
    }

    /// Recomputes library totals from saved progress. The freed sum only changes on confirm.
    private func refreshTotals(includingFreed: Bool = true) {
        stats.totalItems = libraryStats.totalItems
        stats.reviewedItems = libraryStats.reviewedItems + store.reviewedCount()
        if includingFreed { stats.freedBytes = libraryStats.freedBytes + store.freedBytes() }
    }

    private func showChip(bytes: Int64) {
        let chip = DeleteChip(bytes: bytes)
        deleteChip = chip
        chipTask?.cancel()
        chipTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled, self?.deleteChip == chip else { return }
            self?.deleteChip = nil
        }
    }

    private func dismissChip() {
        chipTask?.cancel()
        deleteChip = nil
    }
}

// MARK: - Pruning

private extension FeedCard {
    /// This card without `ids`, or nil if nothing worth showing is left.
    func removing(_ ids: Set<LibraryItem.ID>) -> FeedCard? {
        switch self {
        case .photo(let item), .video(let item):
            return ids.contains(item.id) ? nil : self
        case .similar(let group):
            let rest = group.items.filter { !ids.contains($0.id) }
            guard rest.count > 1, !ids.contains(group.bestID) else { return nil }
            return .similar(SimilarGroup(id: group.id, items: rest, bestID: group.bestID, reason: group.reason, maxDistance: group.maxDistance))
        case .batch(let batch):
            let rest = batch.items.filter { !ids.contains($0.id) }
            guard !rest.isEmpty else { return nil }
            // Titles lead with the count, e.g. "14 screenshots from last week".
            let oldCount = "\(batch.items.count) "
            let title = batch.title.hasPrefix(oldCount) ? "\(rest.count) " + batch.title.dropFirst(oldCount.count) : batch.title
            return .batch(ItemBatch(id: batch.id, kind: batch.kind, label: batch.label, title: title, items: rest))
        }
    }
}

extension FeedViewModel {
    /// Long enough to see onboarding's step change before the feed deals in.
    static let onboardingPreparingMinimum = Duration.seconds(1)
    /// The next page starts building when this many undecided cards are left ahead.
    static let pageAhead = 5
    /// Decided cards kept behind the current one, for undo. Older ones are trimmed when a page lands.
    static let keptBehind = 30
    /// Items a free user's pile holds before they have to delete. Unlocked, there's no limit.
    static let freePileCap = 50
}

// MARK: - Mock setup

#if DEBUG
extension FeedViewModel {
    /// Named starting points for previews and `-startAt` launch arguments.
    enum MockStart: String {
        case first, video, similar, batch, onboarding
        /// Partway through the first page with a few deletes pending.
        case pending
        /// Locked with no swipes left, the wall up over the deck.
        case outOfSwipes
        case caughtUp
    }

    /// Mocks start locked unless `entitlements` says otherwise (or `-unlocked YES` in debug builds),
    /// with a full allowance unless `allowance` says otherwise.
    static func mock(
        startingAt start: MockStart = .first,
        entitlements: (any EntitlementStore)? = nil,
        allowance: SwipeAllowance? = nil,
        allowanceTunables: SwipeAllowance.Tunables = .standard,
        notifier: RefillNotifier? = nil
    ) -> FeedViewModel {
        let entitlements = entitlements ?? EntitlementServices.make(mock: true)
        if start == .onboarding {
            // Unstarted, on a library that hasn't been asked yet, with nothing remembered.
            // Previews get a stand-in notification center that hasn't asked, so the reminders step shows.
            let suite = "mock.onboarding"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            return FeedViewModel(
                library: MockPhotoLibrary(needsPrompt: true),
                builder: MockFeedBuilder(),
                entitlements: entitlements,
                defaults: defaults,
                firstSessionMinimum: onboardingPreparingMinimum,
                allowanceTunables: allowanceTunables,
                notifier: notifier ?? RefillNotifier(center: PreviewNotificationCenter(), defaults: defaults)
            )
        }
        let builder = MockFeedBuilder()
        let library = MockPhotoLibrary()
        let vm = FeedViewModel(
            library: library,
            builder: builder,
            entitlements: entitlements,
            session: builder.makeSessionNow(number: 1),
            stats: LibraryStats(totalItems: library.totalItems, reviewedItems: library.reviewedItems, freedBytes: 0),
            allowanceStore: SwipeAllowanceStore(initial: allowance),
            allowanceTunables: allowanceTunables,
            notifier: notifier
        )
        switch start {
        case .first:
            break
        case .video:
            vm.index = vm.cards.firstIndex { if case .video = $0 { true } else { false } } ?? 0
        case .similar:
            vm.index = vm.cards.firstIndex { if case .similar = $0 { true } else { false } } ?? 0
        case .batch:
            vm.index = vm.cards.firstIndex { if case .batch = $0 { true } else { false } } ?? 0
        case .pending:
            vm.simulateSwipes(10)
        case .outOfSwipes:
            vm.index = 4
            vm.allowance = SwipeAllowance(balance: 0, tunables: allowanceTunables, now: .now)
            vm.presentWall()
        case .caughtUp:
            vm.apply(Session(number: 2, cards: []))
        case .onboarding:
            break
        }
        return vm
    }

    // MARK: Settings' debug section

    /// Replaces the free swipes left. Nil fills them to the cap.
    func debugSetSwipes(_ balance: Int?) {
        allowance = balance.map { SwipeAllowance(balance: $0, tunables: allowanceTunables, now: now()) }
            ?? SwipeAllowance(tunables: allowanceTunables, now: now())
        allowanceStore.save(allowance)
    }

    /// Flips the stand-in purchase. Only the debug store can.
    func debugSetUnlocked(_ unlocked: Bool) {
        (entitlements as? DebugEntitlementStore)?.setUnlocked(unlocked)
        if unlocked { notifier?.cancelAll(now: now()) }
    }

    /// Onboarding and the swipe hint show again on the next launch.
    func debugResetOnboarding() {
        defaults.removeObject(forKey: DefaultsKey.hasOnboarded)
        defaults.removeObject(forKey: DefaultsKey.hasSeenSwipeHint)
        // Access is usually granted by now, which on its own skips onboarding.
        defaults.set(true, forKey: DefaultsKey.debugShowOnboarding)
    }

    /// Forgets every saved decision, the pile, and preferences, then deals a fresh first deck.
    func debugClearAllDecisions() async {
        store.reset()
        settledIDs = []
        skipFavorites = store.skipFavorites
        apply(await makeSession(number: 1))
        refreshTotals()
    }

    /// Shows a wall state without going through a purchase, for previews.
    func previewWall(status: PaywallStatus) {
        isWallPresented = true
        paywallStatus = status
    }

    /// Decides the next `count` cards with a plausible mix of deletes, keeps, and laters.
    private func simulateSwipes(_ count: Int) {
        chargesSwipes = false
        defer { chargesSwipes = true }
        for _ in 0..<count where phase == .feed && currentCard != nil {
            let isVideo = if case .video = currentCard { true } else { false }
            let direction: SwipeDirection = switch index % 9 {
            case _ where isVideo: .right
            case 2, 6: .right
            case 4 where index < 20: .up
            default: .left
            }
            decide(direction)
        }
        dismissChip()
    }
}
#endif
