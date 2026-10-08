import Foundation

/// Ready-made mock content for SwiftUI previews.
enum PreviewSamples {
    static let session = MockFeedBuilder().makeSessionNow(number: 1)

    static var blurryPhoto: LibraryItem {
        session.items.first { $0.reviewFlag == .blurry } ?? plainPhoto
    }

    static var plainPhoto: LibraryItem {
        session.items.first { !$0.isVideo && $0.flags.isEmpty }!
    }

    static var video: LibraryItem {
        session.items.first(where: \.isVideo)!
    }

    static var similarGroup: SimilarGroup {
        session.cards.lazy.compactMap { if case .similar(let group) = $0 { group } else { nil } }.first!
    }

    static var screenshotBatch: ItemBatch {
        session.cards.lazy.compactMap { if case .batch(let batch) = $0 { batch } else { nil } }.first!
    }
}
