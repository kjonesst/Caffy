import Foundation
import SwiftData

/// A location Caffy knows about, such as a café, a beach, or a city on a trip.
///
/// `@Model` turns this class into a SwiftData model: its properties are saved to
/// disk automatically, and SwiftUI views update when they change.
@Model
final class Place {
    var name: String
    var latitude: Double
    var longitude: Double

    /// Every moment captured here. `.cascade` means deleting a place also
    /// deletes its moments, and `inverse` links this to `Moment.place`.
    @Relationship(deleteRule: .cascade, inverse: \Moment.place)
    var moments: [Moment] = []

    /// The self-updating playlist Caffy builds for this place.
    @Relationship(deleteRule: .cascade, inverse: \CaffyPlaylist.place)
    var playlist: CaffyPlaylist?

    init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    /// SwiftData doesn't keep to-many relationships in any order, so sort here.
    var momentsNewestFirst: [Moment] {
        moments.sorted { $0.date > $1.date }
    }
}
