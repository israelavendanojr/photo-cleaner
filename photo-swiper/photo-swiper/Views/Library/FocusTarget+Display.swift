import Foundation

/// How each focus is named on screen: the dashboard's rows, the feed's focus chip, and sentences.
extension FocusTarget {
    /// "Large videos", a row on the dashboard.
    var title: String {
        switch self {
        case .category(.similar): "Similar"
        case .category(.burst): "Bursts"
        case .category(let category): category.title
        case .allVideos: "Videos"
        case .livePhotos: "Live Photos"
        case .savedForLater: "Saved for later"
        }
    }

    /// "Only large videos", the feed's focus chip.
    var focusTitle: String {
        switch self {
        case .category(.video): "Only large videos"
        case .category(let category): category.focusTitle
        case .allVideos: "Only videos"
        case .livePhotos: "Only Live Photos"
        case .savedForLater: "Saved for later"
        }
    }

    /// "large videos", inside a sentence. Live Photos keeps its capitals.
    var phrase: String {
        switch self {
        case .category(let category): category.title.lowercased()
        case .allVideos: "videos"
        case .livePhotos: "Live Photos"
        case .savedForLater: "photos saved for later"
        }
    }

    /// The row's icon on the dashboard.
    var systemImage: String {
        switch self {
        case .category(.duplicate): "square.on.square"
        case .category(.similar): "square.stack.3d.down.right"
        case .category(.video): "video.badge.ellipsis"
        case .category(.screenshot): "camera.viewfinder"
        case .category(.burst): "square.stack.3d.forward.dottedline"
        case .category(.photo): "photo"
        case .allVideos: "video"
        case .livePhotos: "livephoto"
        case .savedForLater: "clock.arrow.circlepath"
        }
    }

    /// "214 extra copies", "1 Live Photo": what a row counts.
    func count(_ count: Int) -> String {
        let one = count == 1
        let noun = switch self {
        case .category(.duplicate): one ? "extra copy" : "extra copies"
        case .category(.similar): one ? "similar shot" : "similar shots"
        case .category(.video): one ? "large video" : "large videos"
        case .category(.screenshot): one ? "screenshot" : "screenshots"
        case .category(.burst): one ? "burst shot" : "burst shots"
        case .category(.photo): one ? "photo" : "photos"
        case .allVideos: one ? "video" : "videos"
        case .livePhotos: one ? "Live Photo" : "Live Photos"
        case .savedForLater: "saved for later"
        }
        return "\(Format.count(count)) \(noun)"
    }

    /// "allVideos", for UI test identifiers.
    var identifier: String {
        switch self {
        case .category(let category): category.rawValue
        case .allVideos: "allVideos"
        case .livePhotos: "livePhotos"
        case .savedForLater: "savedForLater"
        }
    }
}
