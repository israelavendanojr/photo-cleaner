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
            present[id].map { (id, AssetFeatures(createdAt: $0.createdAt, bytes: 1_000_000, isVideo: $0.kind == .video, isScreenshot: $0.kind == .screenshot)) }
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
        return ImageSignals(sharpness: 300, exposure: ExposureStats(mean: 0.5, darkFraction: 0, brightFraction: 0), aesthetic: 0.1, isUtility: false)
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
