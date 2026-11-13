import Foundation
import Testing
@testable import Caffy

/// Tests for `LibraryAdditionsReport`, the go/no-go report on filling era
/// playlists from songs' `dateAdded`, and the `LibraryAdditions` steps it runs.
struct LibraryAdditionsReportTests {
    private typealias T = ListeningTime
    private typealias Window = LibraryAdditions.EraWindow

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let now = T.days(400)

    /// A long home era with a trip inside it, both past, then the current era.
    private static let home = Window(id: "home", title: "Home", start: T.days(0), end: T.days(200), isTrip: false)
    private static let trip = Window(id: "trip", title: "Trip", start: T.days(50), end: T.days(57), isTrip: true)
    private static let late = Window(id: "late", title: "Late", start: T.days(210), end: now, isTrip: false)
    private static let eras = [home, trip, late]

    /// 80 songs added on day 20, played 1 to 80 times: a bulk import.
    private static let bulk: [LibrarySongSnapshot] = (0..<80).map {
        .fixture(UInt64(1000 + $0), count: $0 + 1, added: T.days(20).addingTimeInterval(Double($0) * 60))
    }

    /// One album added whole on day 100, over a few hours, played 10 to 5 times.
    private static let album: [LibrarySongSnapshot] = (0..<6).map {
        .fixture(UInt64(2000 + $0), count: 10 - $0, added: T.days(100).addingTimeInterval(Double($0) * T.hour), album: 7)
    }

    private static let duringTrip = LibrarySongSnapshot.fixture(1, count: 3, added: T.days(52))
    /// Inside the home era, and in the trip's lead-in: the home era wins,
    /// because its own dates contain it.
    private static let beforeTrip = LibrarySongSnapshot.fixture(5, count: 2, added: T.days(48))
    /// In the late era's lead-in, after the home era ended.
    private static let beforeLate = LibrarySongSnapshot.fixture(2, count: 4, added: T.days(208.5))
    /// Between eras, out of any lead-in.
    private static let between = LibrarySongSnapshot.fixture(3, count: 4, added: T.days(205))
    private static let atHome = LibrarySongSnapshot.fixture(4, count: 2, added: T.days(30))
    private static let neverPlayed = LibrarySongSnapshot.fixture(6, added: T.days(30).addingTimeInterval(T.hour))
    private static let undated: [LibrarySongSnapshot] = [.fixture(7, count: 5), .fixture(8, count: 5)]

    private static let library: [LibrarySongSnapshot] =
        bulk + album + [duringTrip, beforeTrip, beforeLate, between, atHome, neverPlayed] + undated

    private static func report(
        songs: [LibrarySongSnapshot] = library,
        eras: [Window] = eras,
        config: EraBuildConfig = .standard
    ) -> LibraryAdditionsReport {
        LibraryAdditionsReport(songs: songs, eras: eras, now: now, calendar: calendar, config: config)
    }

    private static func row(_ id: String, in report: LibraryAdditionsReport) throws -> LibraryAdditionsReport.EraRow {
        try #require(report.eras.first { $0.era.id == id })
    }

    // MARK: - Library

    @Test func countsDatesAdded() {
        let report = Self.report()
        #expect(report.librarySongs == 94)
        #expect(report.songsWithDateAdded == 92)
        #expect(report.songsWithoutDateAdded == 2)
        #expect(report.earliestAdded == T.days(20))
        #expect(report.latestAdded == T.days(208.5))
    }

    @Test func countsAdditionsPerDay() {
        let report = Self.report()
        let day = { Self.calendar.startOfDay(for: T.days($0)) }
        #expect(report.topDays.map(\.count) == [80, 6, 2, 1, 1, 1, 1])
        #expect(report.topDays.map(\.day) == [day(20), day(100), day(30), day(48), day(52), day(205), day(208.5)])
        #expect(report.bulkDays == [day(20)])
        #expect(report.biggestDay?.count == 80)
        #expect(report.biggestDayShare == 80.0 / 94.0)
    }

    @Test func countsAdditionsPerMonthIncludingEmptyMonths() throws {
        let report = Self.report()
        #expect(report.months.count == LibraryAdditionsReport.monthsShown)
        #expect(report.months.map(\.month) == report.months.map(\.month).sorted())
        #expect(report.months.reduce(0) { $0 + $1.count } == 92)
        #expect(report.months.contains { $0.count == 0 })
        let bulkMonth = try #require(Self.calendar.dateInterval(of: .month, for: T.days(20))?.start)
        #expect(try #require(report.months.first { $0.month == bulkMonth }).count >= 80)
    }

    // MARK: - Eras

    @Test func countsEachStepPerEra() throws {
        let report = Self.report()
        let home = try Self.row("home", in: report)
        // Bulk day, album, one song at home, one just before the trip and
        // one never played.
        #expect(home.raw == 89)
        #expect(home.played == 88)
        // The bulk day keeps 5.
        #expect(home.afterBulkDays == 5 + 6 + 2)
        // The album keeps 2.
        #expect(home.afterAlbums == 5 + 2 + 2)
        // No cap: every song left is kept.
        #expect(home.songs.count == home.afterAlbums)
        #expect(home.isPast)
    }

