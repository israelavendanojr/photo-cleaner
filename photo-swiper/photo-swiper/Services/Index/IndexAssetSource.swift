import CoreGraphics
import Foundation
import ImageIO

/// Where the indexer gets assets, metadata, and pixels. `PhotoKitIndexSource` is the real one.
protocol IndexAssetSource: Sendable {
    /// Every item in the user's library, favorites included.
    func currentAssets() async -> [IndexableAsset]
    /// Metadata features. Items no longer in the library are left out.
    func metadata(for ids: [LibraryItem.ID]) async -> [LibraryItem.ID: AssetFeatures]
    /// A small image that's already on the device, or nil. Never downloads.
    func image(for id: LibraryItem.ID) async -> AnalysisImage?
}

/// What the work queue needs to know about one library item.
struct IndexableAsset: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Gets image analysis.
        case photo
        /// Metadata only, for now.
        case screenshot, video
    }

    let id: LibraryItem.ID
    let createdAt: Date
    let modifiedAt: Date?
    let kind: Kind
}

/// A decoded image plus how to display it upright.
struct AnalysisImage: @unchecked Sendable {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation
}
