import Foundation
import OSLog

/// Indexed versus total library items.
struct IndexProgress: Hashable, Sendable {
    var indexed: Int
    var total: Int

    var isComplete: Bool { indexed >= total }
    /// 0...100.
    var percent: Int { total == 0 ? 100 : min(100, indexed * 100 / total) }
}

/// Computes features for the whole library once and keeps them current.
///
/// Each `run()` diffs the library against the stored records. Its work queue is every item with no
/// record, an outdated `featureVersion`, or a changed modification date, newest first. Rebuilding
/// the queue from that diff is what makes runs resumable: cancel at any point and the next run picks
/// up where this one stopped, with no cursor to keep. Records for items that left the library are
/// removed. Work is saved in batches; photos get image analysis, screenshots and videos metadata only.
actor LibraryIndexer {
    static let batchSize = 50
    private static let log = Logger(subsystem: "com.israelavendanojr.photo-swiper", category: "index")

    private let source: any IndexAssetSource
    private let analyzer: any ImageAnalyzing
    private let index: FeatureIndex
    private let version: Int
    private let batchSize: Int
    private let now: @Sendable () -> Date

    private(set) var progress = IndexProgress(indexed: 0, total: 0)
    private var isRunning = false

    init(
        source: any IndexAssetSource,
        analyzer: any ImageAnalyzing,
        index: FeatureIndex,
        version: Int = IndexFreshness.currentVersion,
        batchSize: Int = LibraryIndexer.batchSize,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.analyzer = analyzer
        self.index = index
        self.version = version
        self.batchSize = batchSize
        self.now = now
    }

    /// Indexes until the queue is empty or the task is cancelled. A second call while one runs returns at once.
    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let assets = await source.currentAssets().sorted { a, b in
            a.createdAt != b.createdAt ? a.createdAt > b.createdAt : a.id < b.id
        }
        let stamps = await index.stamps()
        let gone = Set(stamps.keys).subtracting(assets.map(\.id))
        await index.remove(gone)

        var edited = 0, outdated = 0
        let queue = assets.filter { asset in
            guard let stamp = stamps[asset.id] else { return true }
            if IndexFreshness.isCurrent(stamp, assetModifiedAt: asset.modifiedAt, version: version) { return false }
            if stamp.version < version { outdated += 1 } else { edited += 1 }
            return true
        }
        progress = IndexProgress(indexed: assets.count - queue.count, total: assets.count)
        Self.log.info("Index run: \(queue.count) to do of \(assets.count) (\(queue.count - edited - outdated) new, \(edited) edited, \(outdated) outdated), \(gone.count) removed")

        for start in stride(from: 0, to: queue.count, by: batchSize) {
            guard !Task.isCancelled else { break }
            let batch = queue[start..<min(start + batchSize, queue.count)]
            let metadata = await source.metadata(for: batch.map(\.id))
            var entries: [IndexEntry] = []
            for asset in batch {
                guard !Task.isCancelled else { break }
                // Missing metadata means the item left the library mid-run.
                guard var features = metadata[asset.id] else { continue }
                if asset.kind == .photo, let image = await source.image(for: asset.id) {
                    features.apply(await analyzer.analyze(image.cgImage, orientation: image.orientation))
                }
                entries.append(IndexEntry(id: asset.id, features: features, modifiedAt: asset.modifiedAt, version: version, indexedAt: now()))
            }
            // Saved even when cancelled partway, so finished items aren't redone.
            await index.upsert(entries)
            progress.indexed += entries.count
        }
        Self.log.info("Index run \(Task.isCancelled ? "paused" : "finished") at \(self.progress.indexed)/\(self.progress.total)")
    }

    /// Drops records for items removed from the library.
    func remove(_ ids: Set<LibraryItem.ID>) async {
        await index.remove(ids)
    }
}
