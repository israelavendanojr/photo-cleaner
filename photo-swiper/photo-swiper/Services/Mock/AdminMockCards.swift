import Foundation

#if DEBUG
/// A kind of mock card Admin Tools can put on top of the deck.
enum AdminMockKind: String, CaseIterable, Identifiable {
    case photo, video, similar, duplicates, screenshots

    var id: Self { self }

    var title: String {
        switch self {
        case .photo: "Photo"
        case .video: "Video"
        case .similar: "Similar shots"
        case .duplicates: "Duplicates"
        case .screenshots: "Screenshots"
        }
    }

    var icon: String {
        switch self {
        case .photo: "photo"
        case .video: "video"
        case .similar: "square.stack"
        case .duplicates: "plus.square.on.square"
        case .screenshots: "iphone"
        }
    }
}

/// Randomized cards from the bundled mock images, for checking how each card kind looks with
/// different sizes, counts, dates and reasons. Every item id starts with `idPrefix`, so the feed can
/// tell them apart: they're never saved and never reach the library (see `LibraryItem.isAdminMock`).
enum AdminMockCards {
    static let idPrefix = "admin-"

    static let similarCounts = 2...12
    static let duplicateCounts = 2...5
    static let screenshotCounts = 2...40

    static func card(_ kind: AdminMockKind, using rng: inout some RandomNumberGenerator, now: Date = .now) -> FeedCard {
        var maker = Maker(prefix: idPrefix + UUID().uuidString.prefix(8).lowercased(), now: now)
        return switch kind {
        case .photo: .photo(maker.photo(using: &rng))
        case .video: .video(maker.video(using: &rng))
        case .similar: .similar(maker.similar(using: &rng))
        case .duplicates: .duplicates(maker.duplicates(using: &rng))
        case .screenshots: .batch(maker.screenshots(using: &rng))
        }
    }
}

private struct Maker {
    let prefix: String
    let now: Date
    private var count = 0

    init(prefix: String, now: Date) {
        self.prefix = prefix
        self.now = now
    }

    mutating func photo(using rng: inout some RandomNumberGenerator) -> LibraryItem {
        let image = Double.random(in: 0..<1, using: &rng) < 0.15
            ? [MockImages.pocket, MockImages.receipt].randomElement(using: &rng)!
            : MockImages.photos.randomElement(using: &rng)!
        return LibraryItem(
            id: nextID(), kind: .photo, date: date(withinDays: 5 * 365, using: &rng),
            location: location(using: &rng), bytes: megabytes(0.8...12, using: &rng),
            isFavorite: Double.random(in: 0..<1, using: &rng) < 0.15, image: .bundled(image)
        )
    }

    /// Roughly 1–8 MB a second, like phone video from 720p to 4K.
    mutating func video(using rng: inout some RandomNumberGenerator) -> LibraryItem {
        let duration = TimeInterval(Int.random(in: 3...(25 * 60), using: &rng))
        let rate = Double.random(in: 1...8, using: &rng) * 1_000_000
        return LibraryItem(
            id: nextID(), kind: .video(duration: duration), date: date(withinDays: 5 * 365, using: &rng),
            location: location(using: &rng), bytes: Int64(duration * rate),
            image: .bundled(MockImages.videos.randomElement(using: &rng)!)
        )
    }

    mutating func similar(using rng: inout some RandomNumberGenerator) -> SimilarGroup {
        let set = MockImages.similarSets.randomElement(using: &rng)!
        let date = date(withinDays: 5 * 365, using: &rng)
        let place = location(using: &rng)
        let base = Double.random(in: 1.5...5, using: &rng)
        let items = (0..<Int.random(in: AdminMockCards.similarCounts, using: &rng)).map { k in
            LibraryItem(
                id: nextID(), kind: .photo, date: date.addingTimeInterval(Double(k)), location: place,
                bytes: megabytes(base...(base + 0.6), using: &rng),
                image: .bundled("\(set)-\(k % MockImages.similarVariants + 1)")
            )
        }
        return SimilarGroup(id: nextID(), items: items, bestID: items.randomElement(using: &rng)!.id,
                            reason: BestPick.Reason.allCases.randomElement(using: &rng)!.rawValue)
    }

