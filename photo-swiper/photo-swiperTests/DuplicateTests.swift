import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
@testable import photo_swiper

// MARK: - Hash

struct DHashTests {
    /// A smooth, lopsided pattern: no symmetry, so a wrong rotation or mirror hashes differently.
    private func pattern(_ u: Double, _ v: Double, seed: Double = 0) -> UInt8 {
        let value = 128 + 60 * sin(5.1 * u + 2.3 * v * v + seed) + 50 * cos(3.7 * v - 4.2 * u * u + 2 * seed) + 15 * u
        return UInt8(max(0, min(255, value)))
    }

    private func image(width: Int, height: Int, seed: Double = 0) -> GrayscaleImage {
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels.append(pattern((Double(x) + 0.5) / Double(width), (Double(y) + 0.5) / Double(height), seed: seed))
            }
        }
        return GrayscaleImage(width: width, height: height, pixels: pixels)
    }

    private func cgImage(_ gray: GrayscaleImage) -> CGImage {
        let context = CGContext(data: nil, width: gray.width, height: gray.height, bitsPerComponent: 8, bytesPerRow: gray.width,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        gray.pixels.withUnsafeBytes { source in
            context.data!.copyMemory(from: source.baseAddress!, byteCount: gray.pixels.count)
        }
        return context.makeImage()!
    }

    /// The image as a camera would store it for `orientation`, given how it looks upright.
    /// Straight from the EXIF definitions: where stored row 0 and column 0 end up.
    private func stored(_ upright: GrayscaleImage, as orientation: CGImagePropertyOrientation) -> GrayscaleImage {
        let W = upright.width, H = upright.height
        let swapped = [.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
        let w = swapped ? H : W, h = swapped ? W : H
        var pixels = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let (ox, oy): (Int, Int) = switch orientation {
                case .up: (x, y)
                case .upMirrored: (w - 1 - x, y)
                case .down: (w - 1 - x, h - 1 - y)
                case .downMirrored: (x, h - 1 - y)
                case .leftMirrored: (y, x)
                case .right: (h - 1 - y, x)
                case .rightMirrored: (h - 1 - y, w - 1 - x)
                case .left: (y, w - 1 - x)
                @unknown default: (x, y)
                }
                pixels[y * w + x] = upright.pixels[oy * W + ox]
            }
        }
        return GrayscaleImage(width: w, height: h, pixels: pixels)
    }

    @Test(arguments: [CGImagePropertyOrientation.up, .upMirrored, .down, .downMirrored, .left, .leftMirrored, .right, .rightMirrored])
    func everyOrientationHashesAsItLooksUpright(_ orientation: CGImagePropertyOrientation) {
        let upright = image(width: 90, height: 60)
        #expect(DHash.hash(stored(upright, as: orientation), orientation: orientation) == DHash.hash(upright))
    }

    @Test func aPortraitShotStoredSidewaysMatchesOneWithTheRotationBakedIn() {
        // Left half dark, right half bright, upright. Stored for `.right` (turned a quarter turn
        // counterclockwise), the dark half is at the bottom.
        let W = 40, H = 60
        let upright = GrayscaleImage(width: W, height: H, pixels: (0..<(W * H)).map { $0 % W < W / 2 ? 20 : 230 })
        let sideways = GrayscaleImage(width: H, height: W, pixels: (0..<(W * H)).map { $0 / H < W / 2 ? 230 : 20 })
        #expect(DHash.hash(sideways, orientation: .right) == DHash.hash(upright))
        #expect(DHash.hash(sideways, orientation: .up) != DHash.hash(upright))
    }

    @Test func aResizedCopyHashesWithinAFewBits() throws {
        let a = try #require(DHash.compute(cgImage(image(width: 1200, height: 800)), orientation: .up))
        let b = try #require(DHash.compute(cgImage(image(width: 300, height: 200)), orientation: .up))
        #expect(DHash.distance(a, b) <= DuplicateGrouper.Tunables().maxHamming)
    }

    @Test func differentPhotosAreFarApart() {
        let a = DHash.hash(image(width: 120, height: 80))
        let b = DHash.hash(image(width: 120, height: 80, seed: 2.5))
        #expect(DHash.distance(a, b) > 10)
    }
}

