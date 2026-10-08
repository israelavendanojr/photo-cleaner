import Foundation

/// One photo or video in the user's library.
struct LibraryItem: Identifiable, Hashable, Sendable {
    typealias ID = String

    enum Kind: Hashable, Sendable {
        case photo
        case video(duration: TimeInterval)
    }

    /// Why the app thinks an item might be worth clearing.
    enum Flag: String, Hashable, Sendable {
        case blurry, accidental, screenshot, forwarded, receipt

        var label: String {
            switch self {
            case .blurry: "Possibly blurry"
            case .accidental: "Accidental shot"
            case .screenshot: "Screenshot"
            case .forwarded: "Forwarded"
            case .receipt: "Receipt or code"
            }
        }
    }

    let id: ID
    let kind: Kind
    let date: Date
    /// Place name, e.g. "Santa Monica". Nil when the item has no location or it couldn't be resolved.
    let location: String?
    let bytes: Int64
    var flags: [Flag] = []
    var isFavorite = false
    let image: ImageReference

    var isVideo: Bool {
        if case .video = kind { true } else { false }
    }

    var duration: TimeInterval? {
        if case .video(let duration) = kind { duration } else { nil }
    }

    /// The single flag worth surfacing on a photo card, if any.
    var reviewFlag: Flag? {
        flags.first { [.blurry, .accidental, .receipt].contains($0) }
    }
}

/// Where an item's pixels come from. Only `ItemImage` resolves this.
enum ImageReference: Hashable, Sendable {
    /// An image in the asset catalog (mock data).
    case bundled(String)
    /// A `PHAsset` in the user's library.
    case photoKit(localIdentifier: String)
}
