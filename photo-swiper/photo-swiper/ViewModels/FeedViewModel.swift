import Foundation
import Observation

/// Owns the swipe session: cards, decisions, undo, and the running totals.
///
/// Views read from it and call its intents. Animation and haptics stay in the views.
@Observable
@MainActor
final class FeedViewModel {
    enum Phase: Equatable {
        case loading
        /// The user denied photo access.
        case noAccess
        case feed
        case endOfSession
        /// Pending items were confirmed and deleted.
        case celebrated
        /// The user is done for now; nothing left in the feed.
        case caughtUp
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
        let decisions: [LibraryItem.ID: Decision]
        let marks: [SimilarGroup.ID: Set<LibraryItem.ID>]
        let cardID: FeedCard.ID
        let direction: SwipeDirection
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
    /// Something about the last delete the user should know, e.g. items the system refused.
    var deleteNotice: String?
    /// Applies to the next session built.
    var skipFavorites = true

    /// Similar-group overrides. Missing means "everything but the best pick".
    private var marks: [SimilarGroup.ID: Set<LibraryItem.ID>] = [:]
    private var history: [Snapshot] = []
    /// Unconfirmed deletes from earlier sessions the user skipped confirming.
    private var carriedPending: [LibraryItem] = []
    /// Items deleted, gone from the library, or undeletable. They stay decided but are no longer pending.
    private var settledIDs: Set<LibraryItem.ID> = []
    private var chipTask: Task<Void, Never>?
    private var changesTask: Task<Void, Never>?

    private let library: any PhotoLibraryProviding
    private let builder: any FeedBuilding

    init(library: any PhotoLibraryProviding, builder: any FeedBuilding) {
        self.library = library
        self.builder = builder
    }

    /// Starts already loaded. Used by previews and launch-time setup.
    init(library: any PhotoLibraryProviding, builder: any FeedBuilding, session: Session, stats: LibraryStats) {
        self.library = library
        self.builder = builder
        self.stats = stats
        apply(session)
    }

    // MARK: Derived

    var cards: [FeedCard] { session?.cards ?? [] }
    var currentCard: FeedCard? { cards.indices.contains(index) ? cards[index] : nil }
    var nextCard: FeedCard? { cards.indices.contains(index + 1) ? cards[index + 1] : nil }

