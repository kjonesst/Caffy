import Foundation
import SwiftData

/// A photo paired with the songs the user was listening to around then.
///
/// Fields added after the first release are optional or have a default, so
/// an existing database gains them on its own when the app updates.
@Model
final class Moment {
    /// When the moment's first photo was taken.
    var date: Date

    /// The `PhotoMoment` id this was saved from (its first photo's PhotoKit
    /// identifier), so the next sync can find it again. `nil` for sample data.
    var momentID: String?

    /// When the moment's last photo was taken. `nil` for sample data.
    var endDate: Date?

    /// The PhotoKit `PHAsset.localIdentifier` for the photo that stands for
    /// this moment in collages. `nil` for sample data, which shows a
    /// placeholder image instead.
    var photoAssetIdentifier: String?

    /// The photo's width divided by its height. A collage with a single photo
    /// uses this to choose a portrait or landscape print.
    var photoAspectRatio: Double = 1

    /// Where the moment happened, if its photos have a location.
    var latitude: Double?
    var longitude: Double?

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

extension Moment {
    /// Copies everything about `moment` except its songs. Only what changed
    /// is set (see `assign`).
    func update(from moment: PhotoMoment) {
        assign(moment.id, to: \.momentID)
        assign(moment.start, to: \.date)
        assign(moment.end, to: \.endDate)
        assign(moment.coverID, to: \.photoAssetIdentifier)
        assign(moment.coverAspectRatio, to: \.photoAspectRatio)
        assign(moment.coordinate?.latitude, to: \.latitude)
        assign(moment.coordinate?.longitude, to: \.longitude)
    }
}