// MARK: - Grouping

struct DuplicateGrouperTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let grouper = DuplicateGrouper()
    private static let day: TimeInterval = 86_400

    private func photo(
        _ id: String, at seconds: TimeInterval = 0, hash: UInt64? = 0xA5A5_0F0F_3C3C_9999, size: (Int, Int)? = (4032, 3024),
        favorite: Bool = false, video: Bool = false, screenshot: Bool = false, utility: Bool? = false
    ) -> RankCandidate {
        RankCandidate(id: id, features: AssetFeatures(
            createdAt: base.addingTimeInterval(seconds), bytes: 3_000_000, isVideo: video, isScreenshot: screenshot,
            isFavorite: favorite, isUtility: utility, pixelWidth: size?.0, pixelHeight: size?.1, dHash: hash
        ))
    }

    private func point(_ x: Float, _ y: Float = 0) -> FeaturePrint {
        FeaturePrint(vector: [x, y])
    }

    private func samePrint(_ shots: [RankCandidate]) -> [String: FeaturePrint] {
        Dictionary(uniqueKeysWithValues: shots.map { ($0.id, point(0)) })
    }

    private func groups(_ shots: [RankCandidate], _ prints: [String: FeaturePrint]) -> [[String]] {
        grouper.group(shots, prints: prints).map(\.ids)
    }

    @Test func copiesSavedYearsApartGroup() {
        let shots = [photo("new", at: 3 * 365 * Self.day), photo("old"), photo("other", hash: 0x1234_5678_9ABC_DEF0)]
        #expect(groups(shots, samePrint(shots)) == [["old", "new"]], "Oldest first, whatever the gap")
    }

    @Test func aResizedRecompressedCopyGroups() {
        let original = photo("original", hash: 0xFFFF_0000_FFFF_0000, size: (4032, 3024))
        let resent = photo("resent", at: 40 * Self.day, hash: 0xFFFF_0000_FFFF_0007, size: (1600, 1200))
        #expect(groups([original, resent], ["original": point(0), "resent": point(0.06)]) == [["original", "resent"]])
    }

    @Test func fourBitsApartIsTooFar() {
        let shots = [photo("a", hash: 0xFFFF_0000_FFFF_0000), photo("b", hash: 0xFFFF_0000_FFFF_000F)]
        #expect(grouper.candidateIDs(shots).isEmpty)
        #expect(groups(shots, samePrint(shots)).isEmpty)
    }

    @Test func aHashCollisionThatLooksDifferentIsRejected() {
        let shots = [photo("a"), photo("b")]
        #expect(grouper.candidateIDs(shots) == ["a", "b"], "Same hash and shape, so prints are loaded")
        #expect(groups(shots, ["a": point(0), "b": point(0.3)]).isEmpty, "A similar shot, not a copy")
    }

    @Test func aDifferentShapeIsRejected() {
        let shots = [photo("wide", size: (4032, 3024)), photo("square", size: (3024, 3024)), photo("cropped", size: (4032, 2900))]
        #expect(grouper.candidateIDs(shots).isEmpty)
        #expect(groups(shots, samePrint(shots)).isEmpty)
    }

    @Test func onlyEligiblePhotosWithHashesAndSizesAndPrintsGroup() {
        let shots = [
            photo("photo"), photo("video", video: true), photo("screenshot", screenshot: true), photo("receipt", utility: true),
            photo("unhashed", hash: nil), photo("unsized", size: nil), photo("unprinted"), photo("copy"),
        ]
        var prints = samePrint(shots)
        prints["unprinted"] = nil
        #expect(groups(shots, prints) == [["copy", "photo"]])
        #expect(grouper.candidateIDs(shots) == ["photo", "unprinted", "copy"])
    }

    @Test func unknownUtilityStillGroups() {
        let shots = [photo("a", utility: nil), photo("b", utility: nil)]
        #expect(groups(shots, samePrint(shots)) == [["a", "b"]])
    }

    @Test func copiesOfCopiesJoinOneGroup() {
        // a and c differ by 4 bits, too many on their own, but each is a copy of b.
        let shots = [photo("a", hash: 0x00), photo("b", at: 1, hash: 0x03), photo("c", at: 2, hash: 0x0F)]
        #expect(groups(shots, samePrint(shots)) == [["a", "b", "c"]])
    }

    @Test func aLargeSetSplitsIntoEvenRuns() {
        let shots = (0..<12).map { photo("c\($0)", at: Double($0) * Self.day) }
        #expect(groups(shots, samePrint(shots)).map(\.count) == [6, 6])
    }

    @Test func aCrowdedHashBandIsSkipped() {
        var tight = DuplicateGrouper()
        tight.tunables.maxBucket = 2
        let shots = [photo("a"), photo("b"), photo("c")]
        #expect(tight.candidateIDs(shots).isEmpty, "Every band holds all three")
        #expect(tight.candidateIDs(Array(shots.prefix(2))) == ["a", "b"])
    }

    @Test func inputOrderDoesNotMatter() {
        let shots = [photo("x", hash: 1), photo("y", at: 5, hash: 1), photo("p", at: 9, hash: 0xFF00_FF00), photo("q", at: 2, hash: 0xFF00_FF00)]
        let prints = samePrint(shots)
        #expect(groups(shots.reversed(), prints) == groups(shots, prints))
        #expect(Set(groups(shots, prints).map { Set($0) }) == [["x", "y"], ["q", "p"]])
    }

    @Test func twentyThousandPhotosFindPairsQuickly() {
        var generator = SystemRandomNumberGenerator()
        var shots = (0..<20_000).map { photo("p\($0)", at: Double($0) * 60, hash: UInt64.random(in: .min ... .max, using: &generator)) }
        // Five photos saved twice, with one bit flipped.
        for k in 0..<5 {
            let original = shots[k * 1_000]
            shots.append(photo("copy\(k)", at: 9e7, hash: original.features.dHash! ^ 1))
        }
        let clock = ContinuousClock()
        var ids: Set<LibraryItem.ID> = []
        let elapsed = clock.measure { ids = grouper.candidateIDs(shots) }
        #expect(ids.isSuperset(of: (0..<5).map { "copy\($0)" }))
        #expect(ids.count < 50, "Random hashes almost never come within 3 bits")
        #expect(elapsed < .seconds(2), "Took \(elapsed)")
    }
}

