import Foundation
import OSLog
import SwiftData

/// The cached feature records, on a background context of the app's shared container.
///
/// A plain actor that owns its `ModelContext`, never the main context, so reads and writes stay off
/// the main thread. Every write saves before returning.
actor FeatureIndex: FeatureIndexReading {
    private static let log = Logger(subsystem: "com.israelavendanojr.photo-swiper", category: "index")
    /// Keeps `IN (...)` predicates well under SQLite's variable limit.
    private static let chunk = 500

    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func indexed() -> [LibraryItem.ID: IndexedFeatures] {
        var descriptor = FetchDescriptor<AssetFeatureRecord>()
        // Everything but the feature print, which would add a few KB per record. See `featurePrints(for:)`.
        descriptor.propertiesToFetch = [
            \.localIdentifier, \.createdAt, \.bytes, \.isVideo, \.duration, \.isScreenshot, \.isFavorite, \.isInBurst,
            \.isBurstPick, \.hasAdjustments, \.burstID, \.isUserBurstPick, \.sharpness, \.exposureMean, \.darkFraction,
            \.brightFraction, \.aesthetic, \.isUtility, \.modifiedAt, \.featureVersion, \.indexedAt,
        ]
        return Dictionary(
            fetch(descriptor).map { ($0.localIdentifier, IndexedFeatures(features: $0.features, stamp: $0.stamp)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Just what the work queue needs to diff against the library.
    func stamps() -> [LibraryItem.ID: IndexStamp] {
        var descriptor = FetchDescriptor<AssetFeatureRecord>()
        descriptor.propertiesToFetch = [\.localIdentifier, \.modifiedAt, \.featureVersion]
        return Dictionary(fetch(descriptor).map { ($0.localIdentifier, $0.stamp) }, uniquingKeysWith: { first, _ in first })
    }

    func featurePrints(for ids: [LibraryItem.ID]) -> [LibraryItem.ID: FeaturePrint] {
        var prints: [LibraryItem.ID: FeaturePrint] = [:]
        prints.reserveCapacity(ids.count)
        for start in stride(from: 0, to: ids.count, by: Self.chunk) {
            let list = Array(ids[start..<min(start + Self.chunk, ids.count)])
            var descriptor = FetchDescriptor<AssetFeatureRecord>(predicate: #Predicate { list.contains($0.localIdentifier) })
            descriptor.propertiesToFetch = [\.localIdentifier, \.featurePrint]
            for record in fetch(descriptor) {
                if let data = record.featurePrint, let print = FeaturePrint(data: data) { prints[record.localIdentifier] = print }
            }
        }
        return prints
    }

    func count() -> Int {
        (try? context.fetchCount(FetchDescriptor<AssetFeatureRecord>())) ?? 0
    }

    /// Inserts or replaces records, then saves.
    func upsert(_ entries: [IndexEntry]) {
        guard !entries.isEmpty else { return }
        let existing = Dictionary(records(for: entries.map(\.id)).map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in entries {
            if let record = existing[entry.id] {
                record.update(from: entry)
            } else {
                context.insert(AssetFeatureRecord(entry))
            }
        }
        persist()
    }

    func remove(_ ids: Set<LibraryItem.ID>) {
        guard !ids.isEmpty else { return }
        for record in records(for: Array(ids)) { context.delete(record) }
        persist()
    }

    // MARK: Internals

    private func records(for ids: [LibraryItem.ID]) -> [AssetFeatureRecord] {
        stride(from: 0, to: ids.count, by: Self.chunk).flatMap { start in
            let list = Array(ids[start..<min(start + Self.chunk, ids.count)])
            return fetch(FetchDescriptor<AssetFeatureRecord>(predicate: #Predicate { list.contains($0.localIdentifier) }))
        }
    }

    private func fetch(_ descriptor: FetchDescriptor<AssetFeatureRecord>) -> [AssetFeatureRecord] {
        do {
            return try context.fetch(descriptor)
        } catch {
            Self.log.error("Couldn't fetch feature records: \(error)")
            return []
        }
    }

    private func persist() {
        do {
            try context.save()
        } catch {
            Self.log.error("Couldn't save feature records: \(error)")
        }
    }
}
