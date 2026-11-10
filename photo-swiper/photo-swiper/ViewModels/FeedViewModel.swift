import Foundation
import Observation
import OSLog

/// Owns the deck: cards, decisions, drafts, marks, undo, the pile, paging, and the running totals.
///
/// The deck is endless. When few cards are left ahead, the next page is built in the background
/// and appended; it only ends at caught up, when a page comes back empty.
/// Views read from it and call its intents. Animation and haptics stay in the views.
/// Every decision is written through to `store` as it happens, so relaunching resumes in place.
///
/// The rest is done by collaborators it owns and forwards to, so views still read everything here:
/// - `SwipeGate`: the free allowance, the wall and the unlock purchase, and the free pile limit.
/// - `OnboardingFlow`: first-launch onboarding, which can hold `phase` while the first deck is dealt.
/// - `ReminderController`: refill reminders and the clutter estimate they quote.
/// - `FollowUpCoordinator`: the review prompt or unlock offer a delete earns.
/// Collaborators never reach each other; effects that span them (a refill front-loading the deck,
/// an unlock cancelling reminders) are sequenced here. Settings' Admin Tools live in
/// `FeedViewModel+AdminTools.swift`, previews and mocks in `FeedViewModel+Mock.swift`.
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
    var session: Session? // internal for FeedViewModel+AdminTools
    var index = 0 // internal for FeedViewModel+AdminTools and +Mock
    private(set) var decisions: [LibraryItem.ID: Decision] = [:]
    private(set) var deleteChip: DeleteChip?
    var returningCard: ReturningCard? // internal for FeedViewModel+AdminTools
    private(set) var stats = LibraryStats(totalItems: 0, reviewedItems: 0, freedBytes: 0)
    private(set) var access = LibraryAccess.full
    /// The system access prompt is up.
    private(set) var isRequestingAccess = false
    /// Access was just granted from onboarding and the first session is being built.
    /// Onboarding stays up meanwhile instead of a loading screen.
    private(set) var isPreparingFirstSession = false
    /// Admin Tools asked for an upsell screen. RootView shows it and clears this.
    var adminUpsellRequest: AdminUpsell? // internal for FeedViewModel+AdminTools
    /// Bumped when Admin Tools puts a mock card on the deck, so RootView switches to the feed.
    var adminShowFeedRequest = 0 // internal for FeedViewModel+AdminTools
    /// A free user's swipe was refused because the pile is full. FeedView shows it.
    var isPileFullNoticePresented = false
    /// Something about the last delete the user should know, e.g. items the system refused.
    var deleteNotice: String?
    /// Saved progress couldn't be opened at launch, so this launch runs on a throwaway store.
    /// RootView says so once.
    private(set) var isProgressLoadNoticePresented = false
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
    var settledIDs: Set<LibraryItem.ID> = [] // internal for FeedViewModel+AdminTools
    /// The "whole library reviewed" confetti has played for this 100%. Cleared when progress drops below it,
    /// so the next 100% celebrates again. Saved in `defaults`.
    var hasCelebratedComplete = false // internal for FeedViewModel+AdminTools
    /// Bumped to play the confetti right away, whatever the progress. Only Settings' debug section does.
    var celebrationRequest = 0 // internal for FeedViewModel+AdminTools
    /// Developer mode: progress reads 100% without any decision being saved. Off shows the real numbers again.
    var debugSimulatesComplete = false // internal for FeedViewModel+AdminTools
    /// Totals the library reports itself. Reviewed counts come from saved progress.
    private var libraryStats = LibraryStats(totalItems: 0, reviewedItems: 0, freedBytes: 0)
    private var chipTask: Task<Void, Never>?
    private var changesTask: Task<Void, Never>?
    /// A refill landed while no deck could take the strongest cards first; the next one dealt does.
    private var refilledSinceDeal = false
    /// The next page being built, while one is.
    private var pageTask: Task<Void, Never>?
    /// The last page build came back empty. No more are tried until the deck runs out.
    private var isLibraryExhausted = false
    /// Changes whenever a different deck is dealt, so a page built for the old one is dropped.
    private var deckGeneration = 0

    private let library: any PhotoLibraryProviding
    private let builder: any FeedBuilding
    let store: any ProgressStoring // internal for FeedViewModel+AdminTools
    let entitlements: any EntitlementStore // internal for FeedViewModel+AdminTools
    /// Runs the background feature index on the real library. Nil for mocks, previews, and tests.
    private let indexScheduler: IndexScheduler?
    /// Holds whether onboarding is done.
    let defaults: UserDefaults // internal for FeedViewModel+AdminTools
    /// Shortest time onboarding shows its "preparing" state, so the step change can be read.
    private let firstSessionMinimum: Duration
    private let now: () -> Date
    /// Where the free tier's limits come from: the swipe allowance and the pile limit.
    let freeTier: FreeTierTunables
    /// Which bundle cards free and unlocked users get.
    let features: FeatureAvailabilityTunables
    /// The allowance, the wall and the unlock purchase, and the free pile limit.
    let gate: SwipeGate
    /// The review prompt or unlock offer a delete earns.
    let followUps: FollowUpCoordinator
    /// Refill reminders and the clutter estimate they quote.
    let reminders: ReminderController
    /// First-launch onboarding, which can hold the screen while the first deck is dealt.
    let onboarding: OnboardingFlow

    /// - Parameters:
    ///   - allowanceStore: Where the free swipes are saved. Nil keeps them in memory, starting full.
    ///   - allowanceTunables: Fixed swipe tunables, used when `freeTier` is nil.
    ///   - freeTier: The live free-tier limits. Nil fixes them at `allowanceTunables` and the standard pile limit.
    ///   - features: Live feature availability. Nil gives everyone every feature.
    ///   - progressLoadFailed: Saved progress couldn't be opened, so `store` is a stand-in. The user is told once.
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
        freeTier: FreeTierTunables? = nil,
        features: FeatureAvailabilityTunables? = nil,
        notifier: RefillNotifier? = nil,
        progressLoadFailed: Bool = false,
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
        let freeTier = freeTier ?? .fixed(FreeTierLimits(allowance: allowanceTunables))
        self.freeTier = freeTier
        self.features = features ?? .fixed()
        followUps = FollowUpCoordinator(defaults: defaults, freeTier: freeTier, now: now)
        onboarding = OnboardingFlow(defaults: defaults, notifier: notifier, library: library)
        reminders = ReminderController(notifier: notifier, builder: builder, store: store, now: now)
        gate = SwipeGate(entitlements: entitlements, allowanceStore: allowanceStore ?? SwipeAllowanceStore(), freeTier: freeTier, now: now)
        skipFavorites = store.skipFavorites
        hasCelebratedComplete = defaults.bool(forKey: DefaultsKey.celebratedComplete)
        isProgressLoadNoticePresented = progressLoadFailed
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
        freeTier: FreeTierTunables? = nil,
        features: FeatureAvailabilityTunables? = nil,
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
        let freeTier = freeTier ?? .fixed(FreeTierLimits(allowance: allowanceTunables))
        self.freeTier = freeTier
        self.features = features ?? .fixed()
        followUps = FollowUpCoordinator(defaults: defaults, freeTier: freeTier, now: now)
        onboarding = OnboardingFlow(defaults: defaults, notifier: notifier, library: library)
        reminders = ReminderController(notifier: notifier, builder: builder, store: store, now: now)
        gate = SwipeGate(entitlements: entitlements, allowanceStore: allowanceStore ?? SwipeAllowanceStore(), freeTier: freeTier, now: now)
        skipFavorites = store.skipFavorites
        hasCelebratedComplete = defaults.bool(forKey: DefaultsKey.celebratedComplete)
        libraryStats = stats
        apply(session)
        refreshTotals()
    }

    // MARK: Follow-ups

    var isReviewPromptDue: Bool { followUps.isReviewPromptDue }
    var isDeleteUpsellDue: Bool { followUps.isDeleteUpsellDue }
    var upsellFreedBytes: Int64 { followUps.upsellFreedBytes }
    func releaseReviewPrompt() { followUps.releaseReviewPrompt() }
    func finishDeleteUpsell(shown: Bool) { followUps.finishDeleteUpsell(shown: shown) }
    func finishReviewPrompt(asked: Bool) { followUps.finishReviewPrompt(asked: asked) }

    // MARK: Reminders

    var isRemindersOptedIn: Bool { reminders.isRemindersOptedIn }
    var areRemindersDenied: Bool { reminders.areRemindersDenied }
    var clutterEstimate: ClutterEstimate? { reminders.clutterEstimate }
    var canRemind: Bool { reminders.canRemind }
    var daysToFinish: Double? { reminders.daysToFinish(swipesPerDay: allowanceTunables.swipesPerDay) }
    func remindWhenSwipesAreBack() async {
        await reminders.remindWhenSwipesAreBack(state: { reminderAllowance }, similarAhead: { similarAhead })
    }
    func setRemindersEnabled(_ on: Bool) async {
        await reminders.setRemindersEnabled(on, state: { reminderAllowance }, similarAhead: { similarAhead })
    }
    func refreshReminderPermission() async { await reminders.refreshReminderPermission() }
    func scheduleReminders() async { // internal for FeedViewModel+AdminTools
        await reminders.scheduleReminders(state: { reminderAllowance }, similarAhead: { similarAhead })
    }
    private var reminderAllowance: ReminderController.AllowanceState {
        .init(allowance: allowance, tunables: allowanceTunables, isUnlocked: isUnlocked)
    }
    /// Similar sets still ahead in the deck, which the clutter estimate counts too.
    private var similarAhead: Int {
        cards.dropFirst(index).filter { if case .similar = $0 { true } else { false } }.count
    }

    // MARK: Swipe gate

    var allowance: SwipeAllowance { gate.allowance }
    var allowanceTunables: SwipeAllowance.Tunables { gate.allowanceTunables }
    var paywallStatus: PaywallStatus { gate.paywallStatus }
    var isWallPresented: Bool {
        get { gate.isWallPresented }
        set { gate.isWallPresented = newValue }
    }
    var purchasedThisLaunch: Bool { gate.purchasedThisLaunch }
    var canSwipe: Bool { gate.canSwipe }
    var swipesLeft: Int? { gate.swipesLeft }
    var nextRefillAt: Date? { gate.nextRefillAt }
    var isPurchaseBusy: Bool { gate.isPurchaseBusy }
    var freeBinBytes: Int64 { gate.freeBinBytes }
    var pileLimitBytes: Int64? { gate.pileLimitBytes }
    /// What the pile counts toward its limit: `pendingBytes`, with unknown sizes counted as `unknownSizeBytes`.
    var pileCountedBytes: Int64 { Self.countedBytes(pendingItems) }
    var isPileFull: Bool { gate.isPileFull(counted: pileCountedBytes) }
    static var unknownSizeBytes: Int64 { SwipeGate.unknownSizeBytes }
    static func countedBytes(_ items: [LibraryItem]) -> Int64 { SwipeGate.countedBytes(items) }
    func dismissWall() { gate.dismissWall() }
    func resetPurchaseStatus() { gate.resetPurchaseStatus() }

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

    /// Unique items decided keep or delete that are still in the library, never more than the total.
    /// "Later" doesn't count as reviewed.
    var libraryReviewedCount: Int {
        if debugSimulatesComplete { return stats.totalItems }
        return min(stats.reviewedItems, stats.totalItems)
    }
    var libraryReviewedFraction: Double {
        stats.totalItems == 0 ? 0 : min(1, Double(libraryReviewedCount) / Double(stats.totalItems))
    }
    /// Every item in the library is reviewed.
    var isLibraryComplete: Bool { stats.totalItems > 0 && libraryReviewedCount >= stats.totalItems }
    /// The library is at 100% and the confetti hasn't played for it yet.
    var isCompleteCelebrationDue: Bool { isLibraryComplete && !hasCelebratedComplete }
    var freedBytes: Int64 { stats.freedBytes }

    var isUnlocked: Bool { entitlements.isUnlocked }
    var displayPrice: String { entitlements.displayPrice }

    /// The deck's phase, even while onboarding holds the screen. Paging and reordering go by this;
    /// swiping still needs `phase` itself to be the feed.
    var deckPhase: Phase { onboarding.heldPhase ?? phase } // internal for FeedViewModel+AdminTools

    /// The number the next page gets. Pages are numbered across decks, so saved decisions can tell them apart.
    var nextPageNumber: Int { max(session?.number ?? 0, store.lastSessionNumber()) + 1 } // internal for FeedViewModel+AdminTools

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

    /// Copies in a duplicate set that a left swipe would clear: every one but the keeper, unless a
    /// partial one-by-one review decided otherwise.
    func markedForClearing(in group: DuplicateGroup) -> Set<LibraryItem.ID> {
        var marked = Set(group.others.map(\.id))
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
        case (.left, .similar), (.left, .duplicates), (.left, .batch):
            switch itemDecisions(for: card, direction: .left).values.filter({ $0 == .delete }).count {
            case 0: "Keep all \(card.items.count)"
            case let n: "Clear \(n)"
            }
        case (.right, .photo), (.right, .video): "Keep"
        case (.right, _): "Keep all \(card.items.count)"
        }
    }

    // MARK: Intents

    func dismissProgressLoadNotice() {
        isProgressLoadNoticePresented = false
    }

    /// The 100% confetti has played; it won't again until progress drops and comes back.
    func markCompleteCelebrated() {
        hasCelebratedComplete = true
        defaults.set(true, forKey: DefaultsKey.celebratedComplete)
    }

    /// Called at launch, from onboarding's Allow button, and again from the no-access screen
    /// when the app returns from Settings. A first launch stops at onboarding without prompting.
    func start() async {
        guard phase == .loading || phase == .noAccess || phase == .onboarding, !isRequestingAccess,
              !onboarding.isOnboardingAccessGranted else { return }
        if phase == .loading, onboarding.needsOnboarding {
            onboarding.enter()
            phase = .onboarding
            // Settled long before the page dots fade in, without holding up onboarding at launch.
            await onboarding.settleReminderOffer()
            return
        }
        let fromOnboarding = phase == .onboarding
        if fromOnboarding { onboarding.markOnboarded() }
        guard await requestAccess(fromOnboarding: fromOnboarding) else { return }
        await loadDeck(fromOnboarding: fromOnboarding)
    }

    /// Asks for photo access. False if denied, which shows the no-access screen.
    private func requestAccess(fromOnboarding: Bool) async -> Bool {
        isRequestingAccess = true
        access = await library.requestAccess()
        isRequestingAccess = false
        guard access != .denied else {
            phase = .noAccess
            return false
        }
        if fromOnboarding {
            isPreparingFirstSession = true
            onboarding.accessGranted()
        } else {
            phase = .loading
        }
        return true
    }

    /// Brings back the saved deck, or deals a fresh one, once access is granted.
    private func loadDeck(fromOnboarding: Bool) async {
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
        if isUnlocked { reminders.cancelAll() }
        fillIfNeeded()
    }

    // MARK: Onboarding

    var onboardingStep: OnboardingStep { onboarding.onboardingStep }
    var offersReminderStep: Bool { onboarding.offersReminderStep }
    var isOnboardingAccessGranted: Bool { onboarding.isOnboardingAccessGranted }
    /// Onboarding will end on the unlock offer.
    var offersUpsellStep: Bool { onboarding.offersUpsellStep(isUnlocked: isUnlocked) }
    /// Onboarding's last step is done but the first deck is still being built. The step shows progress meanwhile.
    var isLeavingOnboarding: Bool { phase == .onboarding && onboarding.isOnboardingAccessGranted && !onboarding.holdsOnboarding }

    /// Moves onboarding past photo access to the next step that applies, or finishes it.
    func advanceOnboarding() async {
        guard phase == .onboarding, onboarding.isOnboardingAccessGranted else { return }
        if await onboarding.advance(isUnlocked: { isUnlocked }) { finishOnboarding() }
    }

    /// Back one step after photo access: the offer to reminders where they were shown, either to the primer.
    func goBackInOnboarding() {
        guard canGoBackInOnboarding else { return }
        onboarding.goBack()
    }

    /// Onboarding can step back from where it is. Not mid-purchase, nor once the user has finished.
    var canGoBackInOnboarding: Bool {
        phase == .onboarding && onboarding.canGoBack && !isPurchaseBusy
    }

    /// Lets the feed replace onboarding. If the first deck is still being built, `start()` shows it
    /// once it's ready, and `isLeavingOnboarding` holds meanwhile.
    private func finishOnboarding() {
        guard let held = onboarding.finish() else { return }
        phase = held
        fillIfNeeded()
    }

    /// Sets the deck's phase, or holds it while onboarding is still up.
    func enterDeckPhase(_ next: Phase) { // internal for FeedViewModel+AdminTools
        if let next = onboarding.route(next) { phase = next }
    }

    /// Whether swiping card `cardID` this way would go through. The deck asks before letting a card fly.
    /// False out of swipes, for a free user when it would take the pile past its limit, or when
    /// `cardID` is no longer the current card.
    func canDecide(_ direction: SwipeDirection, cardID: FeedCard.ID) -> Bool {
        guard let card = currentCard else { return gate.admitsSwipe }
        guard card.id == cardID else { return false }
        if card.isAdminMock { return true }
        guard gate.admitsSwipe else { return false }
        return fitsInPile(itemDecisions(for: card, direction: direction), card: card)
    }

    /// Whether a finished one-by-one review of card `cardID` would go through, like `canDecide`.
    func canDecideIndividually(_ outcome: [LibraryItem.ID: Decision], cardID: FeedCard.ID) -> Bool {
        guard let card = currentCard else { return gate.admitsSwipe }
        guard card.id == cardID else { return false }
        if card.isAdminMock { return true }
        guard gate.admitsSwipe else { return false }
        guard let complete = completed(outcome, for: card) else { return true }
        return fitsInPile(complete, card: card)
    }

    /// The deck refused a swipe on `cardID`: opens the wall when out of swipes, or says the pile is full.
    /// Nothing happens if that card is no longer the current one.
    func refuse(_ direction: SwipeDirection, cardID: FeedCard.ID) {
        guard currentCard?.id == cardID else { return }
        refreshAllowance()
        if !gate.admitsSwipe {
            presentWall()
        } else if !isUnlocked {
            isPileFullNoticePresented = true
        }
    }

    /// Decides card `cardID`, the one the user swiped. If it's no longer the current card, nothing happens.
    /// Out of free swipes, nothing is committed and the wall opens instead.
    /// A free user's delete that won't fit in the pile is refused whole, and says so.
    func decide(_ direction: SwipeDirection, cardID: FeedCard.ID) {
        guard phase == .feed, let top = currentCard else { return }
        // Admitting can credit a refill, which reorders the deck, so the card is only read after it.
        guard top.isAdminMock || admitSwipe(), let card = currentCard(matching: cardID) else { return }
        let outcome = itemDecisions(for: card, direction: direction)
        guard fitsInPile(outcome, card: card) else {
            isPileFullNoticePresented = true
            return
        }
        commit(outcome, card: card, direction: direction)
    }

    /// Settles batch or similar-shots card `cardID` from a one-by-one review. Items left out
    /// count as "later" in a batch, and follow their marks in a similar set. If that card is no longer
    /// the current one, nothing happens.
    /// It costs one swipe like any card; out of swipes, or past a free user's pile limit, the review
    /// is kept as a draft and the wall or the pile notice opens.
    func decideIndividually(_ outcome: [LibraryItem.ID: Decision], cardID: FeedCard.ID) {
        guard phase == .feed, let top = currentCard, completed(outcome, for: top) != nil else { return }
        // Admitting can credit a refill, which reorders the deck, so the card is only read after it.
        let admitted = top.isAdminMock || admitSwipe()
        guard let card = currentCard(matching: cardID), let complete = completed(outcome, for: card) else { return }
        guard admitted else {
            saveDraft(outcome, for: card.id)
            return
        }
        guard fitsInPile(complete, card: card) else {
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
        if last.charged { gate.refund() }
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
        await refreshLibraryTotal()
        let freed = deletedItems.reduce(0) { $0 + $1.bytes }
        followUps.queueFollowUp(freed: freed, isUnlocked: isUnlocked, isWallPresented: isWallPresented, purchasedThisLaunch: purchasedThisLaunch)
        return freed
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
        gate.openWall()
        followUps.wallShown()
        Task { await reminders.refreshEstimate(similarAhead: { similarAhead }) }
    }

    /// Buys the unlock, from the wall or Settings. See `SwipeGate.purchaseUnlock()`.
    /// Bought: reminders are moot.
    @discardableResult
    func purchaseUnlock() async -> Bool {
        guard await gate.purchaseUnlock() else { return false }
        reminders.cancelAll()
        return true
    }

    /// The unlock changed outside a purchase run here. See `SwipeGate.entitlementChanged()`.
    func entitlementChanged() {
        if gate.entitlementChanged() { reminders.cancelAll() }
    }

    /// Restores an earlier purchase, from the wall or Settings. See `SwipeGate.restorePurchases()`.
    @discardableResult
    func restorePurchases() async -> Bool {
        guard await gate.restorePurchases() else { return false }
        reminders.cancelAll()
        return true
    }

    /// Credits any refills owed by now. Called on returning to the app and while a countdown shows.
    /// When a refill lands, the strongest cards waiting move to the front.
    func refreshAllowance() {
        if gate.creditRefills() { frontLoad() }
    }

    func clearReturningCard() {
        returningCard = nil
    }

    // MARK: Internals

    /// The current card if it's `cardID`. Otherwise the gesture was for a card that has since moved,
    /// and is dropped rather than applied to whatever is on top now.
    private func currentCard(matching cardID: FeedCard.ID) -> FeedCard? {
        guard let card = currentCard, card.id == cardID else {
            #if DEBUG
            Self.log.debug("Dropped a decision for \(cardID, privacy: .public): the current card is \(self.currentCard?.id ?? "none", privacy: .public)")
            #endif
            return nil
        }
        return card
    }

    /// Lets a card decision through, or refuses it and opens the wall when no swipes are left.
    private func admitSwipe() -> Bool {
        refreshAllowance()
        guard gate.admitsSwipe else {
            presentWall()
            return false
        }
        return true
    }

    /// Spends one swipe for a card decision. Unlocked, nothing is counted. True if one was spent.
    private func spendSwipe() -> Bool {
        guard gate.spend() else { return false }
        // Back and swiping before a reminder fired: it's no longer needed.
        reminders.cancelAll()
        if allowance.remaining == 0, isRemindersOptedIn {
            Task { await scheduleReminders() }
        }
        return true
    }

    /// Moves the strongest cards still to come to right after the current one, or leaves it to the
    /// next deck dealt.
    private func frontLoad() {
        guard deckPhase == .feed, var current = session else {
            refilledSinceDeal = true
            return
        }
        refilledSinceDeal = false
        let reordered = FrontLoad.reordered(current.cards, from: frontLoadStart)
        guard reordered != current.cards else { return }
        current.cards = reordered
        session = current
        saveProgress()
    }

    /// Where a refill's reordering starts. The current card never moves: the user may be looking at it
    /// full screen, or reviewing it one by one. With none showing, the next card dealt can move too.
    private var frontLoadStart: Int { currentCard == nil ? index : index + 1 }

    /// Records per-item decisions for the current card and moves on.
    /// `direction` is the side the card left from, so undo brings it back the same way.
    /// An Admin Tools mock card only moves on: nothing is saved, charged or added to the pile.
    private func commit(_ outcome: [LibraryItem.ID: Decision], card: FeedCard, direction: SwipeDirection) {
        let isMock = card.isAdminMock
        let ids = card.items.map(\.id)
        let before = isMock ? [:] : store.decisions(for: Set(ids))
        let stored = isMock ? [:] : Dictionary(uniqueKeysWithValues: ids.map { ($0, before[$0]) })
        let charged = isMock ? false : spendSwipe()
        history.append(Snapshot(index: index, decisions: decisions, marks: marks, drafts: drafts, cardID: card.id, direction: direction, stored: stored, charged: charged))
        if !isMock { decisions.merge(outcome) { _, new in new } }
        drafts[card.id] = nil
        returningCard = nil

        let decidedAt = now()
        let sessionNumber = session?.number ?? 0
        if !isMock {
            store.save(Dictionary(uniqueKeysWithValues: card.items.compactMap { item in
                outcome[item.id].map { (item.id, StoredDecision(decision: $0, decidedAt: decidedAt, sessionNumber: sessionNumber, item: item)) }
            }))
        }

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
    func fillIfNeeded() { // internal for FeedViewModel+AdminTools
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
        let page = gated(await builder.makeSession(number: nextPageNumber, options: options))
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
            current.cards = FrontLoad.reordered(current.cards, from: frontLoadStart)
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
        let marked: Set<LibraryItem.ID>? = switch card {
        case .similar(let group): markedForClearing(in: group)
        case .duplicates(let group): markedForClearing(in: group)
        case .photo, .video, .batch: nil
        }
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
        case .duplicates(let group):
            let marked = markedForClearing(in: group)
            rest = { marked.contains($0) ? .delete : .keep }
        case .photo, .video:
            return nil
        }
        return Dictionary(uniqueKeysWithValues: card.items.map { ($0.id, outcome[$0.id] ?? rest($0.id)) })
    }

    /// The pile can take these deletes from `card`: always when unlocked, and up to `pileLimitBytes` otherwise.
    /// Keeps and laters add nothing, so they always fit unless a partial review drafted deletes.
    /// An empty pile takes anything, even one item (or group) bigger than the whole limit.
    /// Groups go in whole or not at all.
    private func fitsInPile(_ outcome: [LibraryItem.ID: Decision], card: FeedCard) -> Bool {
        guard !card.isAdminMock else { return true }
        guard gate.isPileLimited else { return true }
        let pending = pendingItems
        let pendingIDs = Set(pending.map(\.id))
        let added = card.items.filter { outcome[$0.id] == .delete && !pendingIDs.contains($0.id) }
        return gate.pileTakes(added, onto: pending)
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
        // The library is smaller now, whoever deleted these, so its total is read again.
        Task { await refreshLibraryTotal() }
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
    func makeSession(number: Int, placeBudget: Duration? = nil) async -> Session { // internal for FeedViewModel+AdminTools
        var options = FeedOptions(skipFavorites: skipFavorites, excluding: store.excludedFromNewSession(asOf: now()))
        if let placeBudget { options.placeBudget = placeBudget }
        return gated(await builder.makeSession(number: number, options: options))
    }

    /// Splits bundles this user doesn't get into single cards. See `FeatureAvailabilityTunables`.
    private func gated(_ session: Session) -> Session {
        let enabled = features.enabled(isUnlocked: isUnlocked)
        var session = session
        session.cards = session.cards.flatMap { $0.unbundled(unless: enabled) }
        return session
    }

    func apply(_ next: Session) { // internal for FeedViewModel+AdminTools and +Mock
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
        // Admin Tools' mock cards don't outlive the launch.
        position -= restored.cards.prefix(position).filter(\.isAdminMock).count
        restored.cards.removeAll(where: \.isAdminMock)
        let savedIndex = position
        let gone = await library.missing(from: Set(restored.items.map(\.id)).union(store.pile().map(\.id)))
        if !gone.isEmpty {
            // Undo history starts empty, so earlier cards can be pruned too.
            var cards: [FeedCard] = []
            position = 0
            for (offset, card) in restored.cards.enumerated() {
                guard let kept = card.removing(gone) else { continue }
                cards.append(kept)
                if offset < savedIndex { position += 1 }
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

    func saveProgress() { // internal for FeedViewModel+AdminTools
        guard let session else { return }
        store.saveSession(SavedSession(session: session, index: index, marks: marks, finished: false, drafts: drafts))
    }

    /// Recomputes library totals from saved progress. The freed sum only changes on confirm.
    func refreshTotals(includingFreed: Bool = true) { // internal for FeedViewModel+AdminTools
        stats.totalItems = libraryStats.totalItems
        // Each item counts once. The real library reports no baseline; debug mocks report a pretend one,
        // which stands until real decisions pass it, so it's never added to them.
        stats.reviewedItems = min(libraryStats.totalItems, max(libraryStats.reviewedItems, store.reviewedCount()))
        if includingFreed { stats.freedBytes = libraryStats.freedBytes + store.freedBytes() }
        updateCelebration()
    }

    /// Reads the library's own total again, which shrinks as items are deleted here or elsewhere.
    private func refreshLibraryTotal() async {
        libraryStats = await library.stats()
        refreshTotals()
    }

    /// Below 100% again, so reaching it next time celebrates again.
    func updateCelebration() { // internal for FeedViewModel+AdminTools
        guard stats.totalItems > 0, !isLibraryComplete, hasCelebratedComplete else { return }
        hasCelebratedComplete = false
        defaults.removeObject(forKey: DefaultsKey.celebratedComplete)
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

    func dismissChip() { // internal for FeedViewModel+Mock
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
        case .duplicates(let group):
            let rest = group.items.filter { !ids.contains($0.id) }
            guard rest.count > 1, !ids.contains(group.keepID) else { return nil }
            return .duplicates(DuplicateGroup(id: group.id, items: rest, keepID: group.keepID, reason: group.reason))
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
    fileprivate static let log = Logger(subsystem: "com.israelavendanojr.photo-swiper", category: "feed")
}