    /// The keeper is the largest copy and comes first; the rest follow oldest first.
    mutating func duplicates(using rng: inout some RandomNumberGenerator) -> DuplicateGroup {
        let image = MockImages.photos.randomElement(using: &rng)!
        let place = location(using: &rng)
        let keeperBytes = megabytes(2...9, using: &rng)
        let keeper = LibraryItem(id: nextID(), kind: .photo, date: date(withinDays: 3 * 365, using: &rng),
                                 location: place, bytes: keeperBytes, image: .bundled(image))
        let others = (1..<Int.random(in: AdminMockCards.duplicateCounts, using: &rng)).map { _ in
            LibraryItem(
                id: nextID(), kind: .photo,
                date: keeper.date.addingTimeInterval(-Double.random(in: 1...(4 * 365), using: &rng) * 86_400),
                location: place, bytes: Int64(Double(keeperBytes) * Double.random(in: 0.2...0.95, using: &rng)),
                image: .bundled(image)
            )
        }.sorted { $0.date < $1.date }
        return DuplicateGroup(id: nextID(), items: [keeper] + others, keepID: keeper.id,
                              reason: DuplicatePick.Reason.allCases.randomElement(using: &rng)!.rawValue)
    }

    mutating func screenshots(using rng: inout some RandomNumberGenerator) -> ItemBatch {
        let count = Int.random(in: AdminMockCards.screenshotCounts, using: &rng)
        let start = date(withinDays: 2 * 365, using: &rng)
        let items = (0..<count).map { k in
            LibraryItem(
                id: nextID(), kind: .photo, date: start.addingTimeInterval(-Double(k % 7) * 86_400),
                location: "iPhone", bytes: megabytes(0.4...3.5, using: &rng), flags: [.screenshot],
                image: .bundled(MockImages.screenshots.randomElement(using: &rng)!)
            )
        }
        let when = ["this week", "last week", "the week of \(Format.shortDay(start))"].randomElement(using: &rng)!
        return ItemBatch(id: nextID(), kind: .screenshots, label: "Screenshots",
                         title: "\(count) screenshots from \(when)", items: items)
    }

    // MARK: Helpers

    private mutating func nextID() -> String {
        defer { count += 1 }
        return "\(prefix)-\(count)"
    }

    private func date(withinDays days: Int, using rng: inout some RandomNumberGenerator) -> Date {
        now.addingTimeInterval(-Double.random(in: 0...Double(days), using: &rng) * 86_400)
    }

    /// A place most of the time, none now and then.
    private func location(using rng: inout some RandomNumberGenerator) -> String? {
        Double.random(in: 0..<1, using: &rng) < 0.2 ? nil : MockImages.locations.randomElement(using: &rng)
    }

    private func megabytes(_ range: ClosedRange<Double>, using rng: inout some RandomNumberGenerator) -> Int64 {
        Int64(Double.random(in: range, using: &rng) * 1_000_000)
    }
}
#endif

extension LibraryItem {
    /// An item on an Admin Tools mock card. Its decisions live only in memory: it never costs a swipe,
    /// is never written to the store, and never reaches `library.delete`. A delete puts it in the pile,
    /// where it counts toward the free limit, and deleting it from there just drops it.
    /// Outside `#if DEBUG` because the feed's guards run in every build; only debug builds can make one.
    var isAdminMock: Bool { Self.isAdminMock(id: id) }

    /// Real ids are PhotoKit local identifiers, which never start this way.
    static func isAdminMock(id: ID) -> Bool {
        id.hasPrefix("admin-")
    }
}

extension FeedCard {
    /// An Admin Tools mock card (see `LibraryItem.isAdminMock`).
    /// Photo and video card ids carry the item's id after "item-", so this goes by the items.
    var isAdminMock: Bool {
        items.first?.isAdminMock == true
    }
}
