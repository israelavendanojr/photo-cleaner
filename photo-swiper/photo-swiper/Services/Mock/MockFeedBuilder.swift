import Foundation

/// Builds a 50-card session from the bundled mock images.
///
/// Card positions mirror the reference demo: videos at 7 and 24, similar shots
/// at 12 and 31, batches at 14 and 36, single photos everywhere else.
struct MockFeedBuilder: FeedBuilding {
    static let cardsPerSession = 50

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        makeSessionNow(number: number, options: options)
    }

    /// Synchronous variant for previews and launch-time setup.
    func makeSessionNow(number: Int, options: FeedOptions = FeedOptions()) -> Session {
        var factory = Factory(session: number, options: options)
        let cards = (0..<Self.cardsPerSession).map { factory.card(at: $0) }
        return Session(number: number, cards: cards, scanPercentAtStart: number == 1 ? 38 : nil)
    }
}

// MARK: - Factory

private struct Factory {
    private static let photoImages = [
        "photo-sunset", "photo-beach", "photo-desert", "photo-hills", "photo-dusk",
        "photo-coast", "photo-pink", "photo-night", "photo-room", "photo-cafe",
    ]
    private static let screenshotImages = ["shot-light", "shot-dark", "shot-cream", "shot-sand", "shot-lavender"]
    private static let locations = ["Santa Monica", "Los Angeles", "Joshua Tree", "Ojai", "Malibu", "Pasadena", "Big Sur", "Home"]

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
        case 7: .video(video(bytes: 1_228_000_000, duration: 252, image: "video-waves", location: "Malibu"))
        case 24: .video(video(bytes: 846_000_000, duration: 167, image: "video-party", location: "Home"))
        case 12: .similar(similar(cardIndex: index, image: "similar-a", reason: "Sharpest, eyes open."))
        case 31: .similar(similar(cardIndex: index, image: "similar-b", reason: "Best light, nobody blinking."))
        case 14: .batch(screenshots(cardIndex: index))
        case 36: .batch(forwarded(cardIndex: index))
        default: .photo(photo())
        }
    }

    // MARK: Card kinds

    private mutating func photo() -> LibraryItem {
        let roll = rng.unit()
        let flags: [LibraryItem.Flag] = roll < 0.14 ? [.blurry] : roll < 0.24 ? [.accidental] : roll < 0.29 ? [.receipt] : []
        let image = switch flags.first {
        case .accidental: "photo-pocket"
        case .receipt: "photo-receipt"
        default: Self.photoImages[Int(rng.unit() * Double(Self.photoImages.count))]
        }
        // Favorites only appear when the user hasn't asked to skip them.
        let isFavorite = !options.skipFavorites && flags.isEmpty && rng.unit() < 0.15
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

    private mutating func forwarded(cardIndex: Int) -> ItemBatch {
        let items = (0..<9).map { k in
            LibraryItem(
                id: nextID(), kind: .photo, date: nextDate(), location: "WhatsApp",
                bytes: megabytes(0.4 + rng.unit() * 0.6), flags: [.forwarded], image: .bundled("fwd-\(k % 4 + 1)")
            )
        }
        return ItemBatch(id: cardID(cardIndex), kind: .forwarded, label: "Saved & forwarded", title: "9 forwarded images", items: items)
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
