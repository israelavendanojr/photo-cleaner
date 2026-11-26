import Foundation

extension FeedSort {
    /// The pill's and the menu's name.
    var title: String {
        switch self {
        case .recommended: "Recommended"
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .largest: "Largest"
        }
    }

    /// For VoiceOver, after "Sorted by".
    var phrase: String {
        switch self {
        case .recommended: "recommended"
        case .newest: "newest first"
        case .oldest: "oldest first"
        case .largest: "largest first"
        }
    }
}
