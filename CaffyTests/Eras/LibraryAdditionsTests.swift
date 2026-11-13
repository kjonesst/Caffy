import Foundation
import Testing
@testable import Caffy

/// Tests for `LibraryAdditions`, the stage that picks each era's songs from
/// when they were added to the library.
struct LibraryAdditionsTests {
    private typealias T = ListeningTime
    private typealias Window = LibraryAdditions.EraWindow

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func home(_ id: String, from start: Double, to end: Double) -> Window {
        Window(id: id, start: T.days(start), end: T.days(end), isTrip: false)
    }

    private static func trip(_ id: String, from start: Double, to end: Double) -> Window {
        Window(id: id, start: T.days(start), end: T.days(end), isTrip: true)
    }

    private static func ids(
        _ eras: [Window],
        _ library: [LibrarySongSnapshot],
        config: EraBuildConfig = .standard
    ) -> [String: [UInt64]] {
        LibraryAdditions.candidates(eras: eras, library: library, calendar: calendar, config: config)
            .mapValues { $0.map(\.snapshot.persistentID) }
    }

    // MARK: - Assigning

    @Test func songsInsideTheLeadInAndTheEraAreAssigned() {
        let era = Self.home("a", from: 10, to: 20)
        let library: [LibrarySongSnapshot] = [
            .fixture(1, count: 1, added: T.days(6)),     // before the lead-in
            .fixture(2, count: 1, added: T.days(7.5)),   // in the lead-in
            .fixture(3, count: 1, added: T.days(15)),    // in the era
            .fixture(4, count: 1, added: T.days(20.5))   // after it
        ]
        #expect(Set(Self.ids([era], library)["a"] ?? []) == [2, 3])
    }

    @Test func overlappingLeadInsGoToTheContainingEraElseTheLaterOne() {
        let first = Self.home("a", from: 0, to: 30)
        let second = Self.home("b", from: 31, to: 60)
        let library: [LibrarySongSnapshot] = [
            .fixture(1, count: 1, added: T.days(29)),    // in a, and in b's lead-in
            .fixture(2, count: 1, added: T.days(30.5))   // only in b's lead-in
        ]
        #expect(Self.ids([first, second], library) == ["a": [1], "b": [2]])

        // Neither era contains it: both reach it only through their lead-in.
        // The shorter one wins.
        let short = Self.home("c", from: 10, to: 20)
        let long = Self.home("d", from: 11, to: 30)
        #expect(Self.ids([short, long], [.fixture(3, count: 1, added: T.days(8.5))]) == ["c": [3]])
        // As long as each other: the later one wins.
        let early = Self.home("e", from: 10, to: 20)
        let later = Self.home("f", from: 11, to: 21)
        #expect(Self.ids([early, later], [.fixture(4, count: 1, added: T.days(8.5))]) == ["f": [4]])
    }

    @Test func aNestedTripTakesOnlyItsOwnDates() {
        let home = Self.home("home", from: 0, to: 100)
        let trip = Self.trip("trip", from: 40, to: 45)
        let library: [LibrarySongSnapshot] = [
            .fixture(1, count: 1, added: T.days(38)),    // just before the trip
            .fixture(2, count: 1, added: T.days(42)),    // during it
            .fixture(3, count: 1, added: T.days(46)),    // the day after it
            .fixture(4, count: 1, added: T.days(50))     // well after it
        ]
        let ids = Self.ids([home, trip], library)
        #expect(ids["trip"] == [2])
        #expect(ids["home"] == [1, 3, 4])
    }

    @Test func theShortestContainingEraWins() {
        let long = Self.home("long", from: 0, to: 100)
        let short = Self.home("short", from: 20, to: 40)
        let library: [LibrarySongSnapshot] = [
            .fixture(1, count: 1, added: T.days(30)),
            .fixture(2, count: 1, added: T.days(50))
        ]
        #expect(Self.ids([long, short], library) == ["short": [1], "long": [2]])
    }

    @Test func aSongIsNeverInTwoEras() {
        let eras = [
            Self.home("a", from: 0, to: 30), Self.trip("t", from: 10, to: 14),
            Self.home("b", from: 31, to: 60), Self.home("c", from: 58, to: 90)
        ]
        let library = (0..<90).map { LibrarySongSnapshot.fixture(UInt64($0 + 1), count: 2, added: T.days(Double($0) + 0.5)) }
        let assigned = Self.ids(eras, library).values.flatMap { $0 }
        #expect(assigned.count == Set(assigned).count)
        #expect(assigned.count == 90)
    }

