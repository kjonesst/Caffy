import Foundation
import Testing
@testable import Caffy

/// Tests for `PlayHistoryDiff`, which works out the plays between two reads
/// of a library song.
struct PlayHistoryDiffTests {
    private typealias T = ListeningTime
    private static let threeDays = EraBuildConfig.standard.maxEstimatedPlayWindow

    private static func diff(
        _ previous: PlayHistoryDiff.State?,
        _ current: LibrarySongSnapshot,
        previousCheck: Date? = nil,
        now: Date = T.hours(100),
        maxWindow: TimeInterval = threeDays
    ) -> [ListeningEvent] {
        PlayHistoryDiff.newPlays(previous: previous, current: current, previousCheck: previousCheck, now: now, maxEstimatedWindow: maxWindow)
    }

    private static func state(_ lastPlayed: Date?, _ count: Int) -> PlayHistoryDiff.State {
        PlayHistoryDiff.State(lastPlayedDate: lastPlayed, playCount: count)
    }

    private static func instant(_ date: Date) -> DateInterval {
        DateInterval(start: date, duration: 0)
    }

    // MARK: - First sighting

    @Test func firstSightingRecordsTheLastPlay() {
        let plays = Self.diff(nil, .fixture(1, lastPlayed: T.hours(2), count: 9))
        #expect(plays.map(\.interval) == [Self.instant(T.hours(2))])
        #expect(plays.allSatisfy { !$0.isEstimated && $0.isMatchable })
    }

    @Test func neverPlayedSongRecordsNothing() {
        #expect(Self.diff(nil, .fixture(1)).isEmpty)
    }

    // MARK: - Date moved forward

    @Test func onePlayIsExact() {
        let plays = Self.diff(Self.state(T.hours(0), 4), .fixture(1, lastPlayed: T.hours(5), count: 5), previousCheck: T.hours(1))
        #expect(plays.map(\.interval) == [Self.instant(T.hours(5))])
        #expect(!plays[0].isEstimated)
    }

    @Test func extraPlaysAreSplitBetweenTheLastReadAndTheLastPlay() {
        let plays = Self.diff(Self.state(T.hours(0), 4), .fixture(1, lastPlayed: T.hours(5), count: 7), previousCheck: T.hours(1))
        #expect(plays.map(\.interval) == [
            Self.instant(T.hours(5)),
            DateInterval(start: T.hours(1), end: T.hours(3)),
            DateInterval(start: T.hours(3), end: T.hours(5))
        ])
        #expect(plays.map(\.isEstimated) == [false, true, true])
        #expect(plays.allSatisfy { $0.isMatchable })
    }

    @Test func playThatSyncedLateFallsAfterTheOldLastPlay() {
        // Read at 6:00, but a play from another device at 5:00 only shows up
        // afterwards: the earlier play fell after the old last play at 0:00.
        let plays = Self.diff(Self.state(T.hours(0), 4), .fixture(1, lastPlayed: T.hours(5), count: 6), previousCheck: T.hours(6))
        #expect(plays.map(\.interval) == [Self.instant(T.hours(5)), DateInterval(start: T.hours(0), end: T.hours(5))])
    }

    @Test func newDateWithoutANewCountIsOneExactPlay() {
        let plays = Self.diff(Self.state(T.hours(0), 4), .fixture(1, lastPlayed: T.hours(5), count: 4), previousCheck: T.hours(1))
        #expect(plays.map(\.interval) == [Self.instant(T.hours(5))])
    }

    @Test func firstPlayOfASongSeenBefore() {
        let plays = Self.diff(Self.state(nil, 0), .fixture(1, lastPlayed: T.hours(5), count: 1), previousCheck: T.hours(1))
        #expect(plays.map(\.interval) == [Self.instant(T.hours(5))])
    }

    // MARK: - Count only

    @Test func countUpWithoutANewDateIsEstimatedUntilNow() {
        let plays = Self.diff(Self.state(T.hours(0), 4), .fixture(1, lastPlayed: T.hours(0), count: 6), previousCheck: T.hours(2), now: T.hours(10))
        #expect(plays.map(\.interval) == [
            DateInterval(start: T.hours(2), end: T.hours(6)),
            DateInterval(start: T.hours(6), end: T.hours(10))
        ])
        #expect(plays.allSatisfy { $0.isEstimated })
    }

    // MARK: - Nothing new, or a reset

    @Test func unchangedSongRecordsNothing() {
        #expect(Self.diff(Self.state(T.hours(0), 4), .fixture(1, lastPlayed: T.hours(0), count: 4), previousCheck: T.hours(1)).isEmpty)
    }

    @Test func countThatFellRecordsNothing() {
        #expect(Self.diff(Self.state(T.hours(0), 4), .fixture(1, lastPlayed: T.hours(5), count: 1), previousCheck: T.hours(1)).isEmpty)
    }

    @Test func dateThatWentBackRecordsNothing() {
        #expect(Self.diff(Self.state(T.hours(5), 4), .fixture(1, lastPlayed: T.hours(2), count: 6), previousCheck: T.hours(6)).isEmpty)
    }

    @Test func dateThatDisappearedRecordsNothing() {
        #expect(Self.diff(Self.state(T.hours(5), 4), .fixture(1, count: 6), previousCheck: T.hours(6)).isEmpty)
    }

    // MARK: - Splitting and the window cap

    @Test func equalPartsWeighTheSameAsCopiesOfTheWholeWindow() {
        let window = DateInterval(start: T.hours(1), end: T.hours(7))
        let song = Song(id: "a", title: "A", artist: "A")
        let parts = PlayHistoryDiff.estimated(song, count: 3, over: window, maxWindow: Self.threeDays)
        // A moment's match window, overlapping the plays' window partly.
        let moment = DateInterval(start: T.hours(5), end: T.hours(6.5))
        let split = parts.map { MusicMatcher.weight(of: $0.interval, around: moment, config: .standard) }.reduce(0, +)
        let copies = 3 * MusicMatcher.weight(of: window, around: moment, config: .standard)
        #expect(abs(split - copies) < 1e-9)
        #expect(parts.map(\.interval.duration) == [2 * T.hour, 2 * T.hour, 2 * T.hour])
    }

    @Test func windowsLongerThanTheCapCantBeMatched() {
        let long = Self.diff(Self.state(T.days(0), 1), .fixture(1, lastPlayed: T.days(10), count: 3), previousCheck: T.days(0.5))
        let short = Self.diff(Self.state(T.days(0), 1), .fixture(1, lastPlayed: T.days(2), count: 3), previousCheck: T.days(0.5))
        #expect(long.filter(\.isEstimated).allSatisfy { !$0.isMatchable })
        #expect(long.filter { !$0.isEstimated }.allSatisfy { $0.isMatchable })
        #expect(short.allSatisfy { $0.isMatchable })
    }

    // MARK: - Song ids

    @Test func songIDIsTheCatalogIDWhenThereIsOne() {
        #expect(LibrarySongSnapshot.fixture(7, catalogID: "1440833098").song.id == "1440833098")
        #expect(LibrarySongSnapshot.fixture(7).song.id == "library-7")
    }

    @Test(arguments: ["", "0"])
    func placeholderCatalogIDsFallBackToTheLibraryID(catalogID: String) {
        let song = LibrarySongSnapshot.fixture(7, catalogID: catalogID)
        #expect(song.catalogID == nil)
        #expect(song.song.id == "library-7")
    }
}
