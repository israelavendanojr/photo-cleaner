import Foundation

/// Narrows a page's candidates to one kind of clutter, for a feed the user focused from the dashboard.
///
/// It runs before planning, so a focused page is as full as the library allows, not whatever of one kind
/// happened to rank into an ordinary page. Pure, like the rest of `Ranking/`.
enum FeedFocus {
    struct Input: Equatable {
        var candidates: [RankCandidate]
        var duplicates: [PlannedGroup]
        var similar: [PlannedGroup]
    }

    /// Duplicate and similar focus keep their groups and only the candidates in them. Any other kind keeps
    /// the candidates of that kind and no groups, so they show as single cards. Nil changes nothing.
    static func apply(_ input: Input, focus: CleanupCategory?) -> Input {
        guard let focus else { return input }
        switch focus {
        case .duplicate:
            return Input(candidates: members(of: input.duplicates, in: input.candidates), duplicates: input.duplicates, similar: [])
        case .similar:
            return Input(candidates: members(of: input.similar, in: input.candidates), duplicates: [], similar: input.similar)
        case .screenshot, .video, .burst, .photo:
            return Input(candidates: input.candidates.filter { CleanupCategory.inferred(from: $0.features) == focus },
                         duplicates: [], similar: [])
        }
    }

    private static func members(of groups: [PlannedGroup], in candidates: [RankCandidate]) -> [RankCandidate] {
        let ids = Set(groups.flatMap(\.ids))
        return candidates.filter { ids.contains($0.id) }
    }
}