    // MARK: - Filtering

    @Test func bulkDaysKeepOnlyTheirMostPlayed() {
        let era = Self.home("a", from: 0, to: 30)
        func day(_ count: Int) -> [LibrarySongSnapshot] {
            (0..<count).map { .fixture(UInt64($0 + 1), count: $0 + 1, added: T.days(5).addingTimeInterval(Double($0) * 60)) }
        }
        // At the threshold (75), nothing is dropped.
        #expect(Self.ids([era], day(75))["a"]?.count == 75)
        // Over it, only the five most played stay, best first.
        #expect(Self.ids([era], day(76))["a"] == [76, 75, 74, 73, 72])
    }

    @Test func albumAddsKeepTheirMostPlayedTracks() {
        let era = Self.home("a", from: 0, to: 30)
        let library: [LibrarySongSnapshot] = (0..<4).map {
            .fixture(UInt64($0 + 1), count: [3, 9, 1, 7][$0], added: T.days(5).addingTimeInterval(Double($0) * T.hour), album: 3)
        } + [
            .fixture(10, count: 1, added: T.days(6)),
            .fixture(11, count: 1, added: T.days(6.1))
        ]
        // Two tracks from the album, and both songs without one.
        #expect(Self.ids([era], library)["a"] == [2, 4, 10, 11])
    }

    @Test func songsWithoutPlaysOrADateAddedAreLeftOut() {
        let era = Self.home("a", from: 0, to: 30)
        let library: [LibrarySongSnapshot] = [
            .fixture(1, count: 0, added: T.days(5)),
            .fixture(2, count: 5),
            .fixture(3, count: 1, added: T.days(5))
        ]
        #expect(Self.ids([era], library) == ["a": [3]])
    }

    // MARK: - Ranking

    @Test func rankingFavoursPlaysAndPenalisesSkips() {
        let era = Self.home("a", from: 0, to: 30)
        let library: [LibrarySongSnapshot] = [
            .fixture(1, count: 4, added: T.days(1)),
            .fixture(2, count: 9, added: T.days(2)),
            .fixture(3, count: 9, added: T.days(3), skips: 20),
            .fixture(4, count: 4, added: T.days(4))
        ]
        // A tie (1 and 4) goes to the earlier addition.
        #expect(Self.ids([era], library)["a"] == [2, 1, 4, 3])
    }

    @Test func tripsBoostTheirSongs() throws {
        let home = Self.home("home", from: 0, to: 100)
        let trip = Self.trip("trip", from: 40, to: 45)
        let atHome = LibrarySongSnapshot.fixture(1, count: 5, added: T.days(10))
        let away = LibrarySongSnapshot.fixture(2, count: 5, added: T.days(42))
        let candidates = LibraryAdditions.candidates(eras: [home, trip], library: [atHome, away], calendar: Self.calendar)
        let homeScore = try #require(candidates["home"]?.first?.score)
        let tripScore = try #require(candidates["trip"]?.first?.score)
        #expect(abs(tripScore - homeScore * 1.5) < 1e-9)

        // Without the boost, a slightly more played home song would beat a
        // trip song in a shared ranking; with it, the trip song comes first.
        let boosted = LibraryAdditions.ranked([away], isTrip: true).first!.score
        let plain = LibraryAdditions.ranked([.fixture(3, count: 7, added: T.days(10))]).first!.score
        #expect(boosted > plain)
    }

    @Test func thereIsNoCap() {
        let era = Self.home("a", from: 0, to: 70)
        let library = (0..<60).map { LibrarySongSnapshot.fixture(UInt64($0 + 1), count: $0 + 1, added: T.days(Double($0) + 0.5)) }
        let ids = Self.ids([era], library)["a"] ?? []
        #expect(ids.count == 60)
        #expect(ids == (1...60).reversed().map(UInt64.init))
    }

    @Test func theOutputIsDeterministic() {
        let eras = [Self.home("a", from: 0, to: 30), Self.trip("t", from: 10, to: 14), Self.home("b", from: 31, to: 60)]
        let library = (0..<60).map {
            LibrarySongSnapshot.fixture(UInt64($0 + 1), count: $0 % 5 + 1, added: T.days(Double($0)), album: $0 % 3 == 0 ? 7 : nil)
        }
        let run = { LibraryAdditions.candidates(eras: eras, library: library, calendar: Self.calendar) }
        #expect(run() == run())
        #expect(LibraryAdditions.candidates(eras: eras.reversed(), library: library.reversed(), calendar: Self.calendar) == run())
    }
}
