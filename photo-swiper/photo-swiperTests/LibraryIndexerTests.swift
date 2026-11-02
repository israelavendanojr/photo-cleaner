import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import photo_swiper

/// A library the test controls. Records which items it was asked for pixels for.
private final class FakeAssetSource: IndexAssetSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _assets: [IndexableAsset] = []
    private var _imageRequests: [LibraryItem.ID] = []
    /// Items with no local image, as if only in iCloud.
    var cloudOnly: Set<LibraryItem.ID> = []

    var assets: [IndexableAsset] {
        get { lock.withLock { _assets } }
        set { lock.withLock { _assets = newValue } }
    }
    var imageRequests: [LibraryItem.ID] { lock.withLock { _imageRequests } }

    func currentAssets() async -> [IndexableAsset] { assets.shuffled() }

    func metadata(for ids: [LibraryItem.ID]) async -> [LibraryItem.ID: AssetFeatures] {
        let present = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Dictionary(uniqueKeysWithValues: ids.compactMap { id in
            present[id].map { (id, AssetFeatures(createdAt: $0.createdAt, bytes: 1_000_000, isVideo: $0.kind == .video, isScreenshot: $0.kind == .screenshot,
                                                 pixelWidth: 4032, pixelHeight: 3024)) }
        })
    }

    func image(for id: LibraryItem.ID) async -> AnalysisImage? {
        lock.withLock { _imageRequests.append(id) }
        guard !cloudOnly.contains(id) else { return nil }
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        return AnalysisImage(cgImage: context.makeImage()!, orientation: .up)
    }

    func clearRequests() { lock.withLock { _imageRequests = [] } }
}

/// Returns fixed signals. Cancels the running task after `stopAfter` analyses, like a pause mid-batch.
private final class FakeAnalyzer: ImageAnalyzing, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var stopAfter: Int?

    func analyze(_ image: CGImage, orientation: CGImagePropertyOrientation) async -> ImageSignals {
        let shouldStop = lock.withLock {
            count += 1
            return stopAfter.map { count >= $0 } ?? false
        }
        if shouldStop { withUnsafeCurrentTask { $0?.cancel() } }
        return ImageSignals(sharpness: 300, exposure: ExposureStats(mean: 0.5, darkFraction: 0, brightFraction: 0), aesthetic: 0.1, isUtility: false,
                            dHash: 0xD0D0)
    }
}

