import Foundation
import Observation

/// Owns the swipe session: cards, decisions, undo, and the running totals.
///
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
        case endOfSession
        /// Pending items were confirmed and deleted.
        case celebrated
        /// The user chose to stop ("Done for now"), or confirmed and left. More is waiting.
        case resting
        /// The feed is genuinely exhausted: a new session found nothing to show.
        case caughtUp
    }

    enum PaywallStatus: Equatable {
        case idle, purchasing, restoring, purchaseFailed, restoreFailed
    }

    /// The "+3.4 MB" chip shown briefly after a delete.
    struct DeleteChip: Equatable {
        let id = UUID()
        let bytes: Int64
    }

    struct Celebration: Equatable {
        let bytes: Int64
        let count: Int
    }

    /// The card an undo just restored, and the side it left from.
    struct ReturningCard: Equatable {
        let cardID: FeedCard.ID
        let direction: SwipeDirection
    }

    private struct Snapshot {
        let index: Int
        var decisions: [LibraryItem.ID: Decision]
        var marks: [SimilarGroup.ID: Set<LibraryItem.ID>]
        let drafts: [ItemBatch.ID: [LibraryItem.ID: Decision]]
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
    private(set) var celebration: Celebration?
    private(set) var stats = LibraryStats(totalItems: 0, reviewedItems: 0, freedBytes: 0)
    private(set) var access = LibraryAccess.full
    /// The system access prompt is up.
    private(set) var isRequestingAccess = false
    /// Access was just granted from onboarding and the first session is being built.
    /// Onboarding stays up meanwhile instead of a loading screen.
    private(set) var isPreparingFirstSession = false
    /// Resting was restored at launch, so the rest screen greets the user back.
    private(set) var isWelcomeBack = false
    private(set) var paywallStatus = PaywallStatus.idle
    /// The free swipes. Never spent or checked while unlocked.
    private(set) var allowance: SwipeAllowance
    /// "Out of swipes": the wall sheet over the feed, offering the unlock.
    var isWallPresented = false
    /// What's left to clear, worked out when the wall opens.
    private(set) var clutterEstimate: ClutterEstimate?
    /// The user tapped "Remind me" and the system said yes.
    private(set) var isRemindersOptedIn = false
    /// The user tapped "Remind me" and notifications are turned off.
    private(set) var areRemindersDenied = false
    /// Something about the last delete the user should know, e.g. items the system refused.
    var deleteNotice: String?
    /// Applies to the next session built.
    var skipFavorites = true {
        didSet { store.skipFavorites = skipFavorites }
    }

    /// Similar-group overrides. Missing means "everything but the best pick".
    private var marks: [SimilarGroup.ID: Set<LibraryItem.ID>] = [:]
    /// One-by-one decisions for batches reviewed partway. Applied when the batch card is swiped.
    private var drafts: [ItemBatch.ID: [LibraryItem.ID: Decision]] = [:]
    private var history: [Snapshot] = []
    /// Unconfirmed deletes from earlier sessions the user skipped confirming.
    private var carriedPending: [LibraryItem] = []
    /// Items deleted, gone from the library, or undeletable. They stay decided but are no longer pending.
    private var settledIDs: Set<LibraryItem.ID> = []
    /// The user is done with this session ("Done for now" or confirmed); relaunch shows resting.
    private var finished = false
    /// Totals the library reports itself; saved progress is added on top.
    private var libraryStats = LibraryStats(totalItems: 0, reviewedItems: 0, freedBytes: 0)
    private var chipTask: Task<Void, Never>?
    private var changesTask: Task<Void, Never>?
    /// A refill landed while no session could take the strongest cards first; the next one dealt does.
    private var refilledSinceDeal = false
    /// Off while mocks play a session through, so their setup doesn't spend the allowance.
    private var chargesSwipes = true

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

    /// Photos swiped so far, shown as "12 of 20". A bundle adds all of its photos at once.
    var photosReviewed: Int { cards.prefix(index).reduce(0) { $0 + $1.items.count } }
    var photoTotal: Int { session?.photoCount ?? 0 }
    var sessionProgress: Double { photoTotal == 0 ? 0 : Double(photosReviewed) / Double(photoTotal) }

    /// "Still scanning" percentage, shown only early in the first session.
    var scanningPercent: Int? {
        guard let start = session?.scanPercentAtStart, index < 10 else { return nil }
        return min(start + index * 4, 99)
    }

    var canUndo: Bool { !history.isEmpty && (phase == .feed || phase == .endOfSession) }

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
    /// Free swipes left; nil when unlocked, where nothing is counted.
    var swipesLeft: Int? { isUnlocked ? nil : allowance.remaining }
    /// When the next refill lands; nil when unlocked or full.
    var nextRefillAt: Date? { isUnlocked ? nil : allowance.nextRefillAt(allowanceTunables) }
    /// Days of free swipes it would take to get through the likely clears.
    var daysToFinish: Double? { clutterEstimate?.daysToFinish(swipesPerDay: allowanceTunables.swipesPerDay) }
    /// "Remind me when swipes are back" can be offered.
    var canRemind: Bool { notifier != nil }

    /// The number the next new session gets.
    private var nextSessionNumber: Int { max(session?.number ?? 0, store.lastSessionNumber()) + 1 }

    // MARK: Card helpers

    /// Items in a similar group that a left swipe would clear.
    func markedForClearing(in group: SimilarGroup) -> Set<LibraryItem.ID> {
        marks[group.id] ?? Set(group.others.map(\.id))
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
        case (.left, .similar(let group)):
            markedForClearing(in: group).isEmpty ? "Keep all \(group.items.count)" : "Clear \(markedForClearing(in: group).count)"
        case (.left, .batch(let batch)) where drafts[batch.id] == nil: "Clear all \(batch.items.count)"
        case (.left, .batch(let batch)):
            switch itemDecisions(for: card, direction: .left).values.filter({ $0 == .delete }).count {
            case 0: "Keep all \(batch.items.count)"
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
        guard phase == .loading || phase == .noAccess || phase == .onboarding, !isRequestingAccess else { return }
        if phase == .loading, library.needsAccessPrompt(), !defaults.bool(forKey: DefaultsKey.hasOnboarded) {
            phase = .onboarding
            return
        }
        let fromOnboarding = phase == .onboarding
        if fromOnboarding { defaults.set(true, forKey: DefaultsKey.hasOnboarded) }
        isRequestingAccess = true
        access = await library.requestAccess()
        isRequestingAccess = false
        guard access != .denied else {
            phase = .noAccess
            return
        }
        if fromOnboarding {
            isPreparingFirstSession = true
        } else {
            phase = .loading
        }
        indexScheduler?.accessGranted()
        let clock = ContinuousClock()
        let started = clock.now
        libraryStats = await library.stats()
        observeLibraryChanges()
        let saved = store.loadSession()
        // Captions can do without place names for the first session; they arrive with the next.
        let next = saved == nil
            ? await makeSession(number: store.lastSessionNumber() + 1, placeBudget: fromOnboarding ? .zero : nil)
            : nil
        if fromOnboarding {
            let remaining = firstSessionMinimum - (clock.now - started)
            if remaining > .zero { try? await Task.sleep(for: remaining) }
        }
        if let saved {
            await restore(saved)
        } else if let next {
            apply(next)
        }
        isPreparingFirstSession = false
        refreshTotals()
        // Credits refills from time away, which also puts the strongest cards first.
        refreshAllowance()
        if isUnlocked { notifier?.cancelAll(now: now()) }
    }

    /// Out of free swipes, nothing is committed and the wall opens instead.
    func decide(_ direction: SwipeDirection) {
        guard phase == .feed, let card = currentCard, admitSwipe() else { return }
        commit(itemDecisions(for: card, direction: direction), card: card, direction: direction)
    }

    /// Settles the current batch card from a one-by-one review. Items left out count as "later".
    /// It costs one swipe like any card; out of swipes, the review is kept as a draft and the wall opens.
    func decideIndividually(_ outcome: [LibraryItem.ID: Decision]) {
        guard phase == .feed, let card = currentCard, case .batch(let batch) = card else { return }
        guard admitSwipe() else {
            saveDraft(outcome, for: batch)
            return
        }
        let complete = Dictionary(uniqueKeysWithValues: card.items.map { ($0.id, outcome[$0.id] ?? .later) })
        commit(complete, card: card, direction: complete.values.contains(.delete) ? .left : .right)
    }

    /// Decisions from an unfinished one-by-one review of this batch.
    func draft(for batch: ItemBatch) -> [LibraryItem.ID: Decision] {
        drafts[batch.id] ?? [:]
    }

    func saveDraft(_ outcome: [LibraryItem.ID: Decision], for batch: ItemBatch) {
        drafts[batch.id] = outcome.isEmpty ? nil : outcome
        saveProgress()
    }

    func toggleMark(_ itemID: LibraryItem.ID, in group: SimilarGroup) {
        var marked = markedForClearing(in: group)
        if marked.contains(itemID) { marked.remove(itemID) } else { marked.insert(itemID) }
        marks[group.id] = marked
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

    /// Deletes everything pending. Returns false if nothing was deleted, including when
    /// the user cancels the system prompt (everything then stays pending).
    @discardableResult
    func confirmDelete() async -> Bool {
        guard let deletedItems = await delete(pendingItems) else { return false }
        applyConfirmedDelete(deletedItems)
        return true
    }

    /// Deletes some of the pile right away, from the pending screen. The session carries on,
    /// and the rest stays pending. Returns false if nothing was deleted.
    @discardableResult
    func deleteNow(_ items: [LibraryItem]) async -> Bool {
        let pending = Set(pendingItems.map(\.id))
        guard let deletedItems = await delete(items.filter { pending.contains($0.id) }) else { return false }
        let ids = Set(deletedItems.map(\.id))
        settle(ids, as: .deleted)
        carriedPending.removeAll { ids.contains($0.id) }
        // A deleted photo can't be swiped again.
        history.removeAll()
        saveProgress()
        refreshTotals()
        return true
    }

    /// "Keep going" and "Start another session". Never gated: only swipes are.
    func requestNextSession() async {
        await loadSession(number: nextSessionNumber)
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
        guard paywallStatus != .purchasing, paywallStatus != .restoring else { return }
        isWallPresented = false
    }

    /// Buys the unlock from the wall. The current card can be swiped straight away. False if it didn't go through.
    @discardableResult
    func unlockFromWall() async -> Bool {
        await settleWall(.purchasing, failure: .purchaseFailed) { await $0.unlock() }
    }

    /// Restores an earlier purchase from the wall.
    @discardableResult
    func restoreFromWall() async -> Bool {
        await settleWall(.restoring, failure: .restoreFailed) { await $0.restore() }
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

    func finishForNow() {
        finished = true
        isWelcomeBack = false
        phase = .resting
        saveProgress()
    }

    func clearReturningCard() {
        returningCard = nil
    }

    // MARK: Internals

    private func settleWall(
        _ working: PaywallStatus,
        failure: PaywallStatus,
        _ attempt: (any EntitlementStore) async -> Bool
    ) async -> Bool {
        guard isWallPresented, paywallStatus != .purchasing, paywallStatus != .restoring else { return false }
        paywallStatus = working
        guard await attempt(entitlements), entitlements.isUnlocked else {
            paywallStatus = failure
            return false
        }
        notifier?.cancelAll(now: now())
        paywallStatus = .idle
        isWallPresented = false
        return true
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
        // Similar sets still ahead in this session count too.
        estimate.similarGroupCount += cards.dropFirst(index).filter { if case .similar = $0 { true } else { false } }.count
        clutterEstimate = estimate
    }

    /// Moves the strongest cards still to come to the front, or leaves it to the next session dealt.
    private func frontLoad() {
        guard phase == .feed, var current = session else {
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
        if index >= cards.count { phase = .endOfSession }
        saveProgress()
        refreshTotals(includingFreed: false)
    }

    /// Per-item outcome of swiping a card in a direction.
    private func itemDecisions(for card: FeedCard, direction: SwipeDirection) -> [LibraryItem.ID: Decision] {
        let ids = card.items.map(\.id)
        switch (direction, card) {
        case (_, .batch(let batch)) where drafts[batch.id] != nil:
            // Items from a partial review keep their decision; the rest follow the swipe.
            let draft = drafts[batch.id] ?? [:]
            let rest: Decision = switch direction {
            case .left: .delete
            case .right: .keep
            case .up: .later
            }
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, draft[$0] ?? rest) })
        case (.up, _):
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, .later) })
        case (.right, _):
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, .keep) })
        case (.left, .similar(let group)):
            let marked = markedForClearing(in: group)
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, marked.contains($0) ? .delete : .keep) })
        case (.left, _):
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, .delete) })
        }
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

    private func applyConfirmedDelete(_ items: [LibraryItem]) {
        let bytes = items.reduce(0) { $0 + $1.bytes }
        settle(Set(items.map(\.id)), as: .deleted)
        celebration = Celebration(bytes: bytes, count: items.count)
        isWallPresented = false
        carriedPending = []
        history.removeAll()
        finished = true
        phase = .celebrated
        saveProgress()
        refreshTotals()
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
    }

    private func loadSession(number: Int) async {
        apply(await makeSession(number: number))
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
        session = next
        index = 0
        decisions = [:]
        marks = [:]
        drafts = [:]
        history = []
        finished = false
        isWelcomeBack = false
        let ids = Set(next.items.map(\.id))
        carriedPending = store.pile().filter { !ids.contains($0.id) }
        celebration = nil
        returningCard = nil
        dismissChip()
        phase = next.cards.isEmpty ? .caughtUp : .feed
        saveProgress()
    }

    /// Picks up a saved session, dropping anything deleted outside the app while it was closed.
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

        let ids = Set(restored.items.map(\.id))
        let records = store.decisions(for: ids).filter { $0.value.sessionNumber == restored.number }
        session = restored
        index = position
        marks = saved.marks
        drafts = saved.drafts
        decisions = records.mapValues(\.decision)
        settledIDs = Set(records.filter { $0.value.settlement != nil }.keys).union(gone)
        carriedPending = store.pile().filter { !ids.contains($0.id) }
        finished = saved.finished
        history = []
        celebration = nil
        returningCard = nil
        isWelcomeBack = finished && !cards.isEmpty
        phase = if cards.isEmpty { .caughtUp } else if finished { .resting } else if index < cards.count { .feed } else { .endOfSession }
        if !gone.isEmpty { saveProgress() }
    }

    private func saveProgress() {
        guard let session else { return }
        store.saveSession(SavedSession(session: session, index: index, marks: marks, finished: finished, drafts: drafts))
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
}

