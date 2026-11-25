import Foundation
import SwiftData
import Testing
@testable import Caffy

/// `EraPublisher` publishes an era's playlist when its pill is tapped.
@MainActor
struct EraPublisherTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let library = FakePlaylistPublisher()

    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        container = try CaffyStore.makeContainer(inMemory: true)
    }

    private func publisher(knowing ids: [String] = ["1", "2", "3"], album: (any CoverAlbum)? = nil) -> (EraPublisher, FakeCatalogLookup) {
        let lookup = FakeCatalogLookup(knowing: ids)
        return (EraPublisher(context: context, publisher: library, lookup: lookup, album: album, now: { Self.now }), lookup)
    }

    /// Gives the era a moment with a photo, which becomes its highlight.
    private func addPhoto(_ assetID: String, to era: Era) throws {
        let moment = Moment(date: Self.now, songs: nil)
        moment.photoAssetIdentifier = assetID
        context.insert(moment)
        moment.era = era
        try context.save()
    }

    private func publisher(lookup: any CatalogSongLookup) -> EraPublisher {
        EraPublisher(context: context, publisher: library, lookup: lookup, now: { Self.now })
    }

    @discardableResult
    private func insertEra(_ songIDs: [String] = ["1", "2"], eraID: String? = "e1", title: String = "Spring at home") throws -> Era {
        let era = Era(title: title, whenLabel: "2026", summary: "", startDate: Self.now, palette: .rust)
        era.eraID = eraID
        era.addedSongs = songIDs.map { .fixture($0, evidence: .libraryAdded) }
        era.playlist = CaffyPlaylist(name: title, lastUpdated: Self.now)
        context.insert(era)
        try context.save()
        return era
    }

    private func listen(_ publisher: EraPublisher, to era: Era, music: MusicAccess = .authorized, library access: MusicLibraryAccess = .canAddToLibrary) async -> EraPublisher.ListenResult? {
        await publisher.listen(to: era, music: music, library: access)
    }

    @Test func theFirstTapMakesThePlaylistAndSavesItsLink() async throws {
        let era = try insertEra()
        let (publisher, _) = publisher()

        let result = try #require(await listen(publisher, to: era))

        #expect(result.isFirstPublish)
        #expect(result.url == URL(string: "https://music.example/p.1"))
        #expect(await library.writes == [.create(name: "Spring at home", catalogIDs: ["1", "2"])])
        #expect(era.playlist?.appleMusicID == "p.1")
        #expect(try PlaylistLedger(context: context).link(forEraID: "e1")?.songIDs == ["1", "2"])
        #expect(publisher.state(for: era) == .idle)
    }

    @Test func tappingAgainWritesNothingAndOpensTheSamePlaylist() async throws {
        let era = try insertEra()
        let (publisher, _) = publisher()
        _ = await listen(publisher, to: era)

        let again = try #require(await listen(publisher, to: era))

        #expect(!again.isFirstPublish)
        #expect(again.url == URL(string: "https://music.example/p.1"))
        #expect(await library.writes.count == 1)
    }

    @Test func newSongsReplaceTheTracks() async throws {
        let era = try insertEra()
        let (publisher, _) = publisher()
        _ = await listen(publisher, to: era)
        era.addedSongs?.append(.fixture("3", evidence: .libraryAdded))

        let result = try #require(await listen(publisher, to: era))

        #expect(!result.isFirstPublish)
        #expect(await library.writes.last == .replaceTracks(id: "p.1", catalogIDs: ["1", "2", "3"]))
    }

    @Test func aNewTitleRenamesThePlaylist() async throws {
        let era = try insertEra()
        let (publisher, _) = publisher()
        _ = await listen(publisher, to: era)
        era.title = "Spring in Fremantle"

        _ = await listen(publisher, to: era)

        #expect(await library.writes.last == .rename(id: "p.1", name: "Spring in Fremantle"))
    }

    @Test func aPlaylistDeletedInAppleMusicIsMadeAgain() async throws {
        let era = try insertEra()
        let (publisher, _) = publisher()
        _ = await listen(publisher, to: era)
        await library.delete("p.1")

        let result = try #require(await listen(publisher, to: era))

        #expect(result.isFirstPublish)
        #expect(result.url == URL(string: "https://music.example/p.2"))
        #expect(era.playlist?.appleMusicID == "p.2")
    }

    @Test func aFailedLookupSavesNothingAndCanBeRetried() async throws {
        let era = try insertEra()
        let publisher = publisher(lookup: UnreachableCatalog())

        #expect(await listen(publisher, to: era) == nil)

        #expect(publisher.state(for: era) == .failed(.couldNotReach))
        #expect(era.playlist?.appleMusicID == nil)
        #expect(await library.writes.isEmpty)
    }

    @Test func withoutAccessNothingIsWritten() async throws {
        let era = try insertEra()
        let (publisher, _) = publisher()

        #expect(await listen(publisher, to: era, music: .denied) == nil)
        #expect(publisher.state(for: era) == .failed(.musicAccess(.denied)))

        #expect(await listen(publisher, to: era, library: .syncLibraryOff) == nil)
        #expect(publisher.state(for: era) == .failed(.libraryAccess(.syncLibraryOff)))

        #expect(await library.calls.isEmpty)
    }

    @Test func anUnknownSubscriptionStillTries() async throws {
        let era = try insertEra()
        let (publisher, _) = publisher()

        #expect(await listen(publisher, to: era, library: .unknown) != nil)
    }

    @Test func twoQuickTapsMakeOnePlaylist() async throws {
        let era = try insertEra()
        let (publisher, _) = publisher()

        async let first = listen(publisher, to: era)
        async let second = listen(publisher, to: era)
        let results = await [first, second]

        #expect(results.compactMap { $0 }.count == 1)
        #expect(await library.writes.count == 1)
    }

    @Test func anEraWithNoCatalogSongsHasNothingToPublish() async throws {
        let era = try insertEra(["library-9"])
        let (publisher, _) = publisher()

        #expect(await listen(publisher, to: era) == nil)
        #expect(publisher.state(for: era) == .failed(.nothingPublishable))
        #expect(await library.calls.isEmpty)
    }

    @Test func cachedSongsNeedNoCatalogLookup() async throws {
        let era = try insertEra()
        for id in ["1", "2"] {
            context.insert(CatalogArtwork(catalogID: id, entry: ArtworkCacheEntry(url: nil, fetchedAt: Self.now, isInCatalog: true)))
        }
        try context.save()
        let (publisher, lookup) = publisher()

        #expect(await listen(publisher, to: era) != nil)
        #expect(await lookup.lookups.isEmpty)
    }

    // MARK: - Cover album

    @Test func theFirstPublishPutsTheHighlightInTheCoverAlbumOnce() async throws {
        let era = try insertEra()
        try addPhoto("photo-1", to: era)
        let album = FakeCoverAlbum()
        let (publisher, _) = publisher(album: album)

        let first = try #require(await listen(publisher, to: era))
        let second = try #require(await listen(publisher, to: era))

        #expect(first.coverPhotoID == "photo-1" && first.coverIsInAlbum)
        #expect(second.coverPhotoID == "photo-1" && second.coverIsInAlbum)
        #expect(await album.added == ["photo-1"])
        #expect(try PlaylistLedger(context: context).coverPhotoID(forEraID: "e1") == "photo-1")
    }

    @Test func theCoverStaysTheSameWhenANewerPhotoArrives() async throws {
        let era = try insertEra()
        try addPhoto("photo-1", to: era)
        let album = FakeCoverAlbum()
        let (publisher, _) = publisher(album: album)
        _ = await listen(publisher, to: era)

        let newer = Moment(date: Self.now.addingTimeInterval(3_600), songs: nil)
        newer.photoAssetIdentifier = "photo-2"
        context.insert(newer)
        newer.era = era
        let result = try #require(await listen(publisher, to: era))

        #expect(result.coverPhotoID == "photo-1")
        #expect(await album.added == ["photo-1"])
    }

    @Test func anAlbumFailureStillPublishesAndTriesAgainNextTime() async throws {
        let era = try insertEra()
        try addPhoto("photo-1", to: era)
        let (failing, _) = publisher(album: FakeCoverAlbum(failing: .noAccess))

        let result = try #require(await listen(failing, to: era))

        #expect(result.isFirstPublish)
        #expect(result.coverPhotoID == "photo-1" && !result.coverIsInAlbum)
        #expect(try PlaylistLedger(context: context).coverPhotoID(forEraID: "e1") == nil)

        let album = FakeCoverAlbum()
        let (working, _) = publisher(album: album)
        let retry = try #require(await listen(working, to: era))
        #expect(retry.coverIsInAlbum)
        #expect(await album.added == ["photo-1"])
    }

    @Test func anEraWithoutPhotosHasNoCover() async throws {
        let era = try insertEra()
        let album = FakeCoverAlbum()
        let (publisher, _) = publisher(album: album)

        let result = try #require(await listen(publisher, to: era))

        #expect(result.coverPhotoID == nil && !result.coverIsInAlbum)
        #expect(await album.added.isEmpty)
    }

    @Test func aRemadePlaylistKeepsItsCoverPhoto() async throws {
        let era = try insertEra()
        try addPhoto("photo-1", to: era)
        let album = FakeCoverAlbum()
        let (publisher, _) = publisher(album: album)
        _ = await listen(publisher, to: era)
        await library.delete("p.1")

        let result = try #require(await listen(publisher, to: era))

        #expect(result.isFirstPublish && result.coverIsInAlbum)
        #expect(await album.added == ["photo-1"])
    }

    @Test func onlyRealErasWithMusicOfferListening() throws {
        #expect(EraPublisher.canListen(to: try insertEra()))
        #expect(!EraPublisher.canListen(to: try insertEra([], eraID: "e2")))
        #expect(!EraPublisher.canListen(to: try insertEra(eraID: nil)))
    }

    @Test func theDescriptionSaysWhen() throws {
        let era = try insertEra()

        #expect(EraPublisher.description(for: era).hasPrefix("Made by Caffy from the music you lived with"))
        #expect(EraPublisher.description(for: era).hasSuffix("now."))
    }

    @Test func buttonsSayWhatWentWrong() {
        #expect(EraListenButton.display(for: .idle) == .ready)
        #expect(EraListenButton.display(for: .publishing).isWorking)
        #expect(EraListenButton.display(for: .failed(.couldNotReach)).isProblem)
        #expect(EraListenButton.opensSettings(.musicAccess(.denied)))
        #expect(!EraListenButton.opensSettings(.couldNotReach))
    }
}

/// A catalog that can't be reached.
private struct UnreachableCatalog: CatalogSongLookup {
    func songs(catalogIDs: [String]) async throws -> [String: CatalogSong] {
        throw URLError(.notConnectedToInternet)
    }
}
