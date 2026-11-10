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
/// removed, but only when `canPrune` says the app sees the whole library: under limited access,
/// everything outside the selection looks gone. Work is saved in batches; photos get image analysis,
/// screenshots and videos metadata only.
///
/// After that, photos whose record has never been hashed for exact duplicates (indexed before
/// `DHash` existed) get a hash-only pass: a small local image and its pixel size, no Vision, so
/// adding the hash didn't need a version bump that would redo the whole library.
actor LibraryIndexer {
    static let batchSize = 50
    private static let log = Logger.app(category: "index")

    private let source: any IndexAssetSource
    private let analyzer: any ImageAnalyzing
    private let index: FeatureIndex
    private let version: Int
    private let hashVersion: Int
    private let batchSize: Int
    private let canPrune: @Sendable () -> Bool
    private let now: @Sendable () -> Date

    private(set) var progress = IndexProgress(indexed: 0, total: 0)
    private var isRunning = false

    init(
        source: any IndexAssetSource,
        analyzer: any ImageAnalyzing,
        index: FeatureIndex,
        version: Int = IndexFreshness.currentVersion,
        hashVersion: Int = DHash.version,
        batchSize: Int = LibraryIndexer.batchSize,
        canPrune: @escaping @Sendable () -> Bool = { true },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.analyzer = analyzer
        self.index = index
        self.version = version
        self.hashVersion = hashVersion
        self.batchSize = batchSize
        self.canPrune = canPrune
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
        let gone = canPrune() ? Set(stamps.keys).subtracting(assets.map(\.id)) : []
        await index.remove(gone)

        var edited = 0, outdated = 0
        let queue = assets.filter { asset in
            guard let stamp = stamps[asset.id] else { return true }
            if IndexFreshness.isCurrent(stamp, assetModifiedAt: asset.modifiedAt, version: version) { return false }
            if stamp.version < version { outdated += 1 } else { edited += 1 }
            return true
        }
        progress = IndexProgress(indexed: assets.count - queue.count, total: assets.count)
        let started = Date.now
        var done = 0
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
                var print: Data?
                if asset.kind == .photo, let image = await source.image(for: asset.id) {
                    let signals = await analyzer.analyze(image.cgImage, orientation: image.orientation)
                    features.apply(signals)
                    print = signals.featurePrint
                }
                entries.append(IndexEntry(id: asset.id, features: features, modifiedAt: asset.modifiedAt, version: version,
                                          indexedAt: now(), featurePrint: print,
                                          hashVersion: asset.kind == .photo ? hashVersion : nil))
            }
            // Saved even when cancelled partway, so finished items aren't redone.
            await index.upsert(entries)
            progress.indexed += entries.count
            done += entries.count
        }
        let elapsed = Date.now.timeIntervalSince(started)
        Self.log.info("Index run \(Task.isCancelled ? "paused" : "finished") at \(self.progress.indexed)/\(self.progress.total): \(done) items in \(elapsed, format: .fixed(precision: 1))s, \(done == 0 ? 0 : elapsed / Double(done) * 1000, format: .fixed(precision: 1)) ms each")
        await backfillHashes(assets)
    }

    /// Hashes photos indexed before `DHash` existed (or with an older hash version), newest first.
    /// Their other features stay as they are.
    private func backfillHashes(_ assets: [IndexableAsset]) async {
        guard !Task.isCancelled else { return }
        let unhashed = await index.unhashedPhotos(version: hashVersion)
        let queue = assets.filter { $0.kind == .photo && unhashed.contains($0.id) }
        guard !queue.isEmpty else { return }
        let started = Date.now
        var done = 0
        for start in stride(from: 0, to: queue.count, by: batchSize) {
            guard !Task.isCancelled else { break }
            let batch = queue[start..<min(start + batchSize, queue.count)]
            let metadata = await source.metadata(for: batch.map(\.id))
            var entries: [HashEntry] = []
            for asset in batch {
                guard !Task.isCancelled else { break }
                guard let features = metadata[asset.id] else { continue }
                var hash: UInt64?
                if let image = await source.image(for: asset.id) {
                    hash = DHash.compute(image.cgImage, orientation: image.orientation)
                }
                entries.append(HashEntry(id: asset.id, pixelWidth: features.pixelWidth, pixelHeight: features.pixelHeight,
                                         dHash: hash, version: hashVersion))
            }
            await index.updateHashes(entries)
            done += entries.count
        }
        Self.log.info("Hash backfill \(Task.isCancelled ? "paused" : "finished"): \(done) of \(queue.count) photos in \(Date.now.timeIntervalSince(started), format: .fixed(precision: 1))s")
    }

    /// Drops records for items removed from the library.
    func remove(_ ids: Set<LibraryItem.ID>) async {
        await index.remove(ids)
    }
}
