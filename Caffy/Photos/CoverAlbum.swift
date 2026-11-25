import Foundation
import Photos

/// The Photos album that holds each published playlist's cover photo.
///
/// Apps can't set a playlist's cover (see docs/notes/musickit-findings.md),
/// so the cover guide sends the user to Apple Music's photo picker. Keeping
/// every era's cover photo in one album makes it quick to find there.
/// Adding a photo to an album doesn't copy it: the album only refers to it.
///
/// A protocol, like `PhotoLibraryReader`, so publishing can be tested without
/// a photo library.
nonisolated protocol CoverAlbum: Sendable {
    /// Adds the photo to the album, making the album first if needed.
    func add(photo assetIdentifier: String) async throws

    /// The photos in the album, newest first. Empty when there's no album
    /// yet, or Caffy may not read it.
    func photos() async -> [String]
}

nonisolated enum CoverAlbumError: Error, Equatable {
    /// Photos access isn't granted (or is limited in a way that blocks it).
    case noAccess
    /// The photo is no longer in the library.
    case photoNotFound
    /// PhotoKit made the album but didn't say what it's called.
    case albumNotCreated
}

/// The real album, through PhotoKit.
///
/// Found by the id saved when Caffy made it; if that's gone (the user deleted
/// the album), by its name; otherwise made again.
nonisolated struct PhotoKitCoverAlbum: CoverAlbum {
    static let title = "Caffinated"
    static let albumIDKey = "coverAlbumID"

    var defaults: UserDefaults = .standard

    func add(photo assetIdentifier: String) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { throw CoverAlbumError.noAccess }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil).firstObject else {
            throw CoverAlbumError.photoNotFound
        }
        let album: PHAssetCollection
        if let existing = existingAlbum() {
            album = existing
        } else {
            album = try await createAlbum()
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: album)?.addAssets([asset] as NSArray)
        }
    }

    /// `@concurrent` so reading the album stays off the main actor.
    @concurrent
    func photos() async -> [String] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited, let album = existingAlbum() else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(in: album, options: options)
        var ids: [String] = []
        assets.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        return ids
    }

    private func existingAlbum() -> PHAssetCollection? {
        if let id = defaults.string(forKey: Self.albumIDKey),
           let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
            return album
        }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title == %@", Self.title)
        let found = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject
        if let found { defaults.set(found.localIdentifier, forKey: Self.albumIDKey) }
        return found
    }

    private func createAlbum() async throws -> PHAssetCollection {
        let placeholder = PlaceholderID()
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: Self.title)
            placeholder.value = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let id = placeholder.value,
              let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw CoverAlbumError.albumNotCreated
        }
        defaults.set(album.localIdentifier, forKey: Self.albumIDKey)
        return album
    }
}

/// Carries the new album's id out of PhotoKit's change block, which runs
/// once, before `performChanges` returns, so there's no shared access.
private final class PlaceholderID: @unchecked Sendable {
    var value: String?
}
