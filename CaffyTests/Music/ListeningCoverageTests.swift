import Foundation
import Testing
@testable import Caffy

/// Tests for `ListeningCoverage`, the go/no-go report on how well real
/// listening covers photo moments.
struct ListeningCoverageTests {
    private typealias T = ListeningTime

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let now = T.days(40)

    /// A moment `daysAgo` days before `now`.
    private static func moment(_ id: String, daysAgo: Double) -> PhotoMoment {
        let start = now.addingTimeInterval(-daysAgo * T.day)
        return PhotoMoment(id: id, start: start, end: start.addingTimeInterval(10 * 60), photoIDs: [id], coverID: id, coverAspectRatio: 1, coordinate: nil)
    }

    private static let recent = moment("recent", daysAgo: 2)
    private static let lastMonth = moment("lastMonth", daysAgo: 10)
    private static let old = moment("old", daysAgo: 100)
    private static let moments = [recent, lastMonth, old]

    private static func play(_ songID: String, at date: Date) -> ListeningEvent {
        ListeningEvent(song: Song(id: songID, title: songID, artist: songID), interval: DateInterval(start: date, duration: 0))
    }

    /// The library: one song last played during the recent moment, one never
    /// played, one not in the catalog played long ago.
    private static let songs: [LibrarySongSnapshot] = [
        .fixture(1, catalogID: "a", lastPlayed: recent.start.addingTimeInterval(5 * 60), count: 3),
        .fixture(2, catalogID: "b"),
        .fixture(3, lastPlayed: now.addingTimeInterval(-200 * T.day), count: 1)
    ]

    /// Recorded history: plays near both recent moments.
    private static let recorded = [
        play("x", at: lastMonth.start.addingTimeInterval(-10 * 60)),
        play("a", at: recent.start.addingTimeInterval(5 * 60))
    ]

    private static func coverage(recorded: [ListeningEvent] = recorded, recordingDays: Double? = 20, moments: [PhotoMoment] = moments) -> ListeningCoverage {
        ListeningCoverage(
            moments: moments,
            songs: songs,
            recordedPlays: recorded,
            recordingSince: recordingDays.map { now.addingTimeInterval(-$0 * T.day) },
            libraryReads: 12,
            now: now,
            calendar: calendar
        )
    }

    @Test func countsTheLibrary() {
        let report = Self.coverage()
        #expect(report.hasMusicAccess)
        #expect(report.librarySongs == 3)
        #expect(report.songsWithLastPlayed == 2)
        #expect(report.songsWithoutCatalogID == 1)
        #expect(report.lastPlayedAges == [.week: 1, .year: 1])
    }

    @Test func comparesLastPlayedWithRecordedHistory() {
        let report = Self.coverage()
        // Last-played dates only reach the recent moment.
        #expect(report.lastPlayedMatches[.week] == ListeningCoverage.MatchCounts(near: 1))
        #expect(report.lastPlayedMatches[.month] == ListeningCoverage.MatchCounts(none: 1))
        // Recorded history reaches last month's too.
        #expect(report.recordedMatches[.week] == ListeningCoverage.MatchCounts(near: 1))
        #expect(report.recordedMatches[.month] == ListeningCoverage.MatchCounts(near: 1))
        #expect(report.recordedMatches[.year] == ListeningCoverage.MatchCounts(none: 1))
    }

    @Test func sameDayOnlyCountsAsLoose() {
        let sameDay = Self.play("y", at: Self.calendar.startOfDay(for: Self.lastMonth.start).addingTimeInterval(60))
        let report = Self.coverage(recorded: [sameDay], moments: [Self.lastMonth])
        #expect(report.recordedMatches[.month] == ListeningCoverage.MatchCounts(looseOnly: 1))
    }

    @Test func countsRecordedPlays() {
        let vague = ListeningEvent(
            song: Song(id: "z", title: "z", artist: "z"),
            interval: DateInterval(start: T.days(1), end: T.days(9)),
            isEstimated: true,
            isMatchable: false
        )
        let report = Self.coverage(recorded: Self.recorded + [vague])
        #expect(report.exactPlays == 2)
        #expect(report.estimatedPlays == 1)
        #expect(report.unmatchablePlays == 1)
    }

    // MARK: - Verdict

    @Test func passesWhenMostRecentMomentsHaveSongsNearThem() {
        #expect(Self.coverage().verdict == .pass(nearShare: 1))
        #expect(Self.coverage().text.contains("VERDICT: Pass (100% near)"))
    }

    @Test func failsWhenFewRecentMomentsHaveSongsNearThem() {
        #expect(Self.coverage(recorded: []).verdict == .fail(nearShare: 0))
    }

    @Test func borderlineInBetween() {
        let quiet = (0..<3).map { Self.moment("quiet\($0)", daysAgo: 5 + Double($0)) }
        let report = Self.coverage(moments: [Self.recent] + quiet)
        #expect(report.verdict == .borderline(nearShare: 0.25))
    }

    @Test func tooEarlyBeforeTwoWeeksOfRecording() {
        #expect(Self.coverage(recordingDays: 3).verdict == .tooEarly(daysRecorded: 3))
        #expect(Self.coverage(recordingDays: nil).verdict == .tooEarly(daysRecorded: 0))
    }

    @Test func noVerdictWithoutRecentMoments() {
        #expect(Self.coverage(moments: [Self.old]).verdict == .noRecentMoments)
    }

    @Test func withoutMusicAccessTheLibraryIsEmpty() {
        let report = ListeningCoverage(
            moments: Self.moments, songs: nil, recordedPlays: [], recordingSince: nil,
            libraryReads: 0, now: Self.now, calendar: Self.calendar
        )
        #expect(!report.hasMusicAccess)
        #expect(report.librarySongs == 0)
        #expect(report.text.contains("Music access: no"))
    }
}