struct LibraryIndexerTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let source = FakeAssetSource()
    private let analyzer = FakeAnalyzer()
    private let index: FeatureIndex

    init() throws {
        index = FeatureIndex(container: try SwiftDataProgressStore.makeContainer(inMemory: true))
    }

    /// `p0` is the newest.
    private func photos(_ count: Int) -> [IndexableAsset] {
        (0..<count).map { IndexableAsset(id: "p\($0)", createdAt: base.addingTimeInterval(-Double($0) * 60), modifiedAt: base, kind: .photo) }
    }

    private func indexer(version: Int = 1, batchSize: Int = 2) -> LibraryIndexer {
        LibraryIndexer(source: source, analyzer: analyzer, index: index, version: version, batchSize: batchSize, now: { [base] in base })
    }

    @Test func indexesNewestFirstAndReportsProgress() async {
        source.assets = photos(5)
        let indexer = indexer()
        await indexer.run()

        #expect(source.imageRequests == ["p0", "p1", "p2", "p3", "p4"])
        #expect(await index.count() == 5)
        #expect(await indexer.progress == IndexProgress(indexed: 5, total: 5))
        #expect(await index.indexed()["p0"]?.features.sharpness == 300)
    }

    @Test func resumesAfterAStopWithoutRedoingFinishedWork() async {
        source.assets = photos(7)
        analyzer.stopAfter = 3
        let first = indexer()
        await Task { await first.run() }.value

        // One full batch of two plus the item that was analyzed when the stop came.
        #expect(source.imageRequests == ["p0", "p1", "p2"])
        #expect(await index.count() == 3)
        #expect(await first.progress == IndexProgress(indexed: 3, total: 7))

        analyzer.stopAfter = nil
        source.clearRequests()
        let second = indexer()
        await second.run()
        #expect(source.imageRequests == ["p3", "p4", "p5", "p6"])
        #expect(await index.count() == 7)
        #expect(await second.progress.isComplete)
    }

    @Test func aFinishedIndexHasNothingToDo() async {
        source.assets = photos(3)
        await indexer().run()
        source.clearRequests()
        await indexer().run()
        #expect(source.imageRequests.isEmpty)
    }

    @Test func aVersionBumpReindexesEverything() async {
        source.assets = photos(3)
        await indexer(version: 1).run()
        source.clearRequests()

        await indexer(version: 2).run()
        #expect(source.imageRequests == ["p0", "p1", "p2"])
        #expect(await index.stamps().values.allSatisfy { $0.version == 2 })
    }

    @Test func anEditedItemIsReindexed() async {
        source.assets = photos(3)
        await indexer().run()
        source.clearRequests()

        let later = base.addingTimeInterval(3600)
        source.assets[1] = IndexableAsset(id: "p1", createdAt: source.assets[1].createdAt, modifiedAt: later, kind: .photo)
        await indexer().run()
        #expect(source.imageRequests == ["p1"])
        #expect(await index.stamps()["p1"]?.modifiedAt == later)
    }

    @Test func itemsThatLeftTheLibraryAreRemoved() async {
        source.assets = photos(4)
        let indexer = indexer()
        await indexer.run()

        // Deleted while the app was closed.
        source.assets.removeAll { $0.id == "p2" }
        await indexer.run()
        #expect(await index.stamps()["p2"] == nil)

        // Reported by the library while running.
        await indexer.remove(["p0"])
        #expect(await index.stamps().keys.sorted() == ["p1", "p3"])
    }

    @Test func screenshotsVideosAndCloudOnlyPhotosKeepMetadataWithoutImageSignals() async {
        source.assets = [
            IndexableAsset(id: "shot", createdAt: base, modifiedAt: base, kind: .screenshot),
            IndexableAsset(id: "clip", createdAt: base.addingTimeInterval(-1), modifiedAt: base, kind: .video),
            IndexableAsset(id: "cloud", createdAt: base.addingTimeInterval(-2), modifiedAt: base, kind: .photo),
        ]
        source.cloudOnly = ["cloud"]
        await indexer().run()

        #expect(source.imageRequests == ["cloud"], "Only photos ask for pixels")
        let all = await index.indexed()
        #expect(all.count == 3)
        #expect(all.values.allSatisfy { $0.features.sharpness == nil && $0.features.aesthetic == nil })
        #expect(all["shot"]?.features.isScreenshot == true)
        #expect(all["clip"]?.features.isVideo == true)
    }
}