// MARK: - Mock setup

#if DEBUG
extension FeedViewModel {
    /// Named starting points for previews and `-startAt` launch arguments.
    enum MockStart: String {
        case first, video, similar, batch, end, celebrated, onboarding
        /// The session's end with everything kept: nothing pending, nothing freed.
        case endNothingToClear
        /// Done for now with deletes still pending.
        case resting
        /// Confirmed, then done for now: freed bytes, nothing pending.
        case celebratedRest
        /// Resting, as restored on a later launch.
        case welcomeBack
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
            let suite = "mock.onboarding"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            return FeedViewModel(
                library: MockPhotoLibrary(needsPrompt: true),
                builder: MockFeedBuilder(),
                entitlements: entitlements,
                defaults: defaults,
                firstSessionMinimum: onboardingPreparingMinimum
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
        case .end, .celebrated:
            vm.simulateSession()
            if start == .celebrated { vm.applyConfirmedDelete(vm.pendingItems) }
        case .resting, .celebratedRest, .welcomeBack:
            vm.simulateSession()
            if start == .celebratedRest { vm.applyConfirmedDelete(vm.pendingItems) }
            vm.finishForNow()
            vm.isWelcomeBack = start == .welcomeBack
        case .endNothingToClear:
            vm.chargesSwipes = false
            while vm.phase == .feed { vm.decide(.right) }
            vm.chargesSwipes = true
            vm.dismissChip()
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

    /// Shows a wall state without going through a purchase, for previews.
    func previewWall(status: PaywallStatus) {
        isWallPresented = true
        paywallStatus = status
    }

    /// Decides every card with a plausible mix of deletes, keeps, and laters.
    private func simulateSession() {
        chargesSwipes = false
        defer { chargesSwipes = true }
        while phase == .feed {
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
