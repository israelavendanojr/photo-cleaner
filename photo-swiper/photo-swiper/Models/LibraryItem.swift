import Foundation

/// One photo or video in the user's library.
struct LibraryItem: Identifiable, Hashable, Sendable, Codable {
    typealias ID = String

    enum Kind: Hashable, Sendable, Codable {
        case photo
        case video(duration: TimeInterval)
    }

    /// Why the app thinks an item might be worth clearing.
    enum Flag: String, Hashable, Sendable, Codable {
        case blurry, accidental, screenshot

        var label: String {
            switch self {
            case .blurry: "Possibly blurry"
            case .accidental: "Accidental shot"
            case .screenshot: "Screenshot"
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
    /// What the ranker saw when it picked this item. Nil for mock items and ones saved before ranking existed.
    var features: AssetFeatures?

    var isVideo: Bool {
        if case .video = kind { true } else { false }
    }

    var duration: TimeInterval? {
        if case .video(let duration) = kind { duration } else { nil }
    }

    /// The single flag worth surfacing on a photo card, if any.
    var reviewFlag: Flag? {
        flags.first { [.blurry, .accidental].contains($0) }
    }
}

extension LibraryItem {
    /// Same as the synthesized decoder, except flags this build no longer knows (e.g. the removed
    /// "receipt") are dropped instead of failing the whole item. Saved decks and progress hold
    /// items as JSON, so one stale flag would otherwise lose them.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        date = try container.decode(Date.self, forKey: .date)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        bytes = try container.decode(Int64.self, forKey: .bytes)
        flags = try container.decode([String].self, forKey: .flags).compactMap(Flag.init(rawValue:))
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        image = try container.decode(ImageReference.self, forKey: .image)
        features = try container.decodeIfPresent(AssetFeatures.self, forKey: .features)
    }
}

/// Where an item's pixels come from. Only `ItemImage` resolves this.
enum ImageReference: Hashable, Sendable, Codable {
    /// An image in the asset catalog (mock data).
    case bundled(String)
    /// A `PHAsset` in the user's library.
    case photoKit(localIdentifier: String)
}
