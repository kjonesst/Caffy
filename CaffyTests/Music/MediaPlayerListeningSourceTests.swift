import Foundation
import Testing
@testable import Caffy

/// Tests for `MediaPlayerListeningSource`, which turns each song's
/// last-played date into a play.
struct MediaPlayerListeningSourceTests {
    private typealias T = ListeningTime

    @Test func eachPlayedSongGivesOneExactPlayAtItsLastPlay() async throws {
        let library = FakeMusicLibrary([
            .fixture(1, lastPlayed: T.hours(3), count: 2),
            .fixture(2, count: 0),
            .fixture(3, catalogID: "99", lastPlayed: T.hours(1), count: 8)
        ])
        let plays = try await MediaPlayerListeningSource(reader: library).plays(in: DateInterval(start: T.hours(0), end: T.hours(10)))
        #expect(plays.map(\.song.id) == ["99", "library-1"])
        #expect(plays.map(\.interval) == [DateInterval(start: T.hours(1), duration: 0), DateInterval(start: T.hours(3), duration: 0)])
        #expect(plays.allSatisfy { !$0.isEstimated })
    }

    @Test func playsOutsideTheIntervalAreLeftOut() async throws {
        let library = FakeMusicLibrary([.fixture(1, lastPlayed: T.hours(3), count: 1), .fixture(2, lastPlayed: T.hours(30), count: 1)])
        let plays = try await MediaPlayerListeningSource(reader: library).plays(in: DateInterval(start: T.hours(0), end: T.hours(10)))
        #expect(plays.map(\.song.id) == ["library-1"])
    }

    @Test func noAccessThrows() async {
        await #expect(throws: ListeningSourceError.noAccess) {
            try await MediaPlayerListeningSource(reader: FakeMusicLibrary(nil)).plays(in: DateInterval(start: T.hours(0), end: T.hours(10)))
        }
    }
}
