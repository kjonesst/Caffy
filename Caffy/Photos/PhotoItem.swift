import CoreLocation
import Foundation

/// A point on the map, in degrees.
///
/// Caffy keeps its own small struct instead of `CLLocation` because
/// `CLLocation` is a class that isn't marked `Sendable`, so it can't be passed
/// freely between the background fetch and the main actor. `clLocation` turns
/// it back into one when Core Location's distance maths is needed.
nonisolated struct Coordinate: Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// The distance to another coordinate in metres, along the Earth's surface.
    func distance(to other: Coordinate) -> CLLocationDistance {
        clLocation.distance(from: other.clLocation)
    }
}

/// The few facts Caffy keeps about one photo in the user's library.
///
/// This is deliberately tiny: no pixels and no `PHAsset`. Images are loaded
/// on demand from `id` by the thumbnail loader, so a library of thousands of
/// photos costs only a few bytes per photo here.
///
/// `nonisolated` and `Sendable` let the background fetch create these and hand
/// them to the main actor safely.
nonisolated struct PhotoItem: Hashable, Sendable, Identifiable {
    /// The PhotoKit `PHAsset.localIdentifier`. Stable on this device.
    let id: String
    let creationDate: Date
    /// Where the photo was taken, from its GPS metadata. `nil` when the photo
    /// has no location (screenshots, edited copies, location turned off).
    let coordinate: Coordinate?
    /// Width divided by height, so collages can pick a portrait or landscape print.
    var aspectRatio: Double = 1
}
