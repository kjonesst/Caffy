import Foundation
import SwiftData

/// Fills the database with example places, moments, and playlists so the
/// app has something to show before PhotoKit and MusicKit are connected.
enum SampleData {
    /// A place to create, and how many days ago each of its moments happened.
    private struct SamplePlace {
        let name: String
        let latitude: Double
        let longitude: Double
        let daysAgo: [Int]
    }

    private static let places: [SamplePlace] = [
        SamplePlace(name: "Bondi Beach", latitude: -33.8908, longitude: 151.2743, daysAgo: [2, 9, 40]),
        SamplePlace(name: "Shibuya, Tokyo", latitude: 35.6595, longitude: 139.7005, daysAgo: [21, 22, 23]),
        SamplePlace(name: "Campus Library", latitude: -33.8888, longitude: 151.1872, daysAgo: [1, 5, 12, 18]),
        SamplePlace(name: "Blue Mountains", latitude: -33.7120, longitude: 150.3119, daysAgo: [60])
    ]

    /// Inserts sample data only when the database has no places yet,
    /// so it runs on first launch and never duplicates.
    static func insertIfNeeded(into context: ModelContext, using provider: some MusicProvider) async throws {
        let placeCount = try context.fetchCount(FetchDescriptor<Place>())
        guard placeCount == 0 else { return }
        try await insert(into: context, using: provider)
    }

    /// Inserts the sample data unconditionally. Used by previews.
    static func insert(into context: ModelContext, using provider: some MusicProvider) async throws {
        for sample in places {
            let place = Place(name: sample.name, latitude: sample.latitude, longitude: sample.longitude)
            context.insert(place)

            for daysAgo in sample.daysAgo {
                let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
                let songs = try await provider.songs(playedAround: date)
                // Appending to the relationship also inserts the moment and
                // sets `moment.place` for us, because of the `inverse`.
                place.moments.append(Moment(date: date, songs: songs))
            }

            let newestMomentDate = place.momentsNewestFirst.first?.date ?? .now
            place.playlist = CaffyPlaylist(name: "\(sample.name) Mix", lastUpdated: newestMomentDate)
        }
        try context.save()
    }
}
