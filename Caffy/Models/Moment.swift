import Foundation
import SwiftData

/// A point in time at a place — usually a photo — paired with the songs the
/// user was listening to around then.
@Model
final class Moment {
    var date: Date

    /// The PhotoKit `PHAsset.localIdentifier` for the photo behind this moment.
    /// `nil` for sample data, which shows a placeholder image instead.
    var photoAssetIdentifier: String?

    var songs: [Song]

    /// Where this moment happened. The other side of `Place.moments`.
    var place: Place?

    init(date: Date, songs: [Song], photoAssetIdentifier: String? = nil) {
        self.date = date
        self.songs = songs
        self.photoAssetIdentifier = photoAssetIdentifier
    }
}
