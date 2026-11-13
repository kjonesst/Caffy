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
            photoIDs: ["early"], coverID: "early", coverAspectRatio: 1, coordinate: SamplePlace.sydney.coordinate
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
        #expect(songsBefore.values.allSatisfy { !($0 ?? []).isEmpty })

        // The same library, but every play has gone.
        let pipeline = EraPipeline(namer: SamplePlaceNamer(), sampler: PipelineHarness.sampler(for: Self.musicShift.moments))
        let quiet = await pipeline.run(
            moments: Self.musicShift.moments, plays: [], frozen: try store.frozenEras(),
            now: Self.musicShift.now, calendar: Self.musicShift.calendar
        )
        try store.save(quiet, moments: Self.musicShift.moments, now: Self.musicShift.now)

        let saved = try eras()
        #expect(Dictionary(uniqueKeysWithValues: saved[0].moments.map { ($0.momentID!, $0.songs) }) == songsBefore)
        // With no plays at all, nothing reaches the open era's moments.
        #expect(saved[1].moments.allSatisfy { $0.songs == nil })
    }

    @Test func frozenMomentsNeverMatchedCanStillGetSome() async throws {
        try await sync(Self.musicShift)
        let frozenBefore = try #require(try eras().first)
        #expect(frozenBefore.isFrozen)
        // As if it froze before its listening was recorded.
        for moment in frozenBefore.moments {
            moment.setMatches(nil)
        }
        try context.save()

        let result = try await sync(Self.musicShift)

        let frozen = try #require(try eras().first)
        #expect(frozen.isFrozen)
        #expect(!frozen.songs.isEmpty)
        for moment in frozen.moments {
            #expect(moment.songs == result.songs[moment.momentID!] ?? [])
        }
    }

    @Test func frozenMomentsMatchedWithNothingStayThatWay() async throws {
        try await sync(Self.musicShift)
        let frozen = try #require(try eras().first)
        for moment in frozen.moments {
            moment.setMatches([])
        }
        try context.save()

        try await sync(Self.musicShift)
        #expect(try #require(try eras().first).moments.allSatisfy { $0.songs == [] })
    }

    // MARK: - Library additions

    /// `musicShift`, with songs added to the library in each era. Adding
    /// songs doesn't change the photos or plays.
    private static func musicShift(adding first: [String], then second: [String]) -> Scenario {
        Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .addToLibrary(first, by: "Pond", genre: "Psychedelic")
            .live(at: .sydney, days: 63)
            .listen(to: "Fred again..", genre: "Electronic")
            .addToLibrary(second, by: "Four Tet", genre: "Electronic")
            .live(at: .sydney, days: 56)
    }

    private func addedTitles(_ era: Era) -> [String] {
        (era.addedSongs ?? []).map(\.song.title)
    }

    @Test func aFrozenEraTakesLibraryAdditionsOnce() async throws {
        // First synced without music access: no additions anywhere.
        try await sync(Self.musicShift)
        let frozen = try #require(try eras().first)
        #expect(frozen.isFrozen)
        #expect(addedTitles(frozen).isEmpty)

        // With the library: the frozen era takes its additions.
        try await sync(Self.musicShift(adding: ["Sorry I Missed Your Party"], then: ["Baby"]))
        #expect(addedTitles(frozen) == ["Sorry I Missed Your Party"])
        #expect(frozen.songs.contains { $0.evidence == .libraryAdded && $0.song.title == "Sorry I Missed Your Party" })

        // Different additions later don't change a frozen era's.
        try await sync(Self.musicShift(adding: ["Paint Me Silver"], then: ["Two Thousand and Seventeen"]))
        #expect(addedTitles(frozen) == ["Sorry I Missed Your Party"])
        // An open era takes the latest.
        let open = try #require(try eras().last)
        #expect(!open.isFrozen)
        #expect(addedTitles(open) == ["Two Thousand and Seventeen"])
    }

    @Test func resyncingTheSameLibraryLeavesAnOpenEraAlone() async throws {
        let scenario = Self.musicShift(adding: ["Sorry I Missed Your Party"], then: ["Baby", "Planet"])
        try await sync(scenario)
        let open = try #require(try eras().last)
        let songs = open.songs
        #expect(songs.contains { $0.evidence == .libraryAdded })

        try await sync(scenario, now: scenario.now.addingTimeInterval(Self.hour))
        #expect(open.songs == songs)
        #expect(open.playlist?.lastUpdated == scenario.now)
    }

    // MARK: - No caps

    @Test func busyMomentsKeepEverySongAndShowTheirTop() async throws {
        let titles = (1...20).map { "Song \($0)" }
        let busy = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic", perDay: 80, titles: titles)
            .live(at: .sydney, days: 10, photosPerWeek: 7)
        try await sync(busy)
        let limit = EraBuildConfig.standard.maxSongsPerMoment
        let moment = try #require(try allMoments().first { ($0.songs?.count ?? 0) > limit })
        let era = try #require(moment.era)

        let playlist = Set(era.songs.map(\.song.id))
        #expect(Set((moment.songs ?? []).map(\.id)).isSubset(of: playlist))
        #expect(moment.shownSongs.count == limit)
        #expect(moment.shownSongs == Array((moment.songs ?? []).prefix(limit)))
        #expect(moment.displaySongs().count == limit)
    }

    // MARK: - One-off reset of empty frozen moments

    @Test func emptyFrozenMomentsAreResetOnce() async throws {
        try await sync(Self.musicShift)
        let frozen = try #require(try eras().first)
        let open = try #require(try eras().last)
        for moment in frozen.moments + open.moments {
            moment.setMatches([])
        }
        try context.save()
        let defaults = try #require(UserDefaults(suiteName: "EraStoreTests-\(UUID().uuidString)"))

        try store.resetEmptyFrozenMomentSongsOnce(defaults: defaults)
        #expect(frozen.moments.allSatisfy { $0.songs == nil })
        // Only frozen eras' moments: open ones are rematched every sync anyway.
        #expect(open.moments.allSatisfy { $0.songs == [] })

        // A second run does nothing, even with empty frozen moments again.
        for moment in frozen.moments {
            moment.setMatches([])
        }
        try context.save()
        try store.resetEmptyFrozenMomentSongsOnce(defaults: defaults)
        #expect(frozen.moments.allSatisfy { $0.songs == [] })
    }

    // MARK: - Moments without songs

    @Test func momentsWithoutSongsShowTheirErasLabelled() async throws {
        try await sync(Self.musicShift)
        let era = try #require(try eras().first)
        let moments = era.momentsNewestFirst
        let withSongs = try #require(moments.first { !($0.songs ?? []).isEmpty })
        #expect(!withSongs.isEraFallback)
        #expect(withSongs.displaySongs() == withSongs.songs)

        for songs in [nil, [Song]()] {
            let moment = try #require(moments.last)
            moment.songs = songs
            #expect(moment.isEraFallback)
            #expect(moment.displaySongs(limit: 3) == Array(era.songs.prefix(3).map(\.song)))
        }
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

    /// Eras saved before the pipeline existed: no ids, like the old
    /// hand-written sample data.
    private func insertLegacyEras() {
        for (index, title) in ["The Long Way Round", "Looking Up"].enumerated() {
            let era = Era(title: title, whenLabel: "2026", summary: "", startDate: Date(timeIntervalSince1970: Double(index) * 1_000_000), palette: .olive)
            context.insert(era)
            era.moments.append(Moment(date: era.startDate, songs: SampleData.previewSongs))
            era.playlist = CaffyPlaylist(name: title, lastUpdated: era.startDate)
        }
    }

    @Test func legacyErasAreReplaced() async throws {
        insertLegacyEras()
        #expect(try eras().count == 2)
        #expect(try eras().allSatisfy { $0.eraID == nil })

        let result = try await sync(Self.weekendAway)
        #expect(try eras().map(\.eraID) == result.eras.map(\.draft.id))
        #expect(try allMoments().allSatisfy { $0.momentID != nil })
        #expect(try context.fetch(FetchDescriptor<CaffyPlaylist>()).count == result.eras.count)
    }
}
