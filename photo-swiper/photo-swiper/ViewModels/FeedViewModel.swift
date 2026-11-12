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
/// - `DashboardController`: the Library tab's cached numbers: cleared over time and what's left to clear.
/// Collaborators never reach each other; effects that span them (a refill front-loading the deck,
/// an unlock cancelling reminders) are sequenced here. The Admin tab's tools live in
/// `AdminController` (`vm.admin`), which changes the deck only through this class's admin intents;
/// previews and mocks are in `FeedViewModel+Mock.swift`. No state here is settable from outside.
@Observable
@MainActor
final class FeedViewModel {
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

    private(set) var phase: FeedPhase = .loading
    private(set) var session: Session? {
        didSet { cardsRevision &+= 1 }
    }
    private(set) var index = 0
    private(set) var decisions: [LibraryItem.ID: Decision] = [:]
    private(set) var deleteChip: DeleteChip?
    private(set) var returningCard: ReturningCard?
    private(set) var stats = LibraryStats(totalItems: 0, reviewedItems: 0, freedBytes: 0)
    private(set) var access = LibraryAccess.full
    /// The one kind of clutter the feed offers, picked from the dashboard. Nil offers everything.
    /// Not saved: a relaunch is back to the full feed.
    private(set) var feedFocus: CleanupCategory?
    /// Goes up each time something asks for the Feed tab. RootView switches tabs when it changes.
    private(set) var feedRequests = 0
    /// The system access prompt is up.
    private(set) var isRequestingAccess = false
    /// Access was just granted from onboarding and the first session is being built.
    /// Onboarding stays up meanwhile instead of a loading screen.
    private(set) var isPreparingFirstSession = false
    /// A free user's swipe was refused because the pile is full. FeedView shows it.
    private(set) var isPileFullNoticePresented = false
    /// Something about the last delete the user should know, e.g. items the system refused.
    private(set) var deleteNotice: String?
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
    private var settledIDs: Set<LibraryItem.ID> = []
    /// Pending deletes outside a limited selection, which the app can't see or delete. They're hidden
    /// from the pile but stay pending in the store, so they come back once the app can see them again.
    private var outOfReachIDs: Set<LibraryItem.ID> = []
    /// The "whole library reviewed" confetti has played for this 100%. Cleared when progress drops below it,
    /// so the next 100% celebrates again. Saved in `defaults`.
    private(set) var hasCelebratedComplete = false
    /// Bumped to play the confetti right away, whatever the progress. Only Settings' debug section does.
    private(set) var celebrationRequest = 0
    /// Developer mode: progress reads 100% without any decision being saved. Off shows the real numbers again.
    private(set) var debugSimulatesComplete = false
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
    /// Changes whenever `session` is set, so a save can tell whether the cards changed since the
    /// last time they were written whole.
    private var cardsRevision = 0
    /// `cardsRevision` when the cards were last written whole; nil before the first write.
    private var savedCardsRevision: Int?

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
    /// Schedules refill reminders. Kept for Admin Tools' test notifications; nil in tests and previews.
    private let notifier: RefillNotifier?
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
    /// The Library tab's numbers, cached between launches.
    let dashboard: DashboardController
    /// The Admin tab's tools (Developer mode).
    @ObservationIgnored private(set) lazy var admin = AdminController(vm: self, entitlements: entitlements, defaults: defaults, notifier: notifier, now: now)

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
        dashboardCache: URL? = nil,
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
        self.notifier = notifier
        let freeTier = freeTier ?? .fixed(FreeTierLimits(allowance: allowanceTunables))
        self.freeTier = freeTier
        self.features = features ?? .fixed()
        followUps = FollowUpCoordinator(defaults: defaults, freeTier: freeTier, now: now)
        onboarding = OnboardingFlow(defaults: defaults, notifier: notifier, library: library)
        reminders = ReminderController(notifier: notifier, builder: builder, store: store, now: now)
        dashboard = DashboardController(builder: builder, store: store, cacheURL: dashboardCache, now: now)
        gate = SwipeGate(entitlements: entitlements, allowanceStore: allowanceStore ?? SwipeAllowanceStore(), freeTier: freeTier, now: now)
        skipFavorites = store.skipFavorites
        hasCelebratedComplete = defaults.bool(forKey: DefaultsKey.celebratedComplete)
        isProgressLoadNoticePresented = progressLoadFailed
    }

    /// Starts already loaded. Used by previews and launch-time setup.
    convenience init(
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
        self.init(library: library, builder: builder, store: store, entitlements: entitlements, allowanceStore: allowanceStore,
                  allowanceTunables: allowanceTunables, freeTier: freeTier, features: features, notifier: notifier)
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
    /// Schedules the refill reminder for the current allowance, if the user opted in.
    func scheduleReminders() async {
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
        return (carriedPending + current).filter { !settledIDs.contains($0.id) && !outOfReachIDs.contains($0.id) }
    }
    var pendingBytes: Int64 { pendingItems.reduce(0) { $0 + $1.bytes } }
    /// Admin Tools' mock items are left out: they aren't in the library.
    var keptCount: Int { decisions.filter { $0.value == .keep && !LibraryItem.isAdminMock(id: $0.key) }.count }
    var laterCount: Int { decisions.filter { $0.value == .later && !LibraryItem.isAdminMock(id: $0.key) }.count }

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
    private var deckPhase: FeedPhase { onboarding.heldPhase ?? phase }

    /// The number the next page gets. Pages are numbered across decks, so saved decisions can tell them apart.
    private var nextPageNumber: Int { max(session?.number ?? 0, store.lastSessionNumber()) + 1 }

    // MARK: Card helpers

    /// Items in a similar or duplicate group that a left swipe would clear: every one but the keeper,
    /// or a similar group's marks. A partial one-by-one review overrides the shots it reached.
    func markedForClearing(in group: some KeeperGroup) -> Set<LibraryItem.ID> {
        // Only similar groups take marks (`toggleMark`); a duplicate set always clears all but the keeper.
        var marked = (group is SimilarGroup ? marks[group.id] : nil) ?? Set(group.others.map(\.id))
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

    func dismissPileFullNotice() {
        isPileFullNoticePresented = false
    }

    func dismissDeleteNotice() {
        deleteNotice = nil
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
        await reopenWronglyGone()
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
    private func enterDeckPhase(_ next: FeedPhase) {
        if let next = onboarding.route(next) { phase = next }
    }

    /// Whether swiping card `cardID` this way would go through. The deck asks before letting a card fly.
    /// False out of swipes, for a free user when it would take the pile past its limit, or when
    /// `cardID` is no longer the current card. Admin Tools' mock cards never need a swipe, but their
    /// deletes count toward the free pile limit like any other.
    func canDecide(_ direction: SwipeDirection, cardID: FeedCard.ID) -> Bool {
        guard let card = currentCard else { return gate.admitsSwipe }
        guard card.id == cardID, card.isAdminMock || gate.admitsSwipe else { return false }
        return fitsInPile(itemDecisions(for: card, direction: direction), card: card)
    }

    /// Whether a finished one-by-one review of card `cardID` would go through, like `canDecide`.
    func canDecideIndividually(_ outcome: [LibraryItem.ID: Decision], cardID: FeedCard.ID) -> Bool {
        guard let card = currentCard else { return gate.admitsSwipe }
        guard card.id == cardID, card.isAdminMock || gate.admitsSwipe else { return false }
        guard let complete = completed(outcome, for: card) else { return true }
        return fitsInPile(complete, card: card)
    }

    /// The deck refused a swipe on `cardID`: opens the wall when out of swipes, or says the pile is full.
    /// Nothing happens if that card is no longer the current one. A mock card never costs a swipe, so it
    /// can only have been refused for the pile, and never opens the wall.
    func refuse(_ direction: SwipeDirection, cardID: FeedCard.ID) {
        guard let card = currentCard, card.id == cardID else { return }
        refreshAllowance()
        if !card.isAdminMock, !gate.admitsSwipe {
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
        if last.charged { gate.refund() }
        returningCard = ReturningCard(cardID: last.cardID, direction: last.direction)
        dismissChip()
        phase = .feed
        saveProgress(with: last.stored)
        refreshTotals(includingFreed: false)
    }

    /// Takes items out of the pile by keeping them instead, here, in the store, and in undo history.
    /// Admin Tools' mock items are kept here only; `saveProgress` never writes them.
    func keep(_ items: [LibraryItem]) {
        let pending = Set(pendingItems.map(\.id))
        let items = items.filter { pending.contains($0.id) }
        guard !items.isEmpty else { return }
        let ids = Set(items.map(\.id))
        for id in ids where decisions[id] == .delete { decisions[id] = .keep }
        carriedPending.removeAll { ids.contains($0.id) }

        let saved = store.decisions(for: ids)
        let decidedAt = now()
        let kept = Dictionary(uniqueKeysWithValues: items.map { item in
            let sessionNumber = saved[item.id]?.sessionNumber ?? session?.number ?? 0
            return (item.id, Optional(StoredDecision(decision: .keep, decidedAt: decidedAt, sessionNumber: sessionNumber, item: item)))
        })

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
        saveProgress(with: kept)
        refreshTotals(includingFreed: false)
    }

    /// Deletes some of the pile, from the pending screen. The deck carries on,
    /// and the rest stays pending. Returns the bytes freed, or nil if nothing was deleted,
    /// including when the user cancels the system prompt.
    ///
    /// Admin Tools' mock items never reach the library: they're only dropped from the pile, here and not
    /// in the store, and their bytes count as freed so the post-delete offer can show. Deleting only mocks
    /// keeps undo and isn't counted as a delete (see `FollowUpCoordinator.queueFollowUp`). If real items
    /// were chosen too and the library deletes none of them (cancelled, failed), the mocks stay as well.
    @discardableResult
    func deleteNow(_ items: [LibraryItem]) async -> Int64? {
        let pending = Set(pendingItems.map(\.id))
        let chosen = items.filter { pending.contains($0.id) }
        let real = chosen.filter { !$0.isAdminMock }
        var deletedItems: [LibraryItem] = []
        if !real.isEmpty {
            guard let deleted = await delete(real) else { return nil }
            deletedItems = deleted
        }
        // Still pending after the system prompt's await.
        let stillPending = Set(pendingItems.map(\.id))
        let mocks = chosen.filter { $0.isAdminMock && stillPending.contains($0.id) }
        guard !deletedItems.isEmpty || !mocks.isEmpty else { return nil }
        let ids = Set(deletedItems.map(\.id))
        let mockIDs = Set(mocks.map(\.id))
        // Before settling: the store's first history write fills in older deletes, and these must not be among them.
        recordCleanup(deletedItems)
        settle(ids, as: .deleted)
        settledIDs.formUnion(mockIDs)
        carriedPending.removeAll { ids.contains($0.id) || mockIDs.contains($0.id) }
        if !deletedItems.isEmpty {
            // A deleted photo can't be swiped again.
            history.removeAll()
        }
        saveProgress()
        if !deletedItems.isEmpty { await refreshLibraryTotal() }
        let freed = (deletedItems + mocks).reduce(0) { $0 + $1.bytes }
        followUps.queueFollowUp(freed: freed, isUnlocked: isUnlocked, isWallPresented: isWallPresented,
                                purchasedThisLaunch: purchasedThisLaunch, isMockOnly: deletedItems.isEmpty)
        if !deletedItems.isEmpty { Task { await refreshDashboard() } }
        return freed
    }

    /// Adds a delete to the cleanup history, one entry per category, at the time it happened.
    /// Each item's category is the one saved with its decision; older decisions fall back to a guess.
    private func recordCleanup(_ deleted: [LibraryItem]) {
        guard !deleted.isEmpty else { return }
        let saved = store.decisions(for: Set(deleted.map(\.id)))
        store.recordCleanup(CleanupEntry.entries(for: deleted, at: now()) { saved[$0.id]?.category ?? .inferred(from: $0) })
    }

    // MARK: Dashboard

    /// Works the Library tab's numbers out again: pull to refresh, and after a delete.
    func refreshDashboard() async {
        await dashboard.refresh(reviewedFraction: libraryReviewedFraction)
    }

    /// Refreshes the Library tab's numbers if they're missing or old, when the tab is shown.
    func refreshDashboardIfStale() async {
        guard dashboard.isStale else { return }
        await refreshDashboard()
    }

    // MARK: Focus

    /// Shows only one kind of clutter in the feed, or everything again with nil, and asks for the Feed tab.
    ///
    /// The current card never changes, whatever its kind: the user may be partway through it, and a decision
    /// must land on the card they acted on. Only the cards after it that don't fit are dropped, and a page
    /// being built without the focus is thrown away. New pages bring the rest. Nothing is decided.
    func focusFeed(on category: CleanupCategory?) {
        defer { showFeed() }
        guard category != feedFocus else { return }
        feedFocus = category
        if let category, var current = session, current.cards.count > index + 1 {
            current.cards = Array(current.cards.prefix(index + 1)) + current.cards.dropFirst(index + 1).filter { $0.matches(category) }
            session = current
            saveProgress()
        }
        // A page on its way was built for the old focus.
        deckGeneration += 1
        pageTask?.cancel()
        pageTask = nil
        isLibraryExhausted = false
        if phase == .caughtUp {
            Task { await checkAgain() }
        } else {
            fillIfNeeded()
        }
    }

    /// Asks for the Feed tab, e.g. from the dashboard's empty state.
    func showFeed() {
        feedRequests += 1
    }

    /// "Check again" from caught up: deals a fresh deck if anything turned up, e.g. new photos
    /// or "later" items back from their cooldown. Never gated: only swipes are.
    func checkAgain() async {
        guard phase == .caughtUp else { return }
        let next = await makeSession(number: nextPageNumber)
        guard !next.cards.isEmpty else { return }
        apply(next)
    }

    /// Under limited access, lets the user add photos to what the app can see. Pending deletes that
    /// come back into view rejoin the pile.
    func addMorePhotos() async {
        await library.presentLimitedPicker()
        if !outOfReachIDs.isEmpty {
            outOfReachIDs.subtract(outOfReachIDs.subtracting(await library.missing(from: outOfReachIDs)))
        }
        await refreshLibraryTotal()
        fillIfNeeded()
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

    // MARK: Admin Tools

    // Intents `AdminController` changes the deck through, so it never needs settable state.

    /// Mock cards queued from the current card on, in the order Admin Tools added them.
    var adminQueuedMockCount: Int {
        cards.dropFirst(index).filter(\.isAdminMock).count
    }

    /// Queues an Admin Tools mock card at the top of the deck, behind any mock cards already queued
    /// there, so they come up in the order added and a mock card on top stays on top. Works from caught up.
    func adminInsertMockCard(_ card: FeedCard) {
        guard var current = session else { return }
        let start = min(index, current.cards.count)
        let queued = current.cards[start...].prefix(while: \.isAdminMock).count
        current.cards.insert(card, at: start + queued)
        session = current
        returningCard = nil
        if deckPhase == .caughtUp { enterDeckPhase(.feed) }
        saveProgress()
    }

    /// Takes the mock cards still ahead out of the deck, and every mock item out of the pile (and out of
    /// undo, so it can't come back). Swiped mock cards stay behind until trimmed.
    func adminRemoveMockCards() {
        let isMock: (LibraryItem.ID) -> Bool = { LibraryItem.isAdminMock(id: $0) }
        decisions = decisions.filter { !isMock($0.key) }
        carriedPending.removeAll { $0.isAdminMock }
        for i in history.indices {
            history[i].decisions = history[i].decisions.filter { !isMock($0.key) }
        }
        refreshTotals(includingFreed: false)
        guard var current = session, current.cards[index...].contains(where: \.isAdminMock) else { return }
        current.cards = Array(current.cards[..<index]) + current.cards[index...].filter { !$0.isAdminMock }
        session = current
        returningCard = nil
        saveProgress()
        fillIfNeeded()
    }

    /// Works out the clutter estimate again, for the body of a test notification.
    func adminRefreshClutterEstimate() async {
        await reminders.refreshEstimate(similarAhead: { similarAhead })
    }

    /// Forgets every saved decision, the pile, and preferences, then deals a fresh first deck.
    func adminClearAllDecisions() async {
        store.reset()
        dashboard.clear()
        settledIDs = []
        skipFavorites = store.skipFavorites
        apply(await makeSession(number: 1))
        refreshTotals()
    }

    /// Deals a fresh deck on the current rules, keeping every decision.
    func adminRebuildDeck() async {
        apply(await makeSession(number: nextPageNumber))
    }

    /// Progress reads 100% while on. Only what's shown changes; nothing is saved.
    func adminSetSimulatesComplete(_ on: Bool) {
        debugSimulatesComplete = on
        updateCelebration()
    }

    /// Plays the 100% confetti now.
    func adminRequestCelebration() {
        celebrationRequest += 1
    }

    /// Forgets that the 100% confetti played, so it plays again at 100%.
    func adminResetCelebration() {
        hasCelebratedComplete = false
        defaults.removeObject(forKey: DefaultsKey.celebratedComplete)
    }

    #if DEBUG
    /// Moves to the first card matching `isWanted`, or stays put. For mock states and previews.
    func debugMoveToFirstCard(where isWanted: (FeedCard) -> Bool) {
        index = cards.firstIndex(where: isWanted) ?? index
    }

    /// Moves to card `position`, for mock states and previews.
    func debugMove(to position: Int) {
        index = position
    }

    /// Deals `session` as a fresh deck, for mock states and previews.
    func debugDeal(_ session: Session) {
        apply(session)
    }
    #endif

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
    /// An Admin Tools mock card is never saved or charged: its decisions live only in memory, where a
    /// delete puts it in the pile like any other (see `deleteNow` for what deleting it does).
    private func commit(_ outcome: [LibraryItem.ID: Decision], card: FeedCard, direction: SwipeDirection) {
        let isMock = card.isAdminMock
        let ids = card.items.map(\.id)
        let before = isMock ? [:] : store.decisions(for: Set(ids))
        let stored = isMock ? [:] : Dictionary(uniqueKeysWithValues: ids.map { ($0, before[$0]) })
        let charged = isMock ? false : spendSwipe()
        history.append(Snapshot(index: index, decisions: decisions, marks: marks, drafts: drafts, cardID: card.id, direction: direction, stored: stored, charged: charged))
        decisions.merge(outcome) { _, new in new }
        drafts[card.id] = nil
        returningCard = nil

        let decidedAt = now()
        let sessionNumber = session?.number ?? 0
        let changes: [LibraryItem.ID: StoredDecision?] = isMock ? [:] : Dictionary(uniqueKeysWithValues: card.items.compactMap { item in
            outcome[item.id].map {
                (item.id, StoredDecision(decision: $0, decidedAt: decidedAt, sessionNumber: sessionNumber, item: item,
                                         category: CleanupCategory.of(item, on: card)))
            }
        })

        let cleared = card.items.filter { outcome[$0.id] == .delete }.reduce(0) { $0 + $1.bytes }
        if cleared > 0 { showChip(bytes: cleared) }

        index += 1
        // The decisions and the deck's new position, in one save, before returning.
        saveProgress(with: changes)
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
        var options = FeedOptions(skipFavorites: skipFavorites, excluding: store.excludedFromNewSession(asOf: now()), focus: feedFocus)
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
        let marked = card.keeperGroup.map { markedForClearing(in: $0) }
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
        if case .batch = card {
            rest = { _ in .later }
        } else if let group = card.keeperGroup {
            let marked = markedForClearing(in: group)
            rest = { marked.contains($0) ? .delete : .keep }
        } else {
            return nil
        }
        return Dictionary(uniqueKeysWithValues: card.items.map { ($0.id, outcome[$0.id] ?? rest($0.id)) })
    }

    /// The pile can take these deletes from `card`: always when unlocked, and up to `pileLimitBytes` otherwise.
    /// Keeps and laters add nothing, so they always fit unless a partial review drafted deletes.
    /// An empty pile takes anything, even one item (or group) bigger than the whole limit.
    /// Groups go in whole or not at all.
    private func fitsInPile(_ outcome: [LibraryItem.ID: Decision], card: FeedCard) -> Bool {
        guard gate.isPileLimited else { return true }
        let pending = pendingItems
        let pendingIDs = Set(pending.map(\.id))
        let added = card.items.filter { outcome[$0.id] == .delete && !pendingIDs.contains($0.id) }
        return gate.pileTakes(added, onto: pending)
    }

    /// Asks the library to delete these and settles the ones that can't be. Returns what was
    /// actually deleted, or nil if nothing was (cancelled, failed, or none deletable).
    /// Admin Tools' mock items are never passed to the library, whatever the caller sends.
    private func delete(_ items: [LibraryItem]) async -> [LibraryItem]? {
        let items = items.filter { !$0.isAdminMock }
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
        // Under limited access "not found" may only mean "not selected", so those stay pending, out of sight.
        var notices: [String] = []
        if library.currentAccess() == .full {
            settle(Set(outcome.missing), as: .gone)
        } else if !outcome.missing.isEmpty {
            outOfReachIDs.formUnion(outcome.missing)
            let n = outcome.missing.count
            notices.append("\(n) \(n == 1 ? "item is" : "items are") outside the photos \(AppInfo.name) can access and \(n == 1 ? "wasn't" : "weren't") deleted.")
        }
        settle(Set(outcome.undeletable), as: .undeletable)
        if !outcome.undeletable.isEmpty {
            let n = outcome.undeletable.count
            notices.append("\(n) \(n == 1 ? "item" : "items") can't be deleted from this app and stayed in your library.")
        }
        if !notices.isEmpty { deleteNotice = notices.joined(separator: " ") }

        let deleted = Set(outcome.deleted)
        let deletedItems = items.filter { deleted.contains($0.id) }
        return deletedItems.isEmpty ? nil : deletedItems
    }

    /// Takes items out of the pile for good, here and in the store. Admin Tools' mock items only here.
    private func settle(_ ids: Set<LibraryItem.ID>, as settlement: Settlement) {
        guard !ids.isEmpty else { return }
        settledIDs.formUnion(ids)
        let real = ids.filter { !LibraryItem.isAdminMock(id: $0) }
        if !real.isEmpty { store.settle(real, as: settlement) }
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
    /// Under limited access a narrowed selection reports its unselected items as removed; they may
    /// still be in the library, so they're only hidden, never settled.
    private func forget(_ ids: Set<LibraryItem.ID>) {
        // The library is smaller now, whoever deleted these, so its total is read again.
        Task { await refreshLibraryTotal() }
        // Our own confirmed deletes come back through here too; they're already settled.
        let gone = ids.subtracting(settledIDs)
        guard !gone.isEmpty else { return }
        if library.currentAccess() == .full {
            settle(gone, as: .gone)
        } else {
            outOfReachIDs.formUnion(gone)
        }
        guard var current = session, current.cards.count > index + 1 else { return }
        current.cards = Array(current.cards.prefix(index + 1))
            + current.cards.dropFirst(index + 1).compactMap { $0.removing(gone) }
        session = current
        saveProgress()
        fillIfNeeded()
    }

    /// - Parameter placeBudget: Overrides how long to wait on place names; nil keeps the default.
    private func makeSession(number: Int, placeBudget: Duration? = nil) async -> Session {
        var options = FeedOptions(skipFavorites: skipFavorites, excluding: store.excludedFromNewSession(asOf: now()), focus: feedFocus)
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
    /// the app while it was closed. Under limited access, items outside the selection leave the deck
    /// and are hidden from the pile, but stay pending in the store.
    private func restore(_ saved: SavedSession) async {
        var restored = saved.session
        var position = saved.index
        // Admin Tools' mock cards don't outlive the launch.
        position -= restored.cards.prefix(position).filter(\.isAdminMock).count
        restored.cards.removeAll(where: \.isAdminMock)
        let savedIndex = position
        let unseen = await library.missing(from: Set(restored.items.map(\.id)).union(store.pile().map(\.id)))
        // Only full access proves an item is gone; a limited selection just hides the rest.
        let gone = library.currentAccess() == .full ? unseen : []
        outOfReachIDs = unseen.subtracting(gone)
        if !unseen.isEmpty {
            // Undo history starts empty, so earlier cards can be pruned too.
            var cards: [FeedCard] = []
            position = 0
            for (offset, card) in restored.cards.enumerated() {
                guard let kept = card.removing(unseen) else { continue }
                cards.append(kept)
                if offset < savedIndex { position += 1 }
            }
            restored.cards = cards
            if !gone.isEmpty { store.settle(gone, as: .gone) }
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
        if !unseen.isEmpty || saved.finished { saveProgress() }
    }

    /// Before limited access was handled, items outside the selection were settled as gone and left
    /// the pile and the feed for good. Once, with full access, any of those still in the library are
    /// reopened so their decision applies again: a delete is back in the pile, still needing the
    /// user's confirmation. Nothing is deleted here.
    private func reopenWronglyGone() async {
        guard library.currentAccess() == .full, !defaults.bool(forKey: DefaultsKey.reopenedLimitedAccessGone) else { return }
        let gone = store.goneIDs()
        let present = gone.subtracting(await library.missing(from: gone))
        if !present.isEmpty {
            store.reopen(present)
            Self.log.info("Reopened \(present.count) items wrongly settled as gone")
        }
        defaults.set(true, forKey: DefaultsKey.reopenedLimitedAccessGone)
    }

    /// Writes `changes` and the deck, durably. The cards are encoded again only when they changed
    /// since they were last written whole; otherwise just the position, marks, and drafts are.
    /// Decisions about Admin Tools' mock items are dropped here, so none ever reaches the store.
    private func saveProgress(with changes: [LibraryItem.ID: StoredDecision?] = [:]) {
        let changes = changes.filter { !LibraryItem.isAdminMock(id: $0.key) }
        guard let session else {
            if !changes.isEmpty { store.save(changes) }
            return
        }
        if savedCardsRevision == cardsRevision,
           store.commit(changes, deck: .position(number: session.number, index: index, marks: marks, drafts: drafts)) {
            return
        }
        store.commit(changes, deck: .full(SavedSession(session: session, index: index, marks: marks, finished: false, drafts: drafts)))
        savedCardsRevision = cardsRevision
    }

    /// Recomputes library totals from saved progress. The freed sum only changes on confirm.
    private func refreshTotals(includingFreed: Bool = true) {
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
    private func updateCelebration() {
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

    /// Hides the "+3.4 MB" chip now.
    func dismissChip() {
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
            return group.removing(ids).map(FeedCard.similar)
        case .duplicates(let group):
            return group.removing(ids).map(FeedCard.duplicates)
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
    fileprivate static let log = Logger.app(category: "feed")
}
