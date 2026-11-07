import Foundation
import SwiftData

/// A photo paired with the songs the user was listening to around then.
@Model
final class Moment {
    var date: Date

    /// The PhotoKit `PHAsset.localIdentifier` for the photo behind this moment.
    /// `nil` for sample data, which shows a placeholder image instead.
    var photoAssetIdentifier: String?

    /// The photo's width divided by its height. A collage with a single photo
    /// uses this to choose a portrait or landscape print.
    var photoAspectRatio: Double = 1

    var songs: [Song]

    /// The era this moment belongs to. The other side of `Era.moments`.
    var era: Era?

    /// Where this moment happened, if Caffy knows. The other side of `Place.moments`.
    var place: Place?

    init(date: Date, songs: [Song], photoAssetIdentifier: String? = nil, photoAspectRatio: Double = 1) {
        self.date = date
        self.songs = songs
        self.photoAssetIdentifier = photoAssetIdentifier
        self.photoAspectRatio = photoAspectRatio
    }
}