// MARK: - Keeper

struct DuplicatePickTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func copy(_ id: String, at days: Double, size: (Int, Int)?, favorite: Bool = false) -> RankCandidate {
        RankCandidate(id: id, features: AssetFeatures(
            createdAt: base.addingTimeInterval(days * 86_400), bytes: 1, isFavorite: favorite,
            pixelWidth: size?.0, pixelHeight: size?.1, dHash: 1
        ))
    }

    @Test func aFavoriteIsAlwaysKept() {
        let choice = DuplicatePick.choose([copy("big", at: 0, size: (4032, 3024)), copy("fav", at: 9, size: (800, 600), favorite: true)])
        #expect(choice == DuplicatePick.Choice(keepID: "fav", reason: .favorite))
    }

    @Test func thenTheHighestResolution() {
        let choice = DuplicatePick.choose([copy("small", at: 0, size: (1600, 1200)), copy("big", at: 9, size: (4032, 3024))])
        #expect(choice == DuplicatePick.Choice(keepID: "big", reason: .resolution))
    }

    @Test func thenTheEarliest() {
        let choice = DuplicatePick.choose([copy("later", at: 9, size: (4032, 3024)), copy("first", at: 0, size: (4032, 3024)), copy("small", at: -5, size: (100, 75))])
        #expect(choice == DuplicatePick.Choice(keepID: "first", reason: .earliest))
    }

    @Test func twoFavoritesMeanNoSuggestion() {
        #expect(DuplicatePick.choose([copy("a", at: 0, size: nil, favorite: true), copy("b", at: 1, size: nil, favorite: true)]) == nil)
        #expect(DuplicatePick.choose([copy("a", at: 0, size: nil)]) == nil)
    }
}

