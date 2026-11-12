import Foundation
import Photos

/// Reads the facts Caffy needs about every photo it may see.
///
/// A protocol so library syncing can be tested without a photo library.
nonisolated protocol PhotoLibraryReader: Sendable {
    /// Every photo Caffy may read, or `nil` when it may not read the library
    /// at all (so nothing should change).
    func photos() async -> [PhotoItem]?
}

/// Reads the user's photo library with PhotoKit.
///
/// Only the facts in `PhotoItem` are read (no pixels), so even a large
/// library costs little. Screenshots are skipped: they have no place and
/// rarely belong to a moment. Hidden photos are skipped too, as PhotoKit does
/// by default.
nonisolated struct PhotoKitLibraryReader: PhotoLibraryReader {
    /// `@concurrent` so a large library is read off the main actor.
    @concurrent
    func photos() async -> [PhotoItem]? {
        // Checked here, not just in the app's permission state: with DEBUG's
        // `-fakePermissions`, the app can believe it has access PhotoKit
        // doesn't give, and an empty read would wipe the eras.
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }

        let assets = Self.fetchImages()
        var items: [PhotoItem] = []
        items.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            if let item = PhotoItem(asset: asset) {
                items.append(item)
            }
        }
        return items
    }

    /// Every image in the library, including the ones `PhotoItem(asset:)`
    /// skips. The change observer watches this same fetch.
    static func fetchImages() -> PHFetchResult<PHAsset> {
        PHAsset.fetchAssets(with: .image, options: nil)
    }
}

nonisolated extension PhotoItem {
    /// The facts Caffy keeps about `asset`, or `nil` for a photo it skips:
    /// screenshots, and photos with no date.
    init?(asset: PHAsset) {
        guard let date = asset.creationDate, !asset.mediaSubtypes.contains(.photoScreenshot) else { return nil }
        self.init(
            id: asset.localIdentifier,
            creationDate: date,
            coordinate: asset.location.map {
                Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            },
            aspectRatio: asset.pixelHeight > 0 ? Double(asset.pixelWidth) / Double(asset.pixelHeight) : 1
        )
    }
}
