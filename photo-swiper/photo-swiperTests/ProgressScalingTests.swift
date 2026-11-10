import Foundation
import SwiftData
import Testing
@testable import photo_swiper

/// What one swipe costs in saved progress with 50,000 items already decided (JUN-5 audit, Q-2).
///
/// Mirrors the store calls `FeedViewModel.commit` makes per swipe (read the card's earlier decisions,
/// one commit of decisions and position, the reviewed count), on an on-disk store, and the exclusion
/// query each page makes. Timings go to the log as `SCALING | …`; see `ScalingTests`.
@MainActor
@Suite(.serialized, .tags(.scaling), .timeLimit(.minutes(10)))
struct ProgressScalingTests {
    static let rows = 50_000
    static let swipes = 200
    private let clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ id: String, at offset: TimeInterval) -> LibraryItem {
        LibraryItem(id: id, kind: .photo, date: clock.addingTimeInterval(offset), location: nil, bytes: 3_000_000,
                    image: .photoKit(localIdentifier: id))
    }

    /// An on-disk store with `rows` decisions: mostly keeps, some deletes (a few settled), some laters.
    private func filledStore() throws -> SwiftDataProgressStore {
        let directory = FileManager.default.temporaryDirectory.appending(path: "progress-scaling-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SwiftDataProgressStore(container: try SwiftDataProgressStore.makeContainer(url: directory.appending(path: "p.store")), defaults: nil)
        let started = Date.now
        for start in stride(from: 0, to: Self.rows, by: 5_000) {
            var batch: [LibraryItem.ID: StoredDecision?] = [:]
            for n in start..<min(start + 5_000, Self.rows) {
                let decision: Decision = n % 10 == 0 ? .delete : n % 7 == 0 ? .later : .keep
                batch["old-\(n)"] = StoredDecision(decision: decision, decidedAt: clock.addingTimeInterval(-Double(n) * 60),
                                                   sessionNumber: n / 20, item: item("old-\(n)", at: -Double(n) * 60))
            }
            store.save(batch)
        }
        store.settle(Set(stride(from: 0, to: Self.rows, by: 20).map { "old-\($0)" }), as: .deleted)
        ScalingReport.line("filled progress store with \(Self.rows) rows in \(Date.now.timeIntervalSince(started).ms)")
        return store
    }

    @Test func aSwipeAt50kDecisions() throws {
        let store = try filledStore()
        // A deck like the real one: about 90 cards, one item each.
        let cards = (0..<90).map { FeedCard.photo(item("deck-\($0)", at: Double($0))) }
        let saved = SavedSession(session: Session(number: Self.rows / 20 + 1, cards: cards), index: 0, marks: [:], finished: false)
        store.commit([:], deck: .full(saved))

        // Before any page: the count comes from disk, as at launch.
        var loading = Date.now
        _ = store.reviewedCount()
        ScalingReport.line("reviewedCount at launch at \(Self.rows) rows: \(Date.now.timeIntervalSince(loading).ms)")
        // The first page reads every decision once; after that they're kept up to date.
        loading = .now
        _ = store.excludedFromNewSession(asOf: clock)
        ScalingReport.line("first page's excludedFromNewSession at \(Self.rows) rows (reads them all once): \(Date.now.timeIntervalSince(loading).ms)")

        var read = 0.0, save = 0.0, count = 0.0
        for n in 0..<Self.swipes {
            let card = cards[n % cards.count]
            let ids = Set(card.items.map(\.id))
            var started = Date.now
            _ = store.decisions(for: ids)
            read += Date.now.timeIntervalSince(started)

            started = .now
            let changes = Dictionary(uniqueKeysWithValues: card.items.map {
                ($0.id, Optional(StoredDecision(decision: n.isMultiple(of: 3) ? .delete : .keep, decidedAt: clock,
                                                sessionNumber: saved.session.number, item: $0)))
            })
            store.commit(changes, deck: .position(number: saved.session.number, index: n % cards.count + 1, marks: [:], drafts: [:]))
            save += Date.now.timeIntervalSince(started)

            started = .now
            _ = store.reviewedCount()
            count += Date.now.timeIntervalSince(started)
        }
        let swipes = Double(Self.swipes)
        let total = (read + save + count) / swipes
        ScalingReport.line("per swipe at \(Self.rows) rows: \(total.ms) total = read \((read / swipes).ms) + commit \((save / swipes).ms) + reviewedCount \((count / swipes).ms)")

        var exclusions = 0.0
        for _ in 0..<10 {
            let started = Date.now
            _ = store.excludedFromNewSession(asOf: clock)
            exclusions += Date.now.timeIntervalSince(started)
        }
        ScalingReport.line("per page at \(Self.rows) rows: excludedFromNewSession \((exclusions / 10).ms)")

        #expect(store.reviewedCount() > 0)
    }
}