// MARK: - Never in both

struct DuplicateExclusivityTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func shot(_ id: String, at seconds: TimeInterval, hash: UInt64, bytes: Int64 = 3_000_000) -> RankCandidate {
        RankCandidate(id: id, features: AssetFeatures(
            createdAt: base.addingTimeInterval(seconds), bytes: bytes, isUtility: false, pixelWidth: 4032, pixelHeight: 3024, dHash: hash
        ))
    }

    /// A photo saved twice seconds apart, plus a similar but different shot right after.
    private var shots: [RankCandidate] {
        [shot("copyA", at: 0, hash: 0xAAAA_AAAA), shot("copyB", at: 5, hash: 0xAAAA_AAAA), shot("similar", at: 10, hash: 0x5555_5555)]
    }
    private let prints = ["copyA": FeaturePrint(vector: [0, 0]), "copyB": FeaturePrint(vector: [0.01, 0]), "similar": FeaturePrint(vector: [0.3, 0])]

    @Test func duplicatesAreTakenBeforeSimilarGrouping() {
        #expect(SimilarGrouper().group(shots, prints: prints).groups.map(\.ids) == [["copyA", "copyB", "similar"]],
                "On their own, all three would be similar shots")

        let duplicates = PhotoKitFeedBuilder.duplicatePlans(shots, prints: prints)
        #expect(duplicates.map(\.ids) == [["copyA", "copyB"]])
        #expect(duplicates.first?.reason == DuplicatePick.Reason.earliest.rawValue)

        let rest = PhotoKitFeedBuilder.similarCandidates(shots, excluding: duplicates)
        #expect(rest.map(\.id) == ["similar"])
        #expect(SimilarGrouper().group(rest, prints: prints).groups.isEmpty)
    }

    @Test func duplicatePhotosNeverShowAsSinglesEvenWhenTheirSetWaits() {
        let planner = SessionPlanner(limit: 3, minBatch: 3, maxBatch: 40)
        let duplicates = PhotoKitFeedBuilder.duplicatePlans(shots, prints: prints)

        let plan = planner.plan(shots, duplicates: duplicates, now: base)
        #expect(plan.contains(.duplicates(ids: ["copyA", "copyB"], keepID: "copyA", reason: "Saved first")))
        #expect(!plan.contains(.single("copyA")) && !plan.contains(.single("copyB")))

        // Room for one item: the set waits, and its photos don't fill in as singles.
        let tight = SessionPlanner(limit: 1, minBatch: 3, maxBatch: 40).plan(shots, duplicates: duplicates, now: base)
        #expect(tight == [.single("similar")])
    }

    @Test func aDuplicateSetOutranksTheSameBytesAsASimilarSet() {
        let planner = SessionPlanner(limit: 4, minBatch: 3, maxBatch: 40)
        let copies = [shot("d1", at: 0, hash: 1), shot("d2", at: 1, hash: 1)]
        let burst = [shot("s1", at: 100, hash: 2), shot("s2", at: 101, hash: 3)]
        let plan = planner.plan(
            copies + burst,
            groups: [PlannedGroup(ids: ["s1", "s2"], bestID: "s1", reason: "Sharpest of the set")],
            duplicates: [PlannedGroup(ids: ["d1", "d2"], bestID: "d1", reason: "Saved first")],
            now: base
        )
        #expect(plan.first == .duplicates(ids: ["d1", "d2"], keepID: "d1", reason: "Saved first"))
    }

    @Test func duplicateCardIDsDependOnlyOnTheMembers() {
        let id = PhotoKitFeedBuilder.duplicateID(["B/L0/001", "A/L0/001"])
        #expect(id == PhotoKitFeedBuilder.duplicateID(["A/L0/001", "B/L0/001"]))
        #expect(id.hasPrefix("dup-") && id.count == "dup-".count + 16)
        #expect(id != PhotoKitFeedBuilder.similarID(["A/L0/001", "B/L0/001"]))
    }
}

