import Foundation
import SwiftData
import Testing
@testable import Caffy

/// `ArtworkFiller` puts cover art on saved songs and caches it.
@MainActor
struct ArtworkFillerTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        container = try CaffyStore.makeContainer(inMemory: true)
    }

    private static func song(_ id: String) -> Song {
        Song(id: id, title: "Song \(id)", artist: "Artist \(id)")
    }

    private static func art(_ id: String) -> URL? {
        URL(string: "https://art.example/\(id).jpg")
    }

    /// An era with library additions, and a moment with played songs.
    @discardableResult
    private func insertLibrary() throws -> (era: Era, moment: Moment) {
        let era = Era(title: "Spring", whenLabel: "2026", summary: "", startDate: Self.now, palette: .rust)
        era.addedSongs = [.fixture("3", evidence: .libraryAdded)]
        let moment = Moment(date: Self.now, songs: [Self.song("1"), Self.song("2"), Self.song("library-9")])
        context.insert(era)
        context.insert(moment)
        moment.era = era
        try context.save()
        return (era, moment)
    }

    private func filler(_ lookup: any CatalogSongLookup) -> ArtworkFiller {
        ArtworkFiller(context: context, resolver: ArtworkResolver(lookup: lookup))
    }

    private func cached() throws -> [String: URL?] {
        Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<CatalogArtwork>()).map { ($0.catalogID, $0.url) })
    }

    @Test func fillingPutsArtOnMomentsAndLibraryAdditions() async throws {
        let (era, moment) = try insertLibrary()
        let lookup = FakeCatalogLookup(knowing: ["1", "3"])

        let filled = try await filler(lookup).fill(now: Self.now)

        #expect(filled == 2)
        #expect(moment.songs?.map(\.artworkURL) == [Self.art("1"), nil, nil])
        #expect(era.addedSongs?.first?.song.artworkURL == Self.art("3"))
        #expect(try cached() == ["1": Self.art("1"), "2": nil, "3": Self.art("3")])
        #expect(await lookup.lookups.map(Set.init) == [["1", "2", "3"]])
    }

    @Test func fillingAgainLooksNothingUp() async throws {
        try insertLibrary()
        let lookup = FakeCatalogLookup(knowing: ["1", "3"])
        try await filler(lookup).fill(now: Self.now)

        let filled = try await filler(lookup).fill(now: Self.now.addingTimeInterval(60))

        #expect(filled == 0)
        #expect(await lookup.lookups.count == 1)
    }

    @Test func newSongsWithCachedArtNeedNoLookup() async throws {
        try insertLibrary()
        let lookup = FakeCatalogLookup(knowing: ["1", "3"])
        try await filler(lookup).fill(now: Self.now)
        let later = Moment(date: Self.now, songs: [Self.song("1")])
        context.insert(later)
        try context.save()

        let filled = try await filler(lookup).fill(now: Self.now)

        #expect(filled == 1)
        #expect(later.songs?.first?.artworkURL == Self.art("1"))
        #expect(await lookup.lookups.count == 1)
    }

    @Test func aFailedLookupCachesNothingAndChangesNothing() async throws {
        let (_, moment) = try insertLibrary()

        await #expect(throws: URLError.self) {
            try await filler(FailingLookup()).fill(now: Self.now)
        }

        #expect(try cached().isEmpty)
        #expect(moment.songs?.allSatisfy { $0.artworkURL == nil } == true)
    }

    @Test func cachedURLsLeaveOutSongsWithNoArt() async throws {
        try insertLibrary()
        let filler = filler(FakeCatalogLookup(knowing: ["1"]))
        try await filler.fill(now: Self.now)

        #expect(try filler.cachedURLs() == ["1": Self.art("1")!])
    }

    @Test func cachedArtGoesOnAPipelineResultBeforeSaving() {
        let built = BuiltEra(
            draft: EraDraft(id: "e1", kind: .home, momentIDs: ["m1"], start: Self.now, end: nil, centre: nil, startReason: .firstMoment),
            content: EraContent(title: "Spring", summary: "", whenLabel: "2026"),
            palette: .rust,
            isFrozen: false,
            addedSongs: [.fixture("3", evidence: .libraryAdded)]
        )
        let result = EraPipelineResult(eras: [built], matches: ["m1": [.fixture("1"), .fixture("2")]])

        let withArt = ArtworkResolver.apply(["1": Self.art("1")!, "3": Self.art("3")!], to: result)

        #expect(withArt.matches["m1"]?.map(\.song.artworkURL) == [Self.art("1"), nil])
        #expect(withArt.eras.first?.addedSongs.first?.song.artworkURL == Self.art("3"))
    }
}

/// A catalog that can't be reached.
private struct FailingLookup: CatalogSongLookup {
    func songs(catalogIDs: [String]) async throws -> [String: CatalogSong] {
        throw URLError(.notConnectedToInternet)
    }
}
