import Photos
import UIKit

/// Loads the user's photos for display, at the size they're drawn.
///
/// Uses PhotoKit's caching image manager, plus a small in-memory cache so
/// scrolling back to a card doesn't load its photos again. Photos stored
/// only in iCloud may be downloaded, since the user is looking at them.
@MainActor
final class PhotoThumbnailLoader {
    static let shared = PhotoThumbnailLoader()

    private let manager = PHCachingImageManager()
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    /// Whether `identifier` is a library photo Caffy may show: not missing,
    /// not sample data, and with photo access granted. Checked before asking
    /// PhotoKit for anything.
    nonisolated static func canLoad(_ identifier: String?, access: PHAuthorizationStatus) -> Bool {
        guard let identifier, !identifier.isEmpty, !identifier.hasPrefix(SampleData.idPrefix) else { return false }
        return access == .authorized || access == .limited
    }

    /// Sizes are rounded up to steps of this many pixels, so prints of
    /// nearly the same size share one cached image.
    private static let sizeStep = 64.0

    /// The photo at about `pixelSize`, cropped to fill it, or `nil` when it
    /// can't be shown (see `canLoad`) or isn't in the library any more.
    func image(for identifier: String?, pixelSize: CGSize) async -> UIImage? {
        guard Self.canLoad(identifier, access: PHPhotoLibrary.authorizationStatus(for: .readWrite)),
              let identifier
        else { return nil }

        let size = CGSize(
            width: (pixelSize.width / Self.sizeStep).rounded(.up) * Self.sizeStep,
            height: (pixelSize.height / Self.sizeStep).rounded(.up) * Self.sizeStep
        )
        let key = "\(identifier)|\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        // High quality calls back exactly once, which the continuation needs.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let image: UIImage? = await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }
}
