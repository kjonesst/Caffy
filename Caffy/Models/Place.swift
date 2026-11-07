import Foundation
import SwiftData

/// A location Caffy knows about, such as a café, a beach, or a city on a trip.
///
/// Places are optional detail on a moment. Eras, not places, organise the app.
///
/// `@Model` turns this class into a SwiftData model: its properties are saved to
/// disk automatically, and SwiftUI views update when they change.
@Model
final class Place {
    var name: String
    var latitude: Double
    var longitude: Double

    /// Every moment captured here. `.nullify` keeps a moment in its era if its
    /// place is deleted, and `inverse` links this to `Moment.place`.
    @Relationship(deleteRule: .nullify, inverse: \Moment.place)
    var moments: [Moment] = []

    init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}