// MARK: - Saved decks

@MainActor
struct DuplicateDeckCodingTests {
    /// A deck saved before duplicates existed, as the synthesized encoder wrote it: no duplicates
    /// case, and features without pixel sizes or hashes.
    private static let oldDeck = """
    {"number":4,"scanPercentAtStart":40,"cards":[
      {"photo":{"_0":{"id":"p1","kind":{"photo":{}},"date":700000000,"location":"Ojai","bytes":3000000,"flags":["blurry"],
        "isFavorite":false,"image":{"photoKit":{"localIdentifier":"p1"}},
        "features":{"createdAt":700000000,"bytes":3000000,"isVideo":false,"duration":0,"isScreenshot":false,"isFavorite":false,
          "isInBurst":false,"isBurstPick":false,"hasAdjustments":false,"sharpness":40,"aesthetic":0.1,"isUtility":false}}}},
      {"similar":{"_0":{"id":"similar-1","bestID":"s1","reason":"Sharpest of the set","items":[
        {"id":"s1","kind":{"photo":{}},"date":700000100,"bytes":2000000,"flags":[],"isFavorite":false,"image":{"bundled":{"_0":"similar-a-1"}}},
        {"id":"s2","kind":{"photo":{}},"date":700000101,"bytes":2000000,"flags":[],"isFavorite":false,"image":{"bundled":{"_0":"similar-a-2"}}}
      ]}}},
      {"video":{"_0":{"id":"v1","kind":{"video":{"duration":12}},"date":700000200,"bytes":9000000,"flags":[],"isFavorite":false,
        "image":{"photoKit":{"localIdentifier":"v1"}}}}}
    ]}
    """

    @Test func aDeckSavedBeforeDuplicatesStillLoads() throws {
        let container = try SwiftDataProgressStore.makeContainer(inMemory: true)
        let context = container.mainContext
        context.insert(SessionProgress(number: 4, index: 1, finished: false, startedAt: .now,
                                       snapshot: Data(Self.oldDeck.utf8), marks: Data("{}".utf8)))
        try context.save()

        let saved = try #require(SwiftDataProgressStore(container: container, defaults: nil).loadSession())
        #expect(saved.index == 1)
        #expect(saved.session.cards.map(\.id) == ["item-p1", "similar-1", "item-v1"])
        let photo = try #require(saved.session.cards.first?.items.first)
        #expect(photo.features?.sharpness == 40)
        #expect(photo.features?.dHash == nil && photo.features?.pixelWidth == nil)
    }

    @Test func aDeckWithDuplicatesRoundTrips() throws {
        let store = try SwiftDataProgressStore.inMemory()
        let session = MockFeedBuilder().makeSessionNow(number: 1)
        #expect(session.cards.contains { if case .duplicates = $0 { true } else { false } })
        let saved = SavedSession(session: session, index: 13, marks: [:], finished: false)
        store.saveSession(saved)
        #expect(store.loadSession() == saved)
    }
}

// MARK: - Feed

