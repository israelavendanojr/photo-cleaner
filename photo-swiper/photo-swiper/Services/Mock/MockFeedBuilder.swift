import Foundation

#if DEBUG
/// Builds 20-card pages from the bundled mock images: three pages with fresh ids each, then
/// nothing, so the endless deck and caught up can both be reached.
///
/// Card positions mirror the reference demo: videos at 3 and 11, similar shots
/// at 6 and 15, a screenshot batch at 8, three copies of one photo at 13, single photos everywhere
/// else. That's 45 photos, more than a real page's target, so the demo shows off every card kind.
struct MockFeedBuilder: FeedBuilding {
    static let cardsPerSession = 20
    /// Pages after this come back empty.
    static let pageCount = 3

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        makeSessionNow(number: number, options: options)
    }

    /// A plausible mid-sized library.
    func clutterEstimate(excluding: Set<LibraryItem.ID>, now: Date) async -> ClutterEstimate? {
        ClutterEstimate(likelyClearCount: 1_240, likelyClearBytes: 8_400_000_000, screenshotCount: 312, similarGroupCount: 46)
    }

    /// A plausible mid-sized library, mostly analyzed.
    func libraryScan(excluding: Set<LibraryItem.ID>, removed: Set<LibraryItem.ID>, later: Set<LibraryItem.ID>) async -> LibraryScan? {
        Self.scan
    }

    static let scan = LibraryScan(
        buckets: [
            .video: .init(count: 38, bytes: 6_120_000_000),
            .duplicate: .init(count: 214, bytes: 1_870_000_000),
            .similar: .init(count: 486, bytes: 1_310_000_000),
            .screenshot: .init(count: 312, bytes: 540_000_000),
            .burst: .init(count: 92, bytes: 260_000_000),
            .photo: .init(count: 7_260, bytes: 17_900_000_000),
        ],
        focusBuckets: [
            .allVideos: .init(count: 1_120, bytes: 18_700_000_000),
            .livePhotos: .init(count: 4_010, bytes: 11_900_000_000),
            .accidental: .init(count: 140, bytes: 410_000_000),
            .blurry: .init(count: 380, bytes: 1_120_000_000),
            .documents: .init(count: 260, bytes: 520_000_000),
            .savedForLater: .init(count: 27, bytes: 96_000_000),
        ],
        indexedCount: 17_820, indexedBytes: 64_000_000_000, scanPercent: 86
    )

    /// Synchronous variant for previews and launch-time setup.
    func makeSessionNow(number: Int, options: FeedOptions = FeedOptions()) -> Session {
        guard number <= Self.pageCount else { return Session(number: number, cards: []) }
        var factory = Factory(session: number, options: options)
        let cards = (0..<Self.cardsPerSession).map { factory.card(at: $0) }.enumerated().filter { offset, card in
            guard let focus = options.focus else { return true }
            // The mock has no Live Photos of its own: single photos at even positions stand in for them.
            if focus == .livePhotos, case .photo = card { return offset.isMultiple(of: 2) }
            return card.matches(focus, only: options.only)
        }.map(\.element)
        return Session(number: number, cards: cards, scanPercentAtStart: number == 1 ? 38 : nil)
    }
}

// MARK: - Factory

/// The bundled mock images and places, shared by the mock deck and Admin Tools' mock cards.
enum MockImages {
    static let photos = [
        "photo-sunset", "photo-beach", "photo-desert", "photo-hills", "photo-dusk",
        "photo-coast", "photo-pink", "photo-night", "photo-room", "photo-cafe",
    ]
    static let pocket = "photo-pocket"
    static let receipt = "photo-receipt"
    static let screenshots = ["shot-light", "shot-dark", "shot-cream", "shot-sand", "shot-lavender"]
    static let videos = ["video-waves", "video-party"]
    /// Similar sets: each has variants 1 to `similarVariants`, e.g. "similar-a-3".
    static let similarSets = ["similar-a", "similar-b"]
    static let similarVariants = 6
    static let locations = ["Santa Monica", "Los Angeles", "Joshua Tree", "Ojai", "Malibu", "Pasadena", "Big Sur", "Home"]
}

private struct Factory {
    private static let photoImages = MockImages.photos
    private static let screenshotImages = MockImages.screenshots
    private static let locations = MockImages.locations

    let session: Int
    let options: FeedOptions
    private var rng: SeededGenerator
    private let start: Date
    private var day: Date
    private var itemCount = 0

    init(session: Int, options: FeedOptions) {
        self.session = session
        self.options = options
        rng = SeededGenerator(seed: UInt64(17 + session * 101))
        // Session 1 starts on Saturday, September 14, 2024; each later session goes back a month.
        let start = Calendar.current.date(from: DateComponents(year: 2024, month: 9, day: 14, hour: 18))!
        self.start = Calendar.current.date(byAdding: .day, value: -30 * (session - 1), to: start)!
        day = self.start
    }

