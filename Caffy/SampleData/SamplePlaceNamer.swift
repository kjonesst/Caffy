import Foundation

/// A `PlaceNamer` that knows the sample cities, and nothing else. Sample data
/// never needs a real place lookup.
nonisolated struct SamplePlaceNamer: PlaceNamer {
    var places: [SamplePlace] = [.sydney, .melbourne, .hobart, .wollongong]

    func name(for coordinate: Coordinate) async -> PlaceName? {
        places
            .first { $0.coordinate.distance(to: coordinate) < 25_000 }
            .map { PlaceName(locality: $0.name) }
    }
}
