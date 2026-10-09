import CoreLocation
import Foundation
import Photos

/// Builds sessions from the real library, newest first.
///
/// Phase 1 cards are single photos, videos, and weekly screenshot batches. Similar shots and
/// blur/accidental flags need on-device ML and come later. Items in `FeedOptions.excluding`,
/// such as ones already decided, are skipped.
actor PhotoKitFeedBuilder: FeedBuilding {
    static let photosPerSession = 20
    /// Fewer screenshots than this in a week show up as ordinary photo cards.
    static let minBatch = 3
    static let maxBatch = 40

    private let places = PlaceNamer()

    private enum Slot {
        case single(PHAsset)
        case screenshots(week: Date)
    }

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        let (slots, weeks) = pickSlots(options)
        let assets = slots.flatMap { slot -> [PHAsset] in
            switch slot {
            case .single(let asset): [asset]
            case .screenshots(let week): weeks[week] ?? []
            }
        }

        let locations = Dictionary(
            assets.compactMap { asset in asset.location.map { (asset.localIdentifier, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let names = await places.names(for: locations, within: .milliseconds(1500))
        let item = { (asset: PHAsset) in AssetMapper.item(for: asset, location: names[asset.localIdentifier]) }

        var cards: [FeedCard] = []
        for slot in slots {
            switch slot {
            case .single(let asset):
                cards.append(Self.card(for: item(asset)))
            case .screenshots(let week):
                let shots = weeks[week] ?? []
                if shots.count < Self.minBatch {
                    cards += shots.map { Self.card(for: item($0)) }
                } else {
                    cards.append(.batch(ItemBatch(
                        id: "s\(number)-shots-\(Int(week.timeIntervalSince1970))",
                        kind: .screenshots,
                        label: "Screenshots",
                        title: "\(shots.count) screenshots from \(Self.phrase(forWeek: week))",
                        items: shots.map(item)
                    )))
                }
            }
        }
        return Session(number: number, cards: cards, scanPercentAtStart: nil)
    }

    /// Walks the library newest first until the session has enough photos. Screenshots are pulled
    /// out into one slot per calendar week, placed where that week's newest screenshot appears.
    /// The oldest week's screenshots are then gathered in full, so its bundle can push the session
    /// past `photosPerSession`.
    private func pickSlots(_ options: FeedOptions) -> ([Slot], [Date: [PHAsset]]) {
        let result = PHAsset.fetchAssets(with: PhotoKitLibrary.fetchOptions(skipFavorites: options.skipFavorites))
        let calendar = Calendar.current
        var slots: [Slot] = []
        var weeks: [Date: [PHAsset]] = [:]
        var oldestWeek: Date?
        var photoCount = 0
        var index = 0

        while index < result.count {
            let asset = result.object(at: index)
            index += 1
            guard !options.excluding.contains(asset.localIdentifier) else { continue }
            let full = photoCount >= Self.photosPerSession
            let isScreenshot = AssetMapper.isScreenshot(asset)

            guard isScreenshot else {
                if full { continue }
                slots.append(.single(asset))
                photoCount += 1
                continue
            }
            let date = asset.creationDate ?? .distantPast
            let week = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            if full {
                // Once full, only top up the week still in progress; anything older waits.
                guard let oldestWeek, week >= oldestWeek else { break }
                guard week == oldestWeek else { continue }
            }
            let shots = weeks[week, default: []]
            // Overflow waits for a later session.
            guard shots.count < Self.maxBatch else { continue }
            if shots.isEmpty {
                slots.append(.screenshots(week: week))
                oldestWeek = week
            }
            weeks[week] = shots + [asset]
            photoCount += 1
        }
        return (slots, weeks)
    }

    private static func card(for item: LibraryItem) -> FeedCard {
        item.isVideo ? .video(item) : .photo(item)
    }

    /// "this week", "last week", or "the week of Sep 22".
    private static func phrase(forWeek week: Date) -> String {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        if calendar.isDate(week, inSameDayAs: thisWeek) { return "this week" }
        if let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek),
           calendar.isDate(week, inSameDayAs: lastWeek) {
            return "last week"
        }
        return "the week of \(Format.shortDay(week))"
    }
}
