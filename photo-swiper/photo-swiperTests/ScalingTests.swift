import Foundation
import SwiftData
import Testing
@testable import photo_swiper

extension Tag {
    /// Benchmarks over 50,000 synthetic items. CI skips them; see docs/ci.md.
    @Tag static var scaling: Tag
}

/// How the page build's pure stages scale to a 50,000-item library (JUN-5 audit, Q-1).
///
/// Timings go to the test log as `SCALING | …` lines, and to the file at `SCALING_OUT` when set
/// (pass `TEST_RUNNER_SCALING_OUT=/path` to xcodebuild). The time limits catch an accidental O(n²).
@Suite(.serialized, .tags(.scaling), .timeLimit(.minutes(10)))
struct ScalingTests {
    static let count = 50_000
    static let library = SyntheticLibrary(count: count)
    static let pages = 5

    @Test func groupersAndPlannerAt50k() {
        let candidates = Self.library.candidates
        let duplicates = DuplicateGrouper()
        let similar = SimilarGrouper()

        var (pairIDs, seconds) = timed { duplicates.candidateIDs(candidates) }
        ScalingReport.line("duplicate candidates: \(pairIDs.count) of \(candidates.count) in \(seconds.ms)")
        let duplicatePrints = Self.library.prints(for: Array(pairIDs))
        let (duplicateGroups, duplicateSeconds) = timed { duplicates.group(candidates.filter { pairIDs.contains($0.id) }, prints: duplicatePrints) }
        ScalingReport.line("DuplicateGrouper.group: \(duplicateGroups.count) sets in \(duplicateSeconds.ms)")

        (pairIDs, seconds) = timed { similar.neighborIDs(candidates) }
        ScalingReport.line("similar neighbors: \(pairIDs.count) of \(candidates.count) (\(pairIDs.count * Self.library.dimensions * 4 / 1_000_000) MB of prints) in \(seconds.ms)")
        let neighbors = pairIDs
        let similarPrints = Self.library.prints(for: Array(neighbors))
        let (result, similarSeconds) = timed { similar.group(candidates.filter { neighbors.contains($0.id) }, prints: similarPrints) }
        ScalingReport.line("SimilarGrouper.group: \(result.groups.count) groups in \(similarSeconds.ms)")

        let planner = SessionPlanner(limit: 20, minBatch: 3, maxBatch: 40)
        let planned = result.groups.map { PlannedGroup(ids: $0.ids, bestID: $0.ids[0], reason: "") }
        let (slots, planSeconds) = timed { planner.plan(candidates, groups: planned, now: .now) }
        ScalingReport.line("SessionPlanner.plan: \(slots.count) slots in \(planSeconds.ms)")

        #expect(!duplicateGroups.isEmpty)
        #expect(!result.groups.isEmpty)
        #expect(!slots.isEmpty)
    }

    /// The whole grouping stage, page after page, as the builder runs it. Prints come from memory,
    /// so this is the work after reading them; see the on-disk test for the reads.
    @Test func groupingPerPageAt50k() async {
        let loads = PrintLoads(library: Self.library)
        let pages = await PageRun.run(Self.library.candidates, pages: Self.pages) { cached in
            await PageGrouping.uncached(cached) { ids in await loads.load(ids) }
        }
        for page in pages {
            ScalingReport.line("uncached page \(page.number): \(page.printsLoaded) prints (\(page.printsLoaded * Self.library.dimensions * 4 / 1_000_000) MB) in \(page.seconds.ms)")
        }
        #expect(pages.allSatisfy { !$0.slots.isEmpty })
    }

    /// Same, with prints read from a real on-disk `FeatureIndex`, so SQLite and decoding count.
    @Test func groupingPerPageOnDiskAt50k() async throws {
        let index = try await Self.filledIndex()
        let pages = await PageRun.run(Self.library.candidates, pages: Self.pages) { cached in
            await PageGrouping.uncached(cached) { ids in await index.featurePrints(for: ids) }
        }
        for page in pages {
            ScalingReport.line("uncached on-disk page \(page.number): \(page.printsLoaded) prints in \(page.seconds.ms)")
        }
        #expect(pages.allSatisfy { !$0.slots.isEmpty })
    }

    /// An on-disk index holding every synthetic photo's features and print.
    static func filledIndex() async throws -> FeatureIndex {
        let directory = FileManager.default.temporaryDirectory.appending(path: "scaling-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let index = FeatureIndex(container: try SwiftDataProgressStore.makeContainer(url: directory.appending(path: "index.store")))
        let started = Date.now
        let entries = library.candidates.map { candidate in
            IndexEntry(id: candidate.id, features: candidate.features, modifiedAt: nil, version: IndexFreshness.currentVersion,
                       indexedAt: .now, featurePrint: library.print(for: candidate.id)?.data, hashVersion: DHash.version)
        }
        for start in stride(from: 0, to: entries.count, by: 2_000) {
            await index.upsert(Array(entries[start..<min(start + 2_000, entries.count)]))
        }
        ScalingReport.line("filled on-disk index with \(entries.count) records in \(Date.now.timeIntervalSince(started).ms)")
        return index
    }
}

/// Pages built one after another: each page's items join the excluded set, as decided cards do.
enum PageRun {
    struct Page {
        let number: Int
        let groups: PageGroups
        let slots: [SessionPlanner.Slot]
        let seconds: TimeInterval
        var printsLoaded: Int { groups.duplicatePrintCount + groups.similarPrintCount }
    }

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func run(_ candidates: [RankCandidate], pages: Int, excluding initial: Set<LibraryItem.ID> = [],
                    grouping: ([RankCandidate]) async -> PageGroups) async -> [Page] {
        let planner = SessionPlanner(limit: PhotoKitFeedBuilder.photosPerSession, minBatch: PhotoKitFeedBuilder.minBatch,
                                     maxBatch: PhotoKitFeedBuilder.maxBatch)
        var excluded = initial
        var result: [Page] = []
        for number in 1...pages {
            let cached = candidates.filter { !excluded.contains($0.id) }
            let started = Date.now
            let groups = await grouping(cached)
            let seconds = Date.now.timeIntervalSince(started)
            let slots = planner.plan(cached, groups: groups.similar, duplicates: groups.duplicates, now: now)
            result.append(Page(number: number, groups: groups, slots: slots, seconds: seconds))
            excluded.formUnion(slots.flatMap(\.ids))
        }
        return result
    }
}

/// Serves synthetic prints and counts how many were asked for.
actor PrintLoads {
    let library: SyntheticLibrary
    private(set) var total = 0

    init(library: SyntheticLibrary) {
        self.library = library
    }

    func load(_ ids: [LibraryItem.ID]) -> [LibraryItem.ID: FeaturePrint] {
        total += ids.count
        return library.prints(for: ids)
    }
}

enum ScalingReport {
    static func line(_ text: String) {
        let line = "SCALING | \(text)"
        Swift.print(line)
        guard let path = ProcessInfo.processInfo.environment["SCALING_OUT"] else { return }
        let data = Data((line + "\n").utf8)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}

func timed<T>(_ work: () -> T) -> (T, TimeInterval) {
    let started = Date.now
    let value = work()
    return (value, Date.now.timeIntervalSince(started))
}

extension TimeInterval {
    var ms: String { String(format: "%.0f ms", self * 1000) }
}