    @Test func bulkDaysKeepTheirMostPlayed() throws {
        let home = try Self.row("home", in: Self.report())
        let kept = home.songs.map(\.snapshot.persistentID).filter { $0 >= 1000 && $0 < 2000 }
        #expect(Set(kept) == [1075, 1076, 1077, 1078, 1079])
    }

    @Test func albumAddsKeepTheirMostPlayedTracks() throws {
        let home = try Self.row("home", in: Self.report())
        let kept = home.songs.map(\.snapshot.persistentID).filter { $0 >= 2000 }
        #expect(Set(kept) == [2000, 2001])
    }

    @Test func albumTracksAddedFarApartAreSeparateAdds() {
        let spread: [LibrarySongSnapshot] = (0..<4).map {
            .fixture(UInt64(3000 + $0), count: 3, added: T.days(10 + 3 * Double($0)), album: 9)
        }
        let filtered = LibraryAdditions.filtered(library: spread, calendar: Self.calendar)
        #expect(filtered.afterAlbums.count == 4)
    }

    @Test func nestedTripsTakeOnlyAdditionsDuringThem() throws {
        let report = Self.report()
        let trip = try Self.row("trip", in: report)
        #expect(trip.songs.map(\.snapshot.persistentID) == [1])
        // Added just before the trip, inside the home era's dates.
        let home = try Self.row("home", in: report)
        #expect(home.songs.contains { $0.snapshot.persistentID == 5 })
    }

    @Test func leadInReachesTheLaterEraButNotBeyond() throws {
        let report = Self.report()
        let late = try Self.row("late", in: report)
        #expect(late.songs.map(\.snapshot.persistentID) == [2])
        #expect(!late.isPast)
        // Added on day 205: after the home era, before the late era's lead-in.
        #expect(!report.eras.contains { $0.songs.contains { $0.snapshot.persistentID == 3 } })
    }

    @Test func theContainingEraWinsOverALaterLeadIn() {
        let first = Window(id: "a", start: T.days(0), end: T.days(30), isTrip: false)
        let second = Window(id: "b", start: T.days(31), end: T.days(60), isTrip: false)
        #expect(LibraryAdditions.era(for: T.days(29), in: [first, second])?.id == "a")
        #expect(LibraryAdditions.era(for: T.days(30.5), in: [first, second])?.id == "b")
    }

    @Test func noSongIsInTwoEras() {
        let report = Self.report()
        let ids = report.eras.flatMap { $0.songs.map(\.snapshot.persistentID) }
        #expect(ids.count == Set(ids).count)
    }

    @Test func songsWithoutADateAddedOrPlaysAreInNoEra() {
        let report = Self.report()
        let ids = Set(report.eras.flatMap { $0.songs.map(\.snapshot.persistentID) })
        #expect(ids.isDisjoint(with: [6, 7, 8]))
    }

    @Test func everyFilteredAdditionIsKeptBestFirst() throws {
        let home = try Self.row("home", in: Self.report())
        #expect(home.songs.count == 9)
        #expect(home.songs.prefix(3).map(\.snapshot.persistentID) == [1079, 1078, 1077])
    }

    @Test func skipsLowerAScoreAndTripsRaiseIt() {
        let played = LibrarySongSnapshot.fixture(1, count: 9)
        let skipped = LibrarySongSnapshot.fixture(2, count: 9, skips: 9)
        #expect(LibraryAdditions.score(skipped) < LibraryAdditions.score(played))
        #expect(LibraryAdditions.score(played, isTrip: true) == LibraryAdditions.score(played) * 1.5)
    }

    @Test func isDeterministic() {
        #expect(Self.report() == Self.report())
        #expect(Self.report(songs: Self.library.reversed()).eras == Self.report().eras)
        let candidates = { LibraryAdditions.candidates(eras: Self.eras, library: Self.library, calendar: Self.calendar) }
        #expect(candidates() == candidates())
    }

    // MARK: - Text

    @Test func summarisesPastEras() {
        let report = Self.report()
        #expect(report.pastEras == 2)
        #expect(report.filledPastEras == 1)
        #expect(report.text.contains("Past eras with ≥ 5 songs: 1 of 2"))
    }

    @Test func warnsWhenOneDayHoldsMuchOfTheLibrary() {
        #expect(Self.report().text.contains("may have been reset"))
        // One song a day.
        let small = Self.report(songs: [Self.atHome, Self.beforeTrip, Self.duringTrip, Self.between, Self.beforeLate] + Self.undated)
        #expect(!small.text.contains("may have been reset"))
    }

    @Test func showsEraRows() {
        let text = Self.report().text
        #expect(text.contains("Home · home · "))
        #expect(text.contains("Trip · trip · "))
        #expect(text.contains("  89 / 88 / 13 / 9\n"))
        #expect(text.contains("1. Song 1079 – Artist 1079 (80 plays)"))
        #expect(text.contains("– now"))
    }

    @Test func withoutErasSaysToSyncFirst() {
        #expect(Self.report(eras: []).text.contains("No saved eras yet"))
    }
}
