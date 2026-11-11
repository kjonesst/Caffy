import Foundation

/// A city that sample and test photos are taken in.
nonisolated struct SamplePlace: Hashable, Sendable {
    let name: String
    let coordinate: Coordinate

    static let sydney = SamplePlace(name: "Sydney", coordinate: Coordinate(latitude: -33.8688, longitude: 151.2093))
    static let melbourne = SamplePlace(name: "Melbourne", coordinate: Coordinate(latitude: -37.8136, longitude: 144.9631))
    static let hobart = SamplePlace(name: "Hobart", coordinate: Coordinate(latitude: -42.8821, longitude: 147.3272))
    /// About 70 km from Sydney: far enough to be "away", close enough for a day trip.
    static let wollongong = SamplePlace(name: "Wollongong", coordinate: Coordinate(latitude: -34.4278, longitude: 150.8931))

    /// How far, in metres, photos in one city spread from its centre. Well
    /// inside `EraBuildConfig.placeClusterRadius`.
    static let spread: Double = 3_000

    /// A point `north` and `east` metres from this place's centre.
    func offset(north: Double, east: Double) -> Coordinate {
        let metresPerDegree = 111_000.0
        let latitude = coordinate.latitude + north / metresPerDegree
        let longitude = coordinate.longitude + east / (metresPerDegree * cos(coordinate.latitude * .pi / 180))
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}
