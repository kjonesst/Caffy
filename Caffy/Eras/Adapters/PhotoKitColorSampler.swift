import Foundation
import Photos
import UIKit

/// Reads tiny thumbnails of the user's photos for working out era palettes.
///
/// Asks PhotoKit for a `side × side` thumbnail (32 by default: about a
/// thousand pixels, plenty for main colours and quick to read). Only photos
/// already on the device are read; nothing is downloaded from iCloud, so a
/// photo that isn't here just doesn't count towards its era's colours.
nonisolated struct PhotoKitColorSampler: ColorSampler {
    var side = 32

    func pixels(ofPhoto id: String) async -> RGBAImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        // High quality calls back exactly once, which the continuation needs.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false

        let image: CGImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
        return image.flatMap { RGBAImage($0, side: side) }
    }
}
