import Foundation
@testable import Caffy

/// A `PlaceNamer` that knows the fixture cities, and nothing else.
struct FixturePlaceNamer: PlaceNamer {
    var places: [FixturePlace] = [.sydney, .melbourne, .hobart, .wollongong]

    func name(for coordinate: Coordinate) async -> PlaceName? {
        places
            .first { $0.coordinate.distance(to: coordinate) < 25_000 }
            .map { PlaceName(locality: $0.name) }
    }
}

/// A `PlaceNamer` that never finds a name, like an offline phone.
struct OfflinePlaceNamer: PlaceNamer {
    func name(for coordinate: Coordinate) async -> PlaceName? { nil }
}
