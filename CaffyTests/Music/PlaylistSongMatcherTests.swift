import Foundation
import Testing
@testable import Caffy

/// `PlaylistSongMatcher` finds each era song in the catalog by its id.
struct PlaylistSongMatcherTests {
    @Test func matchesSongsByCatalogIDInOrder() async throws {
        let lookup = FakeCatalogLookup(knowing: ["3", "1", "2"])

        let match = try await PlaylistSongMatcher.match([.fixture("1"), .fixture("2"), .fixture("3")], lookup: lookup)

        #expect(match.catalogIDs == ["1", "2", "3"])
        #expect(match.unmatched.isEmpty)
        #expect(match.matched.map(\.catalog.title) == ["Title 1", "Title 2", "Title 3"])
    }

    @Test func songsWithoutACatalogIDAreReportedAndNeverLookedUp() async throws {
        let lookup = FakeCatalogLookup(knowing: ["1"])

        let match = try await PlaylistSongMatcher.match([.fixture("library-42"), .fixture("1")], lookup: lookup)

        #expect(match.catalogIDs == ["1"])
        #expect(match.unmatched.map(\.song.id) == ["library-42"])
        #expect(match.unmatched.map(\.reason) == [.noCatalogID])
        #expect(await lookup.lookups == [["1"]])
    }

    @Test func songsTheCatalogDoesNotReturnAreReported() async throws {
        let lookup = FakeCatalogLookup(knowing: ["1"])

        let match = try await PlaylistSongMatcher.match([.fixture("1"), .fixture("9")], lookup: lookup)

        #expect(match.catalogIDs == ["1"])
        #expect(match.unmatched.map(\.reason) == [.notInCatalog])
    }

    @Test func repeatsAreLookedUpOnceAndPublishedOnce() async throws {
        let lookup = FakeCatalogLookup(knowing: ["1", "2"])

        let match = try await PlaylistSongMatcher.match(
            [.fixture("1"), .fixture("2"), .fixture("1", evidence: .libraryAdded)], lookup: lookup
        )

        #expect(match.catalogIDs == ["1", "2"])
        #expect(match.matched.first?.song.evidence == .nearPlay)
        #expect(await lookup.lookups == [["1", "2"]])
    }

    @Test func noSongsMeansNoLookup() async throws {
        let lookup = FakeCatalogLookup(knowing: ["1"])

        let match = try await PlaylistSongMatcher.match([.fixture("library-1")], lookup: lookup)

        #expect(match.matched.isEmpty)
        #expect(await lookup.lookups.isEmpty)
    }

    @Test func uniquedKeepsFirstAppearances() {
        #expect(MusicKitCatalog.uniqued(["b", "a", "b", "c", "a"]) == ["b", "a", "c"])
    }
}
