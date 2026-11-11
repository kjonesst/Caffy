import Foundation

/// A `ListeningSource` that serves a fixed list of plays, such as the sample
/// history or a test fixture. Stands in for MusicKit until it's connected.
nonisolated struct MockListeningSource: ListeningSource {
    let events: [ListeningEvent]

    func plays(in interval: DateInterval) async throws -> [ListeningEvent] {
        events
            .filter { $0.interval.intersects(interval) }
            .sorted { ($0.interval.start, $0.song.id) < ($1.interval.start, $1.song.id) }
    }
}