    mutating func card(at index: Int) -> FeedCard {
        switch index {
        case 3: .video(video(bytes: 1_228_000_000, duration: 252, image: "video-waves", location: "Malibu"))
        case 11: .video(video(bytes: 846_000_000, duration: 167, image: "video-party", location: "Home"))
        case 6: .similar(similar(cardIndex: index, image: "similar-a", reason: "Sharpest of the set"))
        case 15: .similar(similar(cardIndex: index, image: "similar-b", reason: "Best exposure"))
        case 8: .batch(screenshots(cardIndex: index))
        case 13: .duplicates(duplicates(cardIndex: index, image: "photo-coast"))
        default: .photo(photo())
        }
    }

    // MARK: Card kinds

    private mutating func photo() -> LibraryItem {
        let roll = rng.unit()
        let flags: [LibraryItem.Flag] = roll < 0.14 ? [.blurry] : roll < 0.24 ? [.accidental] : []
        // An untagged receipt-looking photo. Same odds and random draws as before, so the mock deck doesn't shift.
        let isReceipt = (0.24..<0.29).contains(roll)
        let image = if flags.first == .accidental {
            MockImages.pocket
        } else if isReceipt {
            MockImages.receipt
        } else {
            Self.photoImages[Int(rng.unit() * Double(Self.photoImages.count))]
        }
        // Favorites only appear when the user hasn't asked to skip them.
        let isFavorite = !options.skipFavorites && flags.isEmpty && !isReceipt && rng.unit() < 0.15
        return LibraryItem(
            id: nextID(),
            kind: .photo,
            date: nextDate(),
            location: Self.locations[Int(rng.unit() * Double(Self.locations.count))],
            bytes: megabytes(1.8 + rng.unit() * 4),
            flags: flags,
            isFavorite: isFavorite,
            image: .bundled(image)
        )
    }

    private mutating func video(bytes: Int64, duration: TimeInterval, image: String, location: String) -> LibraryItem {
        LibraryItem(id: nextID(), kind: .video(duration: duration), date: nextDate(), location: location, bytes: bytes, image: .bundled(image))
    }

    private mutating func similar(cardIndex: Int, image: String, reason: String) -> SimilarGroup {
        let date = nextDate()
        let items = (1...6).map { variant in
            LibraryItem(
                id: nextID(), kind: .photo, date: date, location: "Santa Monica",
                bytes: megabytes(3 + rng.unit() * 0.6), image: .bundled("\(image)-\(variant)")
            )
        }
        return SimilarGroup(id: cardID(cardIndex), items: items, bestID: items[0].id, reason: reason)
    }

    /// One photo saved three times, months apart; the newest copy is the largest, so it's the keeper.
    private mutating func duplicates(cardIndex: Int, image: String) -> DuplicateGroup {
        let saved = nextDate()
        let dates = [
            saved,
            Calendar.current.date(byAdding: .day, value: -47, to: saved)!,
            Calendar.current.date(byAdding: .day, value: -212, to: saved)!,
        ]
        let sizes = [4.2, 1.6, 1.4]
        let items = zip(dates, sizes).map { date, mb in
            LibraryItem(id: nextID(), kind: .photo, date: date, location: "Malibu", bytes: megabytes(mb), image: .bundled(image))
        }
        let others = items.dropFirst().sorted { $0.date < $1.date }
        return DuplicateGroup(id: cardID(cardIndex), items: [items[0]] + others, keepID: items[0].id, reason: "Highest resolution")
    }

    private mutating func screenshots(cardIndex: Int) -> ItemBatch {
        // "Last week" relative to the session's newest photo.
        let weekStart = Calendar.current.date(byAdding: .day, value: 8, to: start)!
        let items = (0..<14).map { k in
            LibraryItem(
                id: nextID(), kind: .photo,
                date: Calendar.current.date(byAdding: .day, value: k % 7, to: weekStart)!,
                location: "iPhone", bytes: megabytes(2 + rng.unit() * 1.2), flags: [.screenshot],
                image: .bundled(Self.screenshotImages[k % Self.screenshotImages.count])
            )
        }
        return ItemBatch(id: cardID(cardIndex), kind: .screenshots, label: "Screenshots", title: "14 screenshots from last week", items: items)
    }

    // MARK: Helpers

    private mutating func nextID() -> LibraryItem.ID {
        defer { itemCount += 1 }
        return "s\(session)-i\(itemCount)"
    }

    private func cardID(_ index: Int) -> String { "s\(session)-c\(index)" }

    /// Walks backwards through time, 0–2 days per item.
    private mutating func nextDate() -> Date {
        day = Calendar.current.date(byAdding: .day, value: -Int(rng.unit() * 2.2), to: day)!
        return day
    }

    private func megabytes(_ mb: Double) -> Int64 {
        Int64((mb * 10).rounded() * 100_000)
    }
}
#endif
