import CoreLocation
import Foundation
import Testing
@testable import photo_swiper

/// Whole page builds through `PhotoKitFeedBuilder`, on a fake library, index, and geocoder (JUN-45, Q-4).
struct FeedBuilderTests {
    /// A library whose items are `candidates`, with `deleted` gone from it since the index saw them.
    private struct FakeCatalog: AssetCatalog {
        let candidates: [RankCandidate]
        var deleted: Set<LibraryItem.ID> = []
        /// Indexed items are read live only when `index` lacks them; these have their own metadata.
        var liveFeatures: [LibraryItem.ID: AssetFeatures] = [:]

        func entries(skipFavorites: Bool) -> [CandidatePool.Entry] {
            candidates
                .filter { !deleted.contains($0.id) && !(skipFavorites && $0.features.isFavorite) }
                .sorted { $0.features.createdAt > $1.features.createdAt }
                .map { CandidatePool.Entry(id: $0.id, modifiedAt: nil, isFavorite: $0.features.isFavorite) }
        }

        func features(for ids: [LibraryItem.ID]) -> [LibraryItem.ID: AssetFeatures] {
            let all = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0.features) }).merging(liveFeatures) { _, live in live }
            return Dictionary(uniqueKeysWithValues: ids.compactMap { id in deleted.contains(id) ? nil : all[id].map { (id, $0) } })
        }

        func locations(for ids: [LibraryItem.ID]) -> [LibraryItem.ID: CLLocation?] {
            let present = Set(candidates.map(\.id)).subtracting(deleted)
            return Dictionary(uniqueKeysWithValues: ids.filter(present.contains).map { ($0, CLLocation(latitude: 34.01, longitude: -118.49)) })
        }
    }

    private actor FakeIndex: FeatureIndexReading {
        let library: SyntheticLibrary
        let records: [LibraryItem.ID: IndexedFeatures]
        var generation = 1
        private(set) var printsRead = 0

        init(_ library: SyntheticLibrary, leavingOut unindexed: Set<LibraryItem.ID> = []) {
            self.library = library
            records = Dictionary(uniqueKeysWithValues: library.candidates.filter { !unindexed.contains($0.id) }.map {
                ($0.id, IndexedFeatures(features: $0.features, stamp: IndexStamp(modifiedAt: nil, version: IndexFreshness.currentVersion)))
            })
        }

        func indexed() -> [LibraryItem.ID: IndexedFeatures] { records }

        func featurePrints(for ids: [LibraryItem.ID]) -> [LibraryItem.ID: FeaturePrint] {
            printsRead += ids.count
            return library.prints(for: ids.filter { records[$0] != nil })
        }

        func bump() { generation += 1 }
    }

    private struct FakeGeocoder: Geocoding {
        func placeName(for location: CLLocation, timeout: Duration) async -> String? { "Santa Monica" }
    }

    private let library = SyntheticLibrary(count: 1_500, seed: 21, dimensions: 32)

    private func builder(_ index: FakeIndex?, catalog: FakeCatalog? = nil) -> PhotoKitFeedBuilder {
        PhotoKitFeedBuilder(index: index, catalog: catalog ?? FakeCatalog(candidates: library.candidates), geocoder: FakeGeocoder())
    }

    private func options(excluding: Set<LibraryItem.ID> = []) -> FeedOptions {
        FeedOptions(skipFavorites: true, excluding: excluding, placeBudget: .seconds(1))
    }

    private func ids(_ session: Session) -> [LibraryItem.ID] { session.cards.flatMap(\.items).map(\.id) }

    @Test func noItemIsOnTwoCardsAndGroupedPhotosAreNeverSingles() async {
        let builder = builder(FakeIndex(library))
        var excluded: Set<LibraryItem.ID> = []
        var grouped: Set<LibraryItem.ID> = [], singles: Set<LibraryItem.ID> = []
        var kinds: Set<String> = []
        // Page through the whole library. Near the end, pages hold a single similar set each, since
        // similar cards are never dealt side by side.
        for page in 1...1_000 {
            let session = await builder.makeSession(number: page, options: options(excluding: excluded))
            if session.cards.isEmpty { break }
            let all = ids(session)
            #expect(Set(all).count == all.count, "page \(page) has an item twice")
            #expect(session.items.allSatisfy { $0.location == "Santa Monica" })
            for card in session.cards {
                switch card {
                case .similar, .duplicates:
                    grouped.formUnion(card.items.map(\.id))
                    kinds.insert(card.id.hasPrefix("dup-") ? "duplicates" : "similar")
                case .photo(let item), .video(let item):
                    singles.insert(item.id)
                case .batch:
                    break
                }
            }
            excluded.formUnion(all)
        }
        #expect(kinds == ["similar", "duplicates"])
        #expect(grouped.isDisjoint(with: singles))
        #expect(excluded.count == library.candidates.filter { !$0.features.isFavorite }.count, "Every item is dealt once")
    }

    @Test func excludedItemsNeverAppear() async {
        let first = await builder(FakeIndex(library)).makeSession(number: 1, options: options())
        let excluded = Set(ids(first))
        let second = await builder(FakeIndex(library)).makeSession(number: 2, options: options(excluding: excluded))
        #expect(!second.cards.isEmpty)
        #expect(excluded.isDisjoint(with: ids(second)))
    }

    @Test func itemsDeletedFromTheLibraryAreLeftOut() async {
        let first = await builder(FakeIndex(library)).makeSession(number: 1, options: options())
        let gone = Set(ids(first).prefix(5))
        let catalog = FakeCatalog(candidates: library.candidates, deleted: gone)
        let again = await builder(FakeIndex(library), catalog: catalog).makeSession(number: 1, options: options())
        #expect(gone.isDisjoint(with: ids(again)))
    }

    @Test func groupIDsAreTheSameEverySession() async {
        let one = await builder(FakeIndex(library)).makeSession(number: 1, options: options())
        let two = await builder(FakeIndex(library)).makeSession(number: 7, options: options())
        let groups = one.cards.filter { if case .photo = $0 { false } else if case .video = $0 { false } else { true } }
        #expect(!groups.isEmpty)
        for card in groups {
            switch card {
            case .similar(let group):
                #expect(group.id == PhotoKitFeedBuilder.similarID(group.items.map(\.id)))
            case .duplicates(let group):
                #expect(group.id == PhotoKitFeedBuilder.duplicateID(group.items.map(\.id)))
            default:
                break
            }
        }
        let similarAndDuplicates = { (session: Session) in
            session.cards.compactMap { card -> String? in
                switch card {
                case .similar, .duplicates: card.id
                default: nil
                }
            }
        }
        #expect(similarAndDuplicates(one) == similarAndDuplicates(two))
    }

    @Test func screenshotsBatchByWeekWithinTheLimits() async {
        let monday = Calendar.current.dateInterval(of: .weekOfYear, for: Date(timeIntervalSince1970: 1_800_000_000))!.start
        func screenshot(_ n: Int, week: Int) -> RankCandidate {
            RankCandidate(id: "shot-\(week)-\(n)", features: AssetFeatures(
                createdAt: monday.addingTimeInterval(Double(week) * 7 * 86_400 + 3_600 + Double(n) * 60), bytes: 500_000,
                isScreenshot: true, isUtility: true, pixelWidth: 1179, pixelHeight: 2556
            ))
        }
        // Five in one week, two in another: everything fits in one page.
        let shots = (0..<5).map { screenshot($0, week: 0) } + (0..<2).map { screenshot($0, week: 2) }
        let session = await PhotoKitFeedBuilder(index: nil, catalog: FakeCatalog(candidates: shots), geocoder: FakeGeocoder())
            .makeSession(number: 1, options: options())

        #expect(Set(ids(session)) == Set(shots.map(\.id)))
        let batches = session.cards.compactMap { card -> ItemBatch? in if case .batch(let batch) = card { batch } else { nil } }
        #expect(batches.map { Set($0.items.map(\.id)) } == [Set((0..<5).map { "shot-0-\($0)" })])
        let fewWeek = session.cards.filter { $0.items.contains { $0.id.hasPrefix("shot-2-") } }
        #expect(fewWeek.count == 2 && fewWeek.allSatisfy { if case .photo = $0 { true } else { false } },
                "A week under minBatch shows ordinary cards")

        // A big week fills at most a page's worth, never past maxBatch, and the rest waits.
        let many = (0..<60).map { screenshot($0, week: 0) }
        let big = PhotoKitFeedBuilder(index: nil, catalog: FakeCatalog(candidates: many), geocoder: FakeGeocoder())
        let first = await big.makeSession(number: 1, options: options())
        let second = await big.makeSession(number: 2, options: options(excluding: Set(ids(first))))
        for card in first.cards + second.cards {
            guard case .batch(let batch) = card else { continue }
            #expect(batch.items.count >= PhotoKitFeedBuilder.minBatch && batch.items.count <= PhotoKitFeedBuilder.maxBatch)
        }
        #expect(ids(first).count == PhotoKitFeedBuilder.photosPerSession)
        #expect(Set(ids(first)).isDisjoint(with: ids(second)))
        #expect(!second.cards.isEmpty)
    }

    @Test func unindexedItemsAreReadLiveAndNeverGrouped() async {
        let unindexed = Set(library.candidates.prefix(200).map(\.id))
        let session = await builder(FakeIndex(library, leavingOut: unindexed)).makeSession(number: 1, options: options())
        let grouped = session.cards.flatMap { card -> [LibraryItem.ID] in
            switch card {
            case .similar, .duplicates: card.items.map(\.id)
            default: []
            }
        }
        #expect(unindexed.isDisjoint(with: grouped))
    }

    /// Page after page, a builder that kept its grouping work deals exactly what a new one does.
    @Test func aWarmBuilderDealsTheSameCardsAsAColdOne() async {
        let index = FakeIndex(library)
        let warm = builder(index)
        var excluded: Set<LibraryItem.ID> = []
        for page in 1...4 {
            let fromWarm = await warm.makeSession(number: page, options: options(excluding: excluded))
            let fromCold = await builder(FakeIndex(library)).makeSession(number: page, options: options(excluding: excluded))
            #expect(fromWarm.cards == fromCold.cards, "page \(page)")
            excluded.formUnion(ids(fromWarm))
        }
        let printsBefore = await index.printsRead
        await index.bump()
        let afterChange = await warm.makeSession(number: 5, options: options(excluding: excluded))
        let fromCold = await builder(FakeIndex(library)).makeSession(number: 5, options: options(excluding: excluded))
        #expect(afterChange.cards == fromCold.cards)
        #expect(await index.printsRead > printsBefore, "A new index generation reads prints again")
    }
}
