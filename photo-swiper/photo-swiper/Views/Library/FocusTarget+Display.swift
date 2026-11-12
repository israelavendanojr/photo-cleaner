import Foundation

/// How each focus is named on screen: the dashboard's chips, the feed's focus chip, and sentences.
extension FocusTarget {
    /// "Large videos", a chip on the dashboard.
    var chipTitle: String {
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

    /// "214 extra copies", "1 Live Photo": what a chip counts.
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

    /// What a chip's number means, in a sentence under it.
    var detail: String {
        switch self {
        case .category(.duplicate): "Only the extra copies count: what removing them would free."
        case .category(.similar): "Only the shots other than the best count: what removing them would free."
        case .category(.video): "Videos over \(Format.size(LibraryScan.largeVideoBytes)) you haven't reviewed."
        case .category(.screenshot): "Screenshots you haven't reviewed."
        case .category(.burst): "Burst shots neither you nor the camera picked."
        case .category(.photo): "Photos you haven't reviewed."
        case .allVideos: "Every video you haven't reviewed, at full size."
        case .livePhotos: "Every Live Photo you haven't reviewed, at full size."
        case .savedForLater: "They come back on their own after a day. Look at them now instead."
        }
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

    /// The part of the library's composition bar this focus is a slice of, if any.
    var kind: LibraryProfile.Kind? {
        switch self {
        case .category(.video), .allVideos: .video
        case .livePhotos: .livePhoto
        case .category(.screenshot): .screenshot
        default: nil
        }
    }
}
