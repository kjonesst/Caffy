import Foundation

/// A human name for a place, such as "Melbourne".
nonisolated struct PlaceName: Codable, Hashable, Sendable {
    /// The town or city.
    let locality: String
    var region: String? = nil
    var country: String? = nil
}

/// Turns coordinates into place names.
///
/// The era pipeline only talks to this protocol, so tests use a fixed
/// dictionary while the app uses Apple's reverse geocoding (with a cache).
nonisolated protocol PlaceNamer: Sendable {
    /// The name of the place at `coordinate`, or `nil` when it can't be found
    /// (offline, open sea, a lookup limit). Never throws: titles simply leave
    /// the place out.
    func name(for coordinate: Coordinate) async -> PlaceName?
}
