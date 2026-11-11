import Foundation
import Testing
@testable import Caffy

/// Tests for `ListeningProfile`, which sums up listening and measures how
/// much it changed.
struct ListeningProfileTests {
    private static func plays(_ artist: String, genre: String? = "Pop", count: Int, track: Int = 1) -> [ListeningEvent] {
        (0..<count).map { index in
            ListeningEvent(
                song: Song(id: "\(artist)-\(track)", title: "Track \(track)", artist: artist, genre: genre),
                interval: DateInterval(start: Date(timeIntervalSince1970: Double(index) * 300), duration: 200)
            )
        }
    }

    @Test func countsPlaysByArtistGenreAndSong() {
        let profile = ListeningProfile(
            Self.plays("Tame Impala", genre: "Psychedelic", count: 3)
                + Self.plays("Tame Impala", genre: "Psychedelic", count: 1, track: 2)
                + Self.plays("Fred again..", genre: nil, count: 2)
        )
        #expect(profile.playCount == 6)
        #expect(profile.artistPlays == ["Tame Impala": 4, "Fred again..": 2])
        #expect(profile.genrePlays == ["Psychedelic": 4])
        #expect(profile.songPlays == ["Tame Impala-1": 3, "Tame Impala-2": 1, "Fred again..-1": 2])
    }

    @Test func sameMixIsNoChange() {
        let a = ListeningProfile(Self.plays("A", count: 4) + Self.plays("B", count: 2))
        let b = ListeningProfile(Self.plays("A", count: 8) + Self.plays("B", count: 4))
        #expect(abs(a.distance(to: b)) < 1e-12)
    }

    @Test func nothingInCommonIsFullChange() {
        let a = ListeningProfile(Self.plays("A", genre: "Rock", count: 5))
        let b = ListeningProfile(Self.plays("B", genre: "Jazz", count: 5))
        #expect(a.distance(to: b) == 1)
    }

    @Test func newArtistInTheSameGenreIsHalfAChange() {
        let a = ListeningProfile(Self.plays("A", genre: "Rock", count: 5))
        let b = ListeningProfile(Self.plays("B", genre: "Rock", count: 5))
        #expect(abs(a.distance(to: b) - 0.5) < 1e-12)
    }

    @Test func withoutGenresOnlyArtistsCount() {
        let a = ListeningProfile(Self.plays("A", genre: nil, count: 5))
        let b = ListeningProfile(Self.plays("B", genre: "Rock", count: 5))
        #expect(a.distance(to: b) == 1)
    }

    @Test func emptyListeningIsNoChange() {
        let some = ListeningProfile(Self.plays("A", count: 5))
        let none = ListeningProfile([ListeningEvent]())
        #expect(some.distance(to: none) == 0)
        #expect(none.distance(to: some) == 0)
    }

    @Test func distanceIsSymmetricAndInRange() {
        let a = ListeningProfile(Self.plays("A", count: 7) + Self.plays("B", genre: "Rock", count: 3))
        let b = ListeningProfile(Self.plays("A", count: 2) + Self.plays("C", genre: "Jazz", count: 6))
        let distance = a.distance(to: b)
        #expect(distance > 0 && distance < 1)
        #expect(abs(distance - b.distance(to: a)) < 1e-12)
    }

    @Test func topArtistsAreMostPlayedThenByName() {
        let profile = ListeningProfile(Self.plays("B", count: 3) + Self.plays("A", count: 3) + Self.plays("C", count: 5))
        #expect(profile.topArtists(2).map(\.artist) == ["C", "A"])
        #expect(profile.topArtists(10).map(\.plays) == [5, 3, 3])
    }
}
