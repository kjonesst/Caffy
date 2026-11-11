import Foundation
import SwiftData
import Testing
@testable import Caffy

/// Tests for `EraStore`, which saves pipeline results into SwiftData and
/// loads frozen eras back. Each test uses its own in-memory database.
@MainActor
struct EraStoreTests {
    // MARK: - Fixtures

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private var store: EraStore { EraStore(context: context) }

    init() throws {
        container = try ModelContainer(
            for: Era.self, Moment.self, Place.self, CaffyPlaylist.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private static let hour: TimeInterval = 60 * 60
    private static let day: TimeInterval = 24 * hour

    private static let weekendAway = Scenario()
        .listen(to: "Tame Impala", genre: "Psychedelic")
        .live(at: .sydney, days: 25)
        .listen(to: "Fred again..", genre: "Electronic")
        .trip(to: .melbourne, nights: 2)
        .listen(to: "Tame Impala", genre: "Psychedelic")
        .live(at: .sydney, days: 21)

    private static let musicShift = Scenario()
        .listen(to: "Tame Impala", genre: "Psychedelic")
        .live(at: .sydney, days: 63)
        .listen(to: "Fred again..", genre: "Electronic")
        .live(at: .sydney, days: 56)

    private func eras() throws -> [Era] {
        try context.fetch(FetchDescriptor<Era>()).sorted { ($0.startDate, $0.eraID ?? "") < ($1.startDate, $1.eraID ?? "") }
    }

    private func allMoments() throws -> [Moment] {
        try context.fetch(FetchDescriptor<Moment>())
    }

    /// Runs the pipeline on `scenario` (with the saved frozen eras) and saves it.
    @discardableResult
    private func sync(
        _ scenario: Scenario,
        moments: [PhotoMoment]? = nil,
        now: Date? = nil,
        config: EraBuildConfig = .standard,
        useFrozen: Bool = true
    ) async throws -> EraPipelineResult {
        let moments = moments ?? scenario.moments
        let now = now ?? scenario.now
        let frozen = useFrozen ? try store.frozenEras() : []
        let result = await PipelineHarness.run(scenario, moments: moments, frozen: frozen, now: now, config: config)
        try store.save(result, moments: moments, now: now)
        return result
    }

    // MARK: - Saving

    @Test func savingCreatesErasMomentsAndPlaylists() async throws {
        let result = try await sync(Self.weekendAway)
        let saved = try eras()

        #expect(saved.map(\.eraID) == result.eras.map(\.draft.id))
        #expect(saved.map(\.kind) == [.home, .trip])
        #expect(saved.map(\.title) == result.titles)
        #expect(saved.map(\.summary) == result.eras.map(\.content.summary))
        #expect(saved.map(\.whenLabel) == result.eras.map(\.content.whenLabel))
        #expect(saved.map(\.palette) == result.eras.map(\.palette))
        #expect(saved.map(\.startDate) == result.eras.map(\.draft.start))
        #expect(saved.map(\.endDate) == result.eras.map(\.draft.end))
        #expect(saved.map(\.isFrozen) == result.eras.map(\.isFrozen))

        for (era, built) in zip(saved, result.eras) {
            #expect(Set(era.moments.compactMap(\.momentID)) == Set(built.draft.momentIDs))
            #expect(era.playlist?.name == built.content.title)
            #expect(era.playlist?.lastUpdated == Self.weekendAway.now)
        }
        for moment in try allMoments() {
            let id = try #require(moment.momentID)
            #expect(moment.songs == result.songs[id])
        }
    }

    @Test func momentsCopyTheirPhotos() async throws {
        try await sync(Self.weekendAway)
        let source = try #require(Self.weekendAway.moments.first)
        let saved = try #require(try allMoments().first { $0.momentID == source.id })

        #expect(saved.date == source.start)
        #expect(saved.endDate == source.end)
        #expect(saved.photoAssetIdentifier == source.coverID)
        #expect(saved.photoAspectRatio == source.coverAspectRatio)
        #expect(saved.latitude == source.coordinate?.latitude)
        #expect(saved.longitude == source.coordinate?.longitude)
    }

    @Test func savingTheSameResultAgainChangesNothing() async throws {
        try await sync(Self.weekendAway)
        let erasBefore = try eras().map(\.persistentModelID)
        let momentsBefore = Set(try allMoments().map(\.persistentModelID))

        try await sync(Self.weekendAway, now: Self.weekendAway.now.addingTimeInterval(Self.hour))

        #expect(try eras().map(\.persistentModelID) == erasBefore)
        #expect(Set(try allMoments().map(\.persistentModelID)) == momentsBefore)
        // The songs didn't change, so neither did the playlists.
        #expect(try eras().allSatisfy { $0.playlist?.lastUpdated == Self.weekendAway.now })
    }

    // MARK: - Keeping eras and playlists

    @Test func growingEraKeepsItsObjectAndPlaylist() async throws {
        let first = Scenario().listen(to: "Tame Impala", genre: "Psychedelic").live(at: .sydney, days: 40)
        try await sync(first)
        let era = try #require(try eras().first)
        let playlist = try #require(era.playlist)
        let momentCount = era.moments.count

        // Ten more days of the same three songs: more moments, same playlist songs.
        let later = first.live(at: .sydney, days: 10)
        try await sync(later)
        #expect(try eras().map(\.persistentModelID) == [era.persistentModelID])
        #expect(era.moments.count > momentCount)
        #expect(era.playlist?.persistentModelID == playlist.persistentModelID)
        #expect(playlist.lastUpdated == first.now)

        // A new artist: the playlist's songs change, so it's updated now.
        let newMusic = later.alsoListen(to: "Pond", genre: "Psychedelic").live(at: .sydney, days: 5)
        try await sync(newMusic)
        #expect(playlist.lastUpdated == newMusic.now)
    }

    @Test func eraWhoseFirstPhotoChangesKeepsItsObject() async throws {
        let scenario = Scenario().live(at: .sydney, days: 40)
        try await sync(scenario)
        let era = try #require(try eras().first)
        let playlist = try #require(era.playlist)

        // An older photo turns up, so the era's first moment (its id) changes.
        let firstStart = try #require(scenario.moments.first).start
        let early = PhotoMoment(
            id: "early", start: firstStart.addingTimeInterval(-Self.day), end: firstStart.addingTimeInterval(-Self.day),
            photoIDs: ["early"], coverID: "early", coverAspectRatio: 1, coordinate: FixturePlace.sydney.coordinate
        )
        try await sync(scenario, moments: [early] + scenario.moments)

        let saved = try eras()
        #expect(saved.map(\.persistentModelID) == [era.persistentModelID])
        #expect(era.eraID == "early")
        #expect(era.playlist?.persistentModelID == playlist.persistentModelID)
    }

    // MARK: - Frozen eras

    @Test func frozenErasComeBackExactlyAsSaved() async throws {
        let result = try await sync(Self.musicShift)
        #expect(try store.frozenEras() == PipelineHarness.frozen(result))
        #expect(try store.frozenEras().count == 1)
    }

    @Test func frozenErasSurviveLaterSyncs() async throws {
        let first = try await sync(Self.musicShift)
        let frozen = try #require(first.eras.first)

        let later = Self.musicShift.live(at: .sydney, days: 30)
        var stricter = EraBuildConfig()
        stricter.maxEraLength = 40 * Self.day
        stricter.minEraLength = 15 * Self.day
        try await sync(later, config: stricter)

        let saved = try #require(try eras().first)
        #expect(saved.frozen == frozen.frozen)
        #expect(saved.isFrozen)
    }

    @Test func frozenMomentsKeepTheirSongs() async throws {
        try await sync(Self.musicShift)
        let frozenEra = try #require(try eras().first)
        let songsBefore = Dictionary(uniqueKeysWithValues: frozenEra.moments.map { ($0.momentID!, $0.songs) })
        #expect(songsBefore.values.allSatisfy { !$0.isEmpty })

        // The same library, but every play has gone.
        let pipeline = EraPipeline(namer: FixturePlaceNamer(), sampler: PipelineHarness.sampler(for: Self.musicShift.moments))
        let quiet = await pipeline.run(
            moments: Self.musicShift.moments, plays: [], frozen: try store.frozenEras(),
            now: Self.musicShift.now, calendar: Self.musicShift.calendar
        )
        try store.save(quiet, moments: Self.musicShift.moments, now: Self.musicShift.now)

        let saved = try eras()
        #expect(Dictionary(uniqueKeysWithValues: saved[0].moments.map { ($0.momentID!, $0.songs) }) == songsBefore)
        #expect(saved[1].moments.allSatisfy { $0.songs.isEmpty })
    }

    // MARK: - Deleting

    @Test func erasAndPhotosThatAreGoneAreDeleted() async throws {
        let scenario = Scenario()
            .live(at: .sydney, days: 40)
            .gap(days: 120)
            .live(at: .sydney, days: 40)
        let first = try await sync(scenario)
        #expect(try eras().count == 2)

        // The second era's photos are deleted, and one photo from the first.
        let firstEra = first.eras[0].draft
        let keep = Set(firstEra.momentIDs.dropLast())
        try await sync(scenario, moments: scenario.moments.filter { keep.contains($0.id) })

        #expect(try eras().map(\.eraID) == [firstEra.id])
        #expect(Set(try allMoments().compactMap(\.momentID)) == keep)
        #expect(try context.fetch(FetchDescriptor<CaffyPlaylist>()).count == 1)
    }

    @Test func momentsMovingOutOfADeletedEraSurvive() async throws {
        let first = try await sync(Self.musicShift, useFrozen: false)
        #expect(first.eras.count == 2)

        // Rules that never cut on music: the two eras become one, so the
        // second stored era is deleted while its moments move to the first.
        var noMusicCuts = EraBuildConfig()
        noMusicCuts.strongCutScore = 2
        try await sync(Self.musicShift, config: noMusicCuts, useFrozen: false)

        #expect(try eras().count == 1)
        #expect(try allMoments().count == Self.musicShift.moments.count)
        #expect(try eras().first?.moments.count == Self.musicShift.moments.count)
    }

    @Test func sampleDataIsReplaced() async throws {
        try await SampleData.insert(into: context, using: MockMusicProvider())
        #expect(try eras().allSatisfy { $0.eraID == nil })

        let result = try await sync(Self.weekendAway)
        #expect(try eras().map(\.eraID) == result.eras.map(\.draft.id))
        #expect(try allMoments().allSatisfy { $0.momentID != nil })
        #expect(try context.fetch(FetchDescriptor<CaffyPlaylist>()).count == result.eras.count)
    }
}
