import Foundation

/// What a feed focused from the dashboard shows: one kind of clutter (`CleanupCategory`, as the history
/// files it), or one of the library's kinds that isn't a cleanup category. Not saved: a relaunch shows everything.
enum FocusTarget: Hashable, Codable, Sendable {
    /// Duplicates, similar shots, large videos, screenshots or bursts, as the dashboard counts them
    /// (`LibraryScan.suggested`).
    case category(CleanupCategory)
    /// Every video, whatever its size.
    case allVideos
    case livePhotos
    /// Photos the analysis reads as taken by accident: a pocket or lens-cap shot, a blown-out frame, or
    /// soft junk (`ImageFlags.isAccidental`).
    case accidental
    /// Photos the analysis reads as blurry and not intentionally soft (`ImageFlags.isBlurry`). Never also
    /// accidental, as the cards flag them.
    case blurry
    /// Photos Vision reads as a utility shot: a receipt, a document, code.
    case documents
    /// Items the user swiped "later", including ones still sitting out their cooldown: the user asked to
    /// see them now. Only shown, never decided by the focus.
    case savedForLater

    /// The dashboard's library rows, in the order equal sizes keep (`DashboardStats.rows`): findings, then
    /// kinds, then saved for later. Large videos aren't a row: they're already in Videos, and two video rows
    /// read as a repeat.
    static let listOrder: [FocusTarget] = [
        .category(.duplicate), .category(.similar), .accidental, .blurry, .allVideos, .livePhotos,
        .category(.screenshot), .category(.burst), .documents, .category(.photo), .savedForLater,
    ]

    /// Whether the focus is a set of IDs the feed builder can't tell from features alone, so a page is
    /// limited to `FeedOptions.only`.
    var isByID: Bool {
        self == .livePhotos || self == .savedForLater
    }
}

/// Narrows a page's candidates to one focus, for a feed the user focused from the dashboard.
///
/// It runs before planning, so a focused page is as full as the library allows, not whatever of one kind
/// happened to rank into an ordinary page. Pure, like the rest of `Ranking/`.
enum FeedFocus {
    struct Input: Equatable {
        var candidates: [RankCandidate]
        var duplicates: [PlannedGroup]
        var similar: [PlannedGroup]
    }

    /// Duplicate and similar focus keep their groups and only the candidates in them. A large-video,
    /// screenshot or burst focus keeps the candidates the dashboard counts as that kind
    /// (`LibraryScan.suggested`) and no groups, so they show as single cards. All videos keeps every video;
    /// Live Photos and saved for later keep the candidates in `only`, also as single cards. Accidental,
    /// blurry and documents keep what the analysis flags (`LibraryScan.findings`), as single cards. Nil changes nothing.
    static func apply(_ input: Input, focus: FocusTarget?, only: Set<LibraryItem.ID>? = nil) -> Input {
        guard let focus else { return input }
        switch focus {
        case .category(.duplicate):
            return Input(candidates: members(of: input.duplicates, in: input.candidates), duplicates: input.duplicates, similar: [])
        case .category(.similar):
            return Input(candidates: members(of: input.similar, in: input.candidates), duplicates: [], similar: input.similar)
        case .category(let category) where category == .photo:
            return singles(input.candidates.filter { CleanupCategory.inferred(from: $0.features) == .photo })
        case .category(let category):
            return singles(input.candidates.filter { LibraryScan.suggested($0.features) == category })
        case .allVideos:
            return singles(input.candidates.filter(\.features.isVideo))
        case .livePhotos:
            // A Live Photo's video is part of it; a video is never a Live Photo, as the dashboard counts it.
            return singles(input.candidates.filter { only?.contains($0.id) == true && !$0.features.isVideo })
        case .savedForLater:
            return singles(input.candidates.filter { only?.contains($0.id) == true })
        case .accidental, .blurry, .documents:
            return singles(input.candidates.filter { LibraryScan.findings($0.features).contains(focus) })
        }
    }

    private static func singles(_ candidates: [RankCandidate]) -> Input {
        Input(candidates: candidates, duplicates: [], similar: [])
    }

    private static func members(of groups: [PlannedGroup], in candidates: [RankCandidate]) -> [RankCandidate] {
        let ids = Set(groups.flatMap(\.ids))
        return candidates.filter { ids.contains($0.id) }
    }
}
