import CoreLocation
import Foundation
import Photos

/// What the feed builder reads from the photo library. `PhotoKitAssetCatalog` is the real one; tests
/// use a fake, so a whole page build runs without PhotoKit.
protocol AssetCatalog: Sendable {
    /// Every photo and video the feed may offer, newest first, without favorites when `skipFavorites`.
    /// Favorites and edit dates are read live, never cached.
    func entries(skipFavorites: Bool) -> [CandidatePool.Entry]
    /// Live metadata for items the index has no fresh record for. Items no longer in the library are left out.
    func features(for ids: [LibraryItem.ID]) -> [LibraryItem.ID: AssetFeatures]
    /// Every one of `ids` still in the library, with where it was taken when it has a location.
    func locations(for ids: [LibraryItem.ID]) -> [LibraryItem.ID: CLLocation?]
}

/// The user's library through PhotoKit.
struct PhotoKitAssetCatalog: AssetCatalog {
    func entries(skipFavorites: Bool) -> [CandidatePool.Entry] {
        let result = PHAsset.fetchAssets(with: PhotoKitLibrary.fetchOptions(skipFavorites: skipFavorites))
        var entries: [CandidatePool.Entry] = []
        entries.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            entries.append(CandidatePool.Entry(id: asset.localIdentifier, modifiedAt: asset.modificationDate, isFavorite: asset.isFavorite))
        }
        return entries
    }

    func features(for ids: [LibraryItem.ID]) -> [LibraryItem.ID: AssetFeatures] {
        PHAsset.byID(ids).mapValues(AssetMapper.features(for:))
    }

    func locations(for ids: [LibraryItem.ID]) -> [LibraryItem.ID: CLLocation?] {
        PHAsset.byID(ids).mapValues(\.location)
    }
}

extension PHAsset {
    /// The assets for `ids` still in the library, by local identifier, in one fetch.
    static func byID(_ ids: [String]) -> [String: PHAsset] {
        guard !ids.isEmpty else { return [:] }
        var assets: [String: PHAsset] = [:]
        assets.reserveCapacity(ids.count)
        fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            assets[asset.localIdentifier] = asset
        }
        return assets
    }
}