    /// 1-based position shown as "12 of 20".
    var position: Int { min(index + 1, cards.count) }
    var sessionProgress: Double { cards.isEmpty ? 0 : Double(position) / Double(cards.count) }

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
    private var reviewedInSession: Int { decisions.values.filter { $0 != .later }.count }
    var libraryReviewedCount: Int { stats.reviewedItems + reviewedInSession }
    var libraryReviewedFraction: Double {
        stats.totalItems == 0 ? 0 : Double(libraryReviewedCount) / Double(stats.totalItems)
    }
    var freedBytes: Int64 { stats.freedBytes }

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
        case (.left, .batch(let batch)): "Clear all \(batch.items.count)"
        case (.right, .photo), (.right, .video): "Keep"
        case (.right, _): "Keep all \(card.items.count)"
        }
    }

    // MARK: Intents

    /// Also called again from the no-access screen when the app returns from Settings.
    func start() async {
        guard phase == .loading || phase == .noAccess else { return }
        access = await library.requestAccess()
        guard access != .denied else {
            phase = .noAccess
            return
        }
        phase = .loading
        stats = await library.stats()
        observeLibraryChanges()
        await loadSession(number: 1)
    }

    func decide(_ direction: SwipeDirection) {
        guard phase == .feed, let card = currentCard else { return }
        commit(itemDecisions(for: card, direction: direction), card: card, direction: direction)
    }

    /// Settles the current batch card from a one-by-one review. Items left out count as "later".
    func decideIndividually(_ outcome: [LibraryItem.ID: Decision]) {
        guard phase == .feed, let card = currentCard, case .batch = card else { return }
        let complete = Dictionary(uniqueKeysWithValues: card.items.map { ($0.id, outcome[$0.id] ?? .later) })
        commit(complete, card: card, direction: complete.values.contains(.delete) ? .left : .right)
    }

    func toggleMark(_ itemID: LibraryItem.ID, in group: SimilarGroup) {
        var marked = markedForClearing(in: group)
        if marked.contains(itemID) { marked.remove(itemID) } else { marked.insert(itemID) }
        marks[group.id] = marked
    }

    func undo() {
        guard canUndo, let last = history.popLast() else { return }
        index = last.index
        decisions = last.decisions
        marks = last.marks
        returningCard = ReturningCard(cardID: last.cardID, direction: last.direction)
        dismissChip()
        phase = .feed
    }

    /// Deletes everything pending. Returns false if nothing was deleted, including when
    /// the user cancels the system prompt (everything then stays pending).
    @discardableResult
    func confirmDelete() async -> Bool {
        let items = pendingItems
        guard !items.isEmpty else { return false }
        let outcome: DeletionOutcome
        do {
            outcome = try await library.delete(items)
        } catch DeletionError.cancelled {
            return false
        } catch {
            deleteNotice = "Couldn't delete right now. Nothing was removed."
            return false
        }

        // Gone or undeletable items can't be cleared, so they leave the pile without counting as freed.
        settledIDs.formUnion(outcome.missing)
        settledIDs.formUnion(outcome.undeletable)
        if !outcome.undeletable.isEmpty {
            let n = outcome.undeletable.count
            deleteNotice = "\(n) \(n == 1 ? "item" : "items") can't be deleted from this app and stayed in your library."
        }

        let deleted = Set(outcome.deleted)
        let deletedItems = items.filter { deleted.contains($0.id) }
        guard !deletedItems.isEmpty else { return false }
        applyConfirmedDelete(deletedItems)
        return true
    }

    func startNewSession() async {
        stats.reviewedItems += reviewedInSession
        carriedPending = pendingItems
        await loadSession(number: (session?.number ?? 0) + 1)
    }

    func finishForNow() {
        phase = .caughtUp
    }

    func clearReturningCard() {
        returningCard = nil
    }

    // MARK: Internals

    /// Records per-item decisions for the current card and moves on.
    /// `direction` is the side the card left from, so undo brings it back the same way.
    private func commit(_ outcome: [LibraryItem.ID: Decision], card: FeedCard, direction: SwipeDirection) {
        history.append(Snapshot(index: index, decisions: decisions, marks: marks, cardID: card.id, direction: direction))
        decisions.merge(outcome) { _, new in new }
        returningCard = nil

        let cleared = card.items.filter { outcome[$0.id] == .delete }.reduce(0) { $0 + $1.bytes }
        if cleared > 0 { showChip(bytes: cleared) }

        index += 1
        if index >= cards.count { phase = .endOfSession }
    }

    /// Per-item outcome of swiping a card in a direction.
    private func itemDecisions(for card: FeedCard, direction: SwipeDirection) -> [LibraryItem.ID: Decision] {
        let ids = card.items.map(\.id)
        switch (direction, card) {
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

    private func applyConfirmedDelete(_ items: [LibraryItem]) {
        let bytes = items.reduce(0) { $0 + $1.bytes }
        stats.freedBytes += bytes
        celebration = Celebration(bytes: bytes, count: items.count)
        settledIDs.formUnion(items.map(\.id))
        carriedPending = []
        history.removeAll()
        phase = .celebrated
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
        settledIDs.formUnion(gone)
        guard var current = session, current.cards.count > index + 1 else { return }
        current.cards = Array(current.cards.prefix(index + 1))
            + current.cards.dropFirst(index + 1).compactMap { $0.removing(gone) }
        session = current
    }

    private func loadSession(number: Int) async {
        let next = await builder.makeSession(number: number, options: FeedOptions(skipFavorites: skipFavorites))
        apply(next)
    }

    private func apply(_ next: Session) {
        session = next
        index = 0
        decisions = [:]
        marks = [:]
        history = []
        celebration = nil
        returningCard = nil
        dismissChip()
        phase = next.cards.isEmpty ? .caughtUp : .feed
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
            return .similar(SimilarGroup(id: group.id, items: rest, bestID: group.bestID, reason: group.reason))
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

// MARK: - Mock setup

extension FeedViewModel {
    /// Named starting points for previews and `-startAt` launch arguments.
    enum MockStart: String {
        case first, video, similar, batch, end, celebrated, caughtUp
    }

    static func mock(startingAt start: MockStart = .first) -> FeedViewModel {
        let builder = MockFeedBuilder()
        let library = MockPhotoLibrary()
        let vm = FeedViewModel(
            library: library,
            builder: builder,
            session: builder.makeSessionNow(number: 1),
            stats: LibraryStats(totalItems: library.totalItems, reviewedItems: library.reviewedItems, freedBytes: 0)
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
        case .caughtUp:
            vm.finishForNow()
        }
        return vm
    }

    /// Decides every card with a plausible mix of deletes, keeps, and laters.
    private func simulateSession() {
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