/// Exact-duplicate hashes: from the normal pass for new photos, and a hash-only pass for records
/// indexed before hashes existed, without a version bump.
struct DuplicateHashIndexTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let source = FakeAssetSource()
    private let analyzer = FakeAnalyzer()
    private let index: FeatureIndex

    init() throws {
        index = FeatureIndex(container: try SwiftDataProgressStore.makeContainer(inMemory: true))
    }

    private func indexer() -> LibraryIndexer {
        LibraryIndexer(source: source, analyzer: analyzer, index: index, version: 1, batchSize: 2, now: { [base] in base })
    }

    private func asset(_ id: String, _ kind: IndexableAsset.Kind, minutesAgo: Double = 0) -> IndexableAsset {
        IndexableAsset(id: id, createdAt: base.addingTimeInterval(-minutesAgo * 60), modifiedAt: base, kind: kind)
    }

    /// A current record written before hashes existed: analyzed, but no pixel size or hash.
    private func oldRecord(_ asset: IndexableAsset) -> IndexEntry {
        IndexEntry(id: asset.id, features: AssetFeatures(createdAt: asset.createdAt, bytes: 1_000_000, isVideo: asset.kind == .video,
                                                         isScreenshot: asset.kind == .screenshot, sharpness: 120),
                   modifiedAt: asset.modifiedAt, version: 1, indexedAt: base)
    }

    @Test func newPhotosAreHashedInTheNormalPass() async {
        source.assets = [asset("p", .photo), asset("shot", .screenshot, minutesAgo: 1)]
        await indexer().run()

        let all = await index.indexed()
        #expect(all["p"]?.features.dHash == 0xD0D0)
        #expect(all["p"]?.features.pixelWidth == 4032 && all["p"]?.features.pixelHeight == 3024)
        #expect(all["shot"]?.features.dHash == nil)
        #expect(await index.unhashedPhotos().isEmpty)
    }

    @Test func olderRecordsGetAHashOnlyPassOnce() async {
        let photos = [asset("p0", .photo), asset("p1", .photo, minutesAgo: 1), asset("p2", .photo, minutesAgo: 2)]
        let others = [asset("shot", .screenshot, minutesAgo: 3), asset("clip", .video, minutesAgo: 4)]
        source.assets = photos + others
        await index.upsert((photos + others).map(oldRecord))
        #expect(await index.unhashedPhotos() == ["p0", "p1", "p2"])

        await indexer().run()

        #expect(source.imageRequests == ["p0", "p1", "p2"], "Newest first; screenshots and videos aren't hashed")
        let all = await index.indexed()
        for photo in photos {
            #expect(all[photo.id]?.features.dHash == 0, "A blank image hashes to zero")
            #expect(all[photo.id]?.features.pixelWidth == 4032)
            #expect(all[photo.id]?.features.sharpness == 120, "Other features stay")
            #expect(all[photo.id]?.stamp == IndexStamp(modifiedAt: base, version: 1), "Not re-analyzed")
        }
        #expect(all["shot"]?.features.pixelWidth == nil)

        source.clearRequests()
        await indexer().run()
        #expect(source.imageRequests.isEmpty)
    }

    @Test func aCloudOnlyPhotoIsTriedOnceAndLeftUnhashed() async {
        let cloud = asset("cloud", .photo)
        source.assets = [cloud]
        source.cloudOnly = ["cloud"]
        await index.upsert([oldRecord(cloud)])

        await indexer().run()
        #expect(source.imageRequests == ["cloud"])
        #expect(await index.indexed()["cloud"]?.features.dHash == nil)
        #expect(await index.indexed()["cloud"]?.features.pixelWidth == 4032, "The pixel size is metadata, so it's kept")

        source.clearRequests()
        await indexer().run()
        #expect(source.imageRequests.isEmpty)
    }

    @Test func aNewerHashVersionRehashesWithoutReanalyzing() async {
        source.assets = [asset("p", .photo)]
        await indexer().run()
        source.clearRequests()

        let rehash = LibraryIndexer(source: source, analyzer: analyzer, index: index, version: 1, hashVersion: DHash.version + 1,
                                    batchSize: 2, now: { [base] in base })
        await rehash.run()
        #expect(source.imageRequests == ["p"])
        #expect(await index.indexed()["p"]?.features.sharpness == 300)
        #expect(await index.unhashedPhotos(version: DHash.version + 1).isEmpty)
    }
}

struct IndexGateTests {
    @Test func runsOnlyInTheForegroundOnFullPowerAndWhileCool() {
        #expect(IndexGate.canRun(isForeground: true, isLowPower: false, thermal: .nominal))
        #expect(IndexGate.canRun(isForeground: true, isLowPower: false, thermal: .fair))
        #expect(!IndexGate.canRun(isForeground: false, isLowPower: false, thermal: .nominal))
        #expect(!IndexGate.canRun(isForeground: true, isLowPower: true, thermal: .nominal))
        #expect(!IndexGate.canRun(isForeground: true, isLowPower: false, thermal: .serious))
        #expect(!IndexGate.canRun(isForeground: true, isLowPower: false, thermal: .critical))
    }
}
