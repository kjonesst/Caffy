import Foundation
import Testing
@testable import Caffy

/// `CachedCatalogLookup` answers from the artwork cache, and only asks the
/// catalog about songs it has never seen.
struct CachedCatalogLookupTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let art = URL(string: "https://art.example/cached.jpg")

    private static func song(_ id: String) -> Song {
        Song(id: id, title: "Mine \(id)", artist: "Artist \(id)")
    }

    private func lookup(_ cache: [String: ArtworkCacheEntry], live: FakeCatalogLookup) -> CachedCatalogLookup {
        CachedCatalogLookup(cache: cache, live: live, songs: ["1", "2", "3"].map(Self.song))
    }

    @Test func knownSongsNeedNoLookup() async throws {
        let live = FakeCatalogLookup(knowing: ["1", "2"])
        let cache = [
            "1": ArtworkCacheEntry(url: Self.art, fetchedAt: Self.now, isInCatalog: true),
            "2": ArtworkCacheEntry(url: nil, fetchedAt: Self.now, isInCatalog: false)
        ]

        let found = try await lookup(cache, live: live).songs(catalogIDs: ["1", "2"])

        #expect(Array(found.keys) == ["1"])
        #expect(found["1"]?.title == "Mine 1")
        #expect(found["1"]?.artworkURL == Self.art)
        #expect(await live.lookups.isEmpty)
    }

    @Test func unseenSongsAreAskedOnceTogether() async throws {
        let live = FakeCatalogLookup(knowing: ["2", "3"])
        let cache = ["1": ArtworkCacheEntry(url: Self.art, fetchedAt: Self.now, isInCatalog: true)]

        let found = try await lookup(cache, live: live).songs(catalogIDs: ["1", "2", "3", "2"])

        #expect(Set(found.keys) == ["1", "2", "3"])
        #expect(await live.lookups == [["2", "3"]])
    }

    @Test func oldEntriesWithArtCountAsFoundAndWithoutAreAsked() async throws {
        let live = FakeCatalogLookup(knowing: ["2"])
        let cache = [
            "1": ArtworkCacheEntry(url: Self.art, fetchedAt: Self.now),
            "2": ArtworkCacheEntry(url: nil, fetchedAt: Self.now)
        ]

        let found = try await lookup(cache, live: live).songs(catalogIDs: ["1", "2"])

        #expect(Set(found.keys) == ["1", "2"])
        #expect(await live.lookups == [["2"]])
    }
}
