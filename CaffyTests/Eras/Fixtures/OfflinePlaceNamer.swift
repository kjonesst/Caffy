import Foundation
@testable import Caffy

/// A `PlaceNamer` that never finds a name, like an offline phone.
struct OfflinePlaceNamer: PlaceNamer {
    func name(for coordinate: Coordinate) async -> PlaceName? { nil }
}
