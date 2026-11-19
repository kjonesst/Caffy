import Foundation
import SwiftData
import Testing
@testable import Caffy

/// Tests for `ListeningRecorder`, `RecordedListeningSource` and
/// `ListeningHistoryStore`: building listening history from library reads.
/// Each test uses its own in-memory database with both stores.
@MainActor
struct ListeningRecorderTests {
    private typealias T = ListeningTime

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try CaffyStore.makeContainer(inMemory: true)
    }

    private func recordedPlays() throws -> [RecordedPlay] {
        try context.fetch(FetchDescriptor<RecordedPlay>(sortBy: [SortDescriptor(\.start)]))
    }

    private func sourcePlays() async throws -> [ListeningEvent] {
        try await RecordedListeningSource(container: container).plays(in: DateInterval(start: .distantPast, end: .distantFuture))
    }

    // MARK: - Recording

    @Test func recordsPlaysBetweenReads() async throws {
        let library = FakeMusicLibrary([.fixture(1, lastPlayed: T.hours(0), count: 5), .fixture(2, count: 0)])
        let recorder = ListeningRecorder(modelContainer: container, reader: library)

        let first = await recorder.record(now: T.hours(1))
        #expect(first == RecordSummary(songCount: 2, newExactPlays: 0, newEstimatedPlays: 0, newSeededPlays: 1))

        await library.set([.fixture(1, lastPlayed: T.hours(9), count: 7), .fixture(2, lastPlayed: T.hours(4), count: 1)])
        let second = await recorder.record(now: T.hours(10))
        #expect(second == RecordSummary(songCount: 2, newExactPlays: 2, newEstimatedPlays: 1))

        let plays = try await sourcePlays()
        #expect(plays.map(\.song.id) == ["library-1", "library-1", "library-2", "library-1"])
        #expect(plays.map(\.interval) == [
            DateInterval(start: T.hours(0), duration: 0),
            DateInterval(start: T.hours(1), end: T.hours(9)),
            DateInterval(start: T.hours(4), duration: 0),
            DateInterval(start: T.hours(9), duration: 0)
        ])
        #expect(plays.map(\.isEstimated) == [false, true, false, false])
        #expect(plays.map(\.isSeeded) == [true, false, false, false])
    }

    // MARK: - Seeded plays

    @Test func firstPassOnlySeedsAndASecondPassObserves() async throws {
        let library = FakeMusicLibrary([
            .fixture(1, lastPlayed: T.hours(0), count: 5),
            .fixture(2, lastPlayed: T.hours(-30), count: 2),
            .fixture(3, count: 0)
        ])
        let recorder = ListeningRecorder(modelContainer: container, reader: library)

        let first = await recorder.record(now: T.hours(1))
        #expect(first == RecordSummary(songCount: 3, newExactPlays: 0, newEstimatedPlays: 0, newSeededPlays: 2))
        #expect(try recordedPlays().allSatisfy(\.isSeeded))
        let check = try #require(try context.fetch(FetchDescriptor<ListeningCheck>()).first)
        #expect(check.newSeededPlays == 2)
        #expect(check.newExactPlays == 0)

        await library.set([
            .fixture(1, lastPlayed: T.hours(5), count: 6),
            .fixture(2, lastPlayed: T.hours(-30), count: 2),
            .fixture(3, count: 0)
        ])
        let second = await recorder.record(now: T.hours(6))
        #expect(second == RecordSummary(songCount: 3, newExactPlays: 1, newEstimatedPlays: 0, newSeededPlays: 0))
        let observed = try recordedPlays().filter { !$0.isSeeded }
        #expect(observed.map(\.start) == [T.hours(5)])
        #expect(observed.allSatisfy { !$0.isEstimated })
    }

    @Test func migrationMarksOnlyPlaysFromBeforeRecordingOnce() throws {
        let song = Song(id: "s", title: "s", artist: "a")
        context.insert(LibrarySongState(key: "1", lastPlayedDate: T.hours(0), playCount: 1, firstSeenAt: T.hours(10)))
        context.insert(LibrarySongState(key: "2", lastPlayedDate: nil, playCount: 0, firstSeenAt: T.hours(20)))
        let before = ListeningEvent(song: song, interval: DateInterval(start: T.hours(0), duration: 0))
        let after = ListeningEvent(song: song, interval: DateInterval(start: T.hours(15), duration: 0))
        // An estimate that ends after recording began.
        let straddling = ListeningEvent(song: song, interval: DateInterval(start: T.hours(8), end: T.hours(12)), isEstimated: true)
        for event in [before, after, straddling] {
            context.insert(RecordedPlay(event, recordedAt: T.hours(20)))
        }
        try context.save()

        #expect(try ListeningHistoryStore.markSeededPlays(in: context) == 1)
        #expect(try recordedPlays().map(\.isSeeded) == [true, false, false])
        #expect(try ListeningHistoryStore.markSeededPlays(in: context) == 0)
        #expect(try recordedPlays().map(\.isSeeded) == [true, false, false])
    }

    @Test func migrationRunsOnceThenRemembers() throws {
        let defaults = try #require(UserDefaults(suiteName: "ListeningRecorderTests.\(UUID().uuidString)"))
        context.insert(LibrarySongState(key: "1", lastPlayedDate: T.hours(0), playCount: 1, firstSeenAt: T.hours(10)))
        let song = Song(id: "s", title: "s", artist: "a")
        context.insert(RecordedPlay(ListeningEvent(song: song, interval: DateInterval(start: T.hours(0), duration: 0)), recordedAt: T.hours(10)))
        try context.save()

        try ListeningHistoryStore.markSeededPlaysOnce(in: context, defaults: defaults)
        #expect(defaults.bool(forKey: ListeningHistoryStore.markSeededPlaysKey))
        #expect(try recordedPlays().map(\.isSeeded) == [true])

        // Once remembered, a play saved wrongly afterwards is left alone.
        context.insert(RecordedPlay(ListeningEvent(song: song, interval: DateInterval(start: T.hours(1), duration: 0)), recordedAt: T.hours(11)))
        try context.save()
        try ListeningHistoryStore.markSeededPlaysOnce(in: context, defaults: defaults)
        #expect(try recordedPlays().map(\.isSeeded) == [true, false])
    }

    @Test func recorderMarksOldHistoryBeforeItsPass() async throws {
        let defaults = try #require(UserDefaults(suiteName: "ListeningRecorderTests.\(UUID().uuidString)"))
        context.insert(LibrarySongState(key: "1", lastPlayedDate: T.hours(0), playCount: 1, firstSeenAt: T.hours(1)))
        context.insert(ListeningCheck(at: T.hours(1), songCount: 1, newExactPlays: 1, newEstimatedPlays: 0))
        let old = LibrarySongSnapshot.fixture(1, lastPlayed: T.hours(0), count: 1)
        context.insert(RecordedPlay(ListeningEvent(song: old.song, interval: DateInterval(start: T.hours(0), duration: 0)), recordedAt: T.hours(1)))
        try context.save()

        let recorder = ListeningRecorder(modelContainer: container, reader: FakeMusicLibrary([old]), defaults: defaults)
        await recorder.record(now: T.hours(2))
        // A fresh context, so the recorder's save is read rather than this
        // context's copy.
        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<RecordedPlay>()).map(\.isSeeded) == [true])
    }

    @Test func aDuplicateKeepsTheObservedPlay() {
        let song = Song(id: "s", title: "s", artist: "a")
        let at = DateInterval(start: T.hours(3), duration: 0)
        let seeded = ListeningEvent(song: song, interval: at, isSeeded: true)
        let observed = ListeningEvent(song: song, interval: at)
        #expect(RecordedListeningSource.unique([seeded, observed]) == [observed])
        #expect(RecordedListeningSource.unique([observed, seeded]) == [observed])
        #expect(RecordedListeningSource.unique([seeded, seeded]) == [seeded])
    }

    @Test func readingAgainWithNothingNewAddsNoPlays() async throws {
        let library = FakeMusicLibrary([.fixture(1, lastPlayed: T.hours(0), count: 5)])
        let recorder = ListeningRecorder(modelContainer: container, reader: library)
        await recorder.record(now: T.hours(1))
        let again = await recorder.record(now: T.hours(2))

        #expect(again?.newPlays == 0)
        #expect(try recordedPlays().count == 1)
        #expect(try context.fetchCount(FetchDescriptor<ListeningCheck>()) == 2)
    }

    @Test func overlappingCallsShareOnePass() async throws {
        let library = FakeMusicLibrary([.fixture(1, lastPlayed: T.hours(0), count: 5)])
        let recorder = ListeningRecorder(modelContainer: container, reader: library)
        async let first = recorder.record(now: T.hours(1))
        async let second = recorder.record(now: T.hours(1))
        _ = await (first, second)

        #expect(try recordedPlays().count == 1)
    }

    @Test func withoutAccessNothingIsRecorded() async throws {
        let recorder = ListeningRecorder(modelContainer: container, reader: FakeMusicLibrary(nil))
        #expect(await recorder.record(now: T.hours(1)) == nil)
        #expect(try context.fetchCount(FetchDescriptor<ListeningCheck>()) == 0)
    }

    @Test func newLibraryIDForTheSameCatalogSongGivesNoDuplicatePlay() async throws {
        let library = FakeMusicLibrary([.fixture(1, catalogID: "123", lastPlayed: T.hours(0), count: 5)])
        let recorder = ListeningRecorder(modelContainer: container, reader: library)
        await recorder.record(now: T.hours(1))

        // An iCloud Music Library resync gives the song a new persistent id.
        await library.set([.fixture(2, catalogID: "123", lastPlayed: T.hours(0), count: 5)])
        await recorder.record(now: T.hours(2))

        let plays = try await sourcePlays()
        #expect(plays.map(\.song.id) == ["123"])
        #expect(plays.map(\.interval) == [DateInterval(start: T.hours(0), duration: 0)])
    }

    @Test func vagueEstimatesComeBackUnmatchable() async throws {
        let library = FakeMusicLibrary([.fixture(1, lastPlayed: T.days(0), count: 1)])
        let recorder = ListeningRecorder(modelContainer: container, reader: library)
        await recorder.record(now: T.days(0.5))
        // Not opened for ten days.
        await library.set([.fixture(1, lastPlayed: T.days(10), count: 3)])
        await recorder.record(now: T.days(10.5))

        let plays = try await sourcePlays()
        let estimated = plays.filter(\.isEstimated)
        #expect(estimated.count == 1)
        #expect(estimated.allSatisfy { !$0.isMatchable })
        #expect(plays.filter { !$0.isEstimated }.allSatisfy { $0.isMatchable })

        // The matcher leaves the estimate out, so a moment on day 5 gets nothing.
        let moment = PhotoMoment(id: "m", start: T.days(5), end: T.days(5), photoIDs: ["m"], coverID: "m", coverAspectRatio: 1, coordinate: nil)
        var config = EraBuildConfig()
        config.dayFallbackMatching = false
        let matched = MusicMatcher.match([moment], with: plays, calendar: Calendar(identifier: .gregorian), config: config)
        #expect(matched.first?.songs.isEmpty == true)
    }

    @Test func sourceOnlyReturnsPlaysInTheInterval() async throws {
        let library = FakeMusicLibrary([.fixture(1, lastPlayed: T.hours(0), count: 1), .fixture(2, lastPlayed: T.hours(20), count: 1)])
        await ListeningRecorder(modelContainer: container, reader: library).record(now: T.hours(21))

        let plays = try await RecordedListeningSource(container: container).plays(in: DateInterval(start: T.hours(10), end: T.hours(30)))
        #expect(plays.map(\.song.id) == ["library-2"])
    }

    // MARK: - The history store

    @Test func clearingErasLeavesListeningHistory() async throws {
        let library = FakeMusicLibrary([.fixture(1, lastPlayed: T.hours(0), count: 1)])
        await ListeningRecorder(modelContainer: container, reader: library).record(now: T.hours(1))
        try await SampleData.insert(into: context)

        for model in CaffyStore.derivedModels {
            try context.delete(model: model)
        }
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Era>()) == 0)
        #expect(try recordedPlays().count == 1)
        #expect(try context.fetchCount(FetchDescriptor<LibrarySongState>()) == 1)
    }

    @Test func deleteAllClearsListeningHistory() async throws {
        let library = FakeMusicLibrary([.fixture(1, lastPlayed: T.hours(0), count: 1)])
        await ListeningRecorder(modelContainer: container, reader: library).record(now: T.hours(1))

        try ListeningHistoryStore.deleteAll(in: context)

        #expect(try recordedPlays().isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<LibrarySongState>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ListeningCheck>()) == 0)
    }

    @Test func historyHasItsOwnLocalStore() {
        let history = ListeningHistoryStore.configuration()
        #expect(history.name == "ListeningHistory")
        #expect(history.cloudKitContainerIdentifier == nil)
        #expect(history.url != ModelConfiguration(schema: Schema(CaffyStore.derivedModels)).url)
    }
}
