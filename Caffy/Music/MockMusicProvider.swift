import Foundation

/// A fake `MusicProvider` that returns songs from a small built-in catalog.
///
/// It's deterministic — the same date always gives the same songs — which makes
/// sample data and previews predictable.
struct MockMusicProvider: MusicProvider {
    /// How many songs to return for each moment.
    var songsPerMoment = 3

    static let catalog: [Song] = [
        Song(id: "mock-01", title: "Dreams", artist: "Fleetwood Mac"),
        Song(id: "mock-02", title: "Midnight City", artist: "M83"),
        Song(id: "mock-03", title: "Electric Feel", artist: "MGMT"),
        Song(id: "mock-04", title: "Redbone", artist: "Childish Gambino"),
        Song(id: "mock-05", title: "Feels Like We Only Go Backwards", artist: "Tame Impala"),
        Song(id: "mock-06", title: "Pink + White", artist: "Frank Ocean"),
        Song(id: "mock-07", title: "Sunflower", artist: "Post Malone & Swae Lee"),
        Song(id: "mock-08", title: "Riptide", artist: "Vance Joy"),
        Song(id: "mock-09", title: "Golden Hour", artist: "JVKE"),
        Song(id: "mock-10", title: "Blinding Lights", artist: "The Weeknd"),
        Song(id: "mock-11", title: "Heat Waves", artist: "Glass Animals"),
        Song(id: "mock-12", title: "Kids", artist: "MGMT")
    ]

    func songs(playedAround date: Date) async throws -> [Song] {
        let catalog = Self.catalog
        // Use the day of the year to pick a starting point in the catalog, then
        // take the next few songs (wrapping around), so each day differs.
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        let count = min(songsPerMoment, catalog.count)
        return (0..<count).map { offset in
            catalog[(dayOfYear + offset) % catalog.count]
        }
    }
}
