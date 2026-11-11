import Foundation
@testable import Caffy

/// A `ListeningSource` that serves a fixed list of plays.
struct FixtureListeningSource: ListeningSource {
    let events: [ListeningEvent]

    func plays(in interval: DateInterval) async throws -> [ListeningEvent] {
        events
            .filter { $0.interval.intersects(interval) }
            .sorted { ($0.interval.start, $0.song.id) < ($1.interval.start, $1.song.id) }
    }
}
