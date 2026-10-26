import Foundation

/// Puts the most rewarding cards first right after a refill, so fresh swipes land on real wins.
///
/// A small reordering of cards already dealt, not a ranker change: similar-shot sets, then large
/// videos, move ahead of everything else, each keeping its order. Two similar cards are never left
/// next to each other, as in `SessionPlanner`.
enum FrontLoad {
    /// Videos at least this big count as strong.
    static let minVideoBytes: Int64 = 50_000_000

    /// `cards` with the strong ones from `start` on moved to `start`. Cards before `start` stay put.
    static func reordered(_ cards: [FeedCard], from start: Int) -> [FeedCard] {
        guard start < cards.count else { return cards }
        let head = Array(cards[..<start])
        let rest = Array(cards[start...])
        let similar = rest.filter(isSimilar)
        let videos = rest.filter(isLargeVideo)
        var others = rest.filter { !isSimilar($0) && !isLargeVideo($0) }
        guard !similar.isEmpty || !videos.isEmpty else { return cards }

        // Interleave so similar cards are separated by a video, or by an ordinary card if none is left.
        var spacers = videos
        var front: [FeedCard] = []
        for (n, card) in similar.enumerated() {
            if n > 0 {
                if !spacers.isEmpty {
                    front.append(spacers.removeFirst())
                } else if !others.isEmpty {
                    front.append(others.removeFirst())
                }
            }
            front.append(card)
        }
        let arranged = front + spacers + others
        // Nothing to separate the last similar cards with: put them back where they were.
        return arranged.count == rest.count && !hasAdjacentSimilar(head.suffix(1) + arranged) ? head + arranged : cards
    }

    private static func isSimilar(_ card: FeedCard) -> Bool {
        if case .similar = card { true } else { false }
    }

    private static func isLargeVideo(_ card: FeedCard) -> Bool {
        if case .video(let item) = card { item.bytes >= minVideoBytes } else { false }
    }

    private static func hasAdjacentSimilar(_ cards: [FeedCard]) -> Bool {
        zip(cards, cards.dropFirst()).contains { isSimilar($0) && isSimilar($1) }
    }
}
