import Foundation

/// How each kind of clutter is named and drawn on screen.
extension CleanupCategory {
    /// "Large videos", as a dashboard row.
    var title: String {
        switch self {
        case .duplicate: "Duplicates"
        case .similar: "Similar shots"
        case .screenshot: "Screenshots"
        case .video: "Large videos"
        case .burst: "Burst shots"
        case .photo: "Photos"
        }
    }

    /// "Only videos", the feed's focus chip.
    var focusTitle: String {
        switch self {
        case .duplicate: "Only duplicates"
        case .similar: "Only similar shots"
        case .screenshot: "Only screenshots"
        case .video: "Only videos"
        case .burst: "Only bursts"
        case .photo: "Only photos"
        }
    }
}