@MainActor
struct DuplicatesCardTests {
    private func duplicatesCard(_ vm: FeedViewModel) throws -> DuplicateGroup {
        guard case .duplicates(let group) = try #require(vm.currentCard) else {
            Issue.record("Expected a duplicates card on top")
            throw CancellationError()
        }
        try #require(group.others.count >= 2)
        return group
    }

    private func lockedMock(swipes: Int) -> FeedViewModel {
        FeedViewModel.mock(
            startingAt: .duplicates,
            entitlements: TestEntitlements(isUnlocked: false),
            allowance: SwipeAllowance(balance: swipes, tunables: .standard, now: .now)
        )
    }

    @Test func theMockDeckHasACardOfCopies() throws {
        let group = try duplicatesCard(FeedViewModel.mock(startingAt: .duplicates))
        #expect(group.items.first?.id == group.keepID, "The keeper comes first")
        #expect(Set(group.items.map(\.image)).count == 1, "Every copy is the same image")
        #expect(PreviewSamples.duplicateGroup.id == group.id)
    }

    @Test func swipingLeftKeepsOneAndClearsTheRestForOneSwipe() throws {
        let vm = lockedMock(swipes: 5)
        let start = vm.index
        let group = try duplicatesCard(vm)
        #expect(vm.swipeLabel(.left, for: .duplicates(group)) == "Clear \(group.others.count)")
        #expect(vm.bytesToClear(for: .duplicates(group)) == group.others.reduce(0) { $0 + $1.bytes })

        vm.decideCurrent(.left)

        #expect(vm.index == start + 1)
        #expect(vm.swipesLeft == 4, "One decision, one swipe")
        #expect(vm.decisions[group.keepID] == .keep)
        #expect(Set(vm.pendingItems.map(\.id)) == Set(group.others.map(\.id)))
    }

    @Test func swipingRightKeepsEveryCopy() throws {
        let vm = FeedViewModel.mock(startingAt: .duplicates)
        let group = try duplicatesCard(vm)
        #expect(vm.swipeLabel(.right, for: .duplicates(group)) == "Keep all \(group.items.count)")

        vm.decideCurrent(.right)

        #expect(group.items.allSatisfy { vm.decisions[$0.id] == .keep })
        #expect(vm.pendingItems.isEmpty)
    }

    @Test func theReviewSetOpensOnTheTappedCopyWithTheKeeperFirst() throws {
        let group = try duplicatesCard(FeedViewModel.mock(startingAt: .duplicates))
        let tapped = group.others[1]

        let set = try #require(ReviewSet(card: .duplicates(group), startingAt: tapped.id))

        #expect(set.id == group.id)
        #expect(set.title == "Duplicates")
        #expect(set.items.map(\.id) == [group.keepID] + group.others.map(\.id))
        #expect(set.items[set.start].id == tapped.id)
        #expect(set.bestID == group.keepID)
        #expect(set.reason == group.reason)
        #expect(ReviewSet(card: .duplicates(group))?.start == 0, "Opens on the keeper by default")
    }

    @Test func aFinishedReviewCostsOneSwipeAndUnreachedCopiesAreCleared() throws {
        let vm = lockedMock(swipes: 5)
        let group = try duplicatesCard(vm)
        let reached = group.others[0], unreached = group.others[1]

        vm.saveDraft([group.keepID: .keep], for: group.id)
        #expect(vm.swipesLeft == 5, "Drafts cost nothing")

        vm.decideCurrentIndividually([group.keepID: .keep, reached.id: .keep])

        #expect(vm.swipesLeft == 4)
        #expect(vm.decisions[reached.id] == .keep)
        #expect(vm.decisions[unreached.id] == .delete, "Copies the review didn't reach are still cleared")
        #expect(vm.draft(for: group.id).isEmpty)
    }

    @Test func theCardFaceFollowsADraft() throws {
        let vm = FeedViewModel.mock(startingAt: .duplicates)
        let group = try duplicatesCard(vm)

        vm.saveDraft([group.others[0].id: .keep], for: group.id)

        #expect(vm.markedForClearing(in: group) == Set(group.others.dropFirst().map(\.id)))
        #expect(vm.swipeLabel(.left, for: .duplicates(group)) == "Clear \(group.others.count - 1)")
    }

    @Test func undoBringsTheCardBack() throws {
        let vm = FeedViewModel.mock(startingAt: .duplicates)
        let start = vm.index
        let group = try duplicatesCard(vm)

        vm.decideCurrent(.left)
        vm.undo()

        #expect(vm.index == start)
        #expect(group.items.allSatisfy { vm.decisions[$0.id] == nil })
        #expect(vm.pendingItems.isEmpty)
    }
}
