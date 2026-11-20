import Foundation
import Testing
@testable import Caffy

/// `ArtworkResolver` decides which covers to look up and puts them on songs.
struct ArtworkResolverTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let day: TimeInterval = 24 * 60 * 60
    private static let art = URL(string: "https://art.example/cached.jpg")!

    private static func song(_ id: String) -> Song {
        Song(id: id, title: "Song \(id)", artist: "Artist \(id)")
    }

    private let resolver = ArtworkResolver(lookup: FakeCatalogLookup(knowing: []))

    @Test func uncachedSongsAreFetchedOnceEachInOrder() {
        let ids = resolver.idsToFetch([Self.song("2"), Self.song("1"), Self.song("2")], cache: [:], now: Self.now)

        #expect(ids == ["2", "1"])
    }

    @Test func songsWithoutACatalogIDAreNeverFetched() {
        #expect(resolver.idsToFetch([Self.song("library-7")], cache: [:], now: Self.now).isEmpty)
    }

    @Test func cachedCoversAreNotFetchedAgain() {
        let cache = ["1": ArtworkCacheEntry(url: Self.art, fetchedAt: Self.now.addingTimeInterval(-365 * Self.day))]

        #expect(resolver.idsToFetch([Self.song("1")], cache: cache, now: Self.now).isEmpty)
    }

    @Test func notFoundIsRetriedOnlyAfterAWeek() {
        let recent = ["1": ArtworkCacheEntry(url: nil, fetchedAt: Self.now.addingTimeInterval(-6 * Self.day))]
        let stale = ["1": ArtworkCacheEntry(url: nil, fetchedAt: Self.now.addingTimeInterval(-7 * Self.day))]

        #expect(resolver.idsToFetch([Self.song("1")], cache: recent, now: Self.now).isEmpty)
        #expect(resolver.idsToFetch([Self.song("1")], cache: stale, now: Self.now) == ["1"])
    }

    @Test func fetchingGivesEveryIDAnEntryFoundOrNot() async throws {
        let lookup = FakeCatalogLookup(knowing: ["1"])

        let entries = try await ArtworkResolver(lookup: lookup).fetch(["1", "9"], now: Self.now)

        #expect(entries["1"] == ArtworkCacheEntry(url: URL(string: "https://art.example/1.jpg"), fetchedAt: Self.now))
        #expect(entries["9"] == ArtworkCacheEntry(url: nil, fetchedAt: Self.now))
        #expect(await lookup.lookups == [["1", "9"]])
    }

    @Test func nothingToFetchMakesNoLookup() async throws {
        let lookup = FakeCatalogLookup(knowing: ["1"])

        let entries = try await ArtworkResolver(lookup: lookup).fetch([], now: Self.now)

        #expect(entries.isEmpty)
        #expect(await lookup.lookups.isEmpty)
    }

    @Test func applyingPutsArtOnlyOnSongsItHasArtFor() {
        let songs = ArtworkResolver.apply(["1": Self.art], to: [Self.song("1"), Self.song("2"), Self.song("library-1")])

        #expect(songs.map(\.artworkURL) == [Self.art, nil, nil])
        #expect(songs.map(\.id) == ["1", "2", "library-1"])
    }

    @Test func applyingToEraSongsKeepsTheirEvidence() {
        let songs = ArtworkResolver.apply(["1": Self.art], to: [EraSong.fixture("1", evidence: .libraryAdded)])

        #expect(songs.first?.song.artworkURL == Self.art)
        #expect(songs.first?.evidence == .libraryAdded)
    }

    @Test func burstTipsTakeCoversFirstAndKeepTheirCount() {
        let fallback = BurstArtwork.placeholders(6)
        let covers = [URL(string: "https://art.example/a.jpg")!, URL(string: "https://art.example/b.jpg")!]

        let tips = BurstArtwork.filling(fallback, with: covers)

        #expect(tips.count == 6)
        if case .url(let first) = tips[0] { #expect(first == covers[0]) } else { Issue.record("Expected a cover first") }
        if case .placeholder = tips[2] {} else { Issue.record("Expected placeholders after the covers") }
    }
}
