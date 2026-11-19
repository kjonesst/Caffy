import Foundation

/// A song as the Apple Music catalog describes it.
nonisolated struct CatalogSong: Hashable, Sendable {
    /// The catalog id.
    let id: String
    let title: String
    let artist: String
    /// Cover art at a fixed size, when the catalog has any.
    var artworkURL: URL? = nil
}

/// Looks songs up in the Apple Music catalog by catalog id.
///
/// A protocol so matching and artwork can be tested without MusicKit:
/// `LiveCatalogSongLookup` is the real one, and tests use a fake.
nonisolated protocol CatalogSongLookup: Sendable {
    /// The songs the catalog has, by catalog id. Ids it doesn't know are
    /// left out rather than throwing.
    func songs(catalogIDs: [String]) async throws -> [String: CatalogSong]
}

/// An era's songs, split into the ones that can go into an Apple Music
/// playlist and the ones that can't, with why.
nonisolated struct PlaylistSongMatch: Equatable, Sendable {
    struct Matched: Equatable, Sendable {
        let song: EraSong
        let catalog: CatalogSong
    }

    struct Unmatched: Equatable, Sendable {
        let song: EraSong
        let reason: Reason
    }

    enum Reason: String, Equatable, Sendable {
        /// The library song has no catalog id, such as an imported file
        /// (its id is `library-<persistentID>`).
        case noCatalogID
        /// It has a catalog id, but the catalog didn't return it, for example
        /// because it's no longer available in the user's storefront.
        case notInCatalog
    }

    /// In the era playlist's order.
    var matched: [Matched]
    /// In the era playlist's order.
    var unmatched: [Unmatched]

    /// What to publish, in order.
    var catalogIDs: [String] { matched.map(\.catalog.id) }
}

/// Matches an era's songs to Apple Music catalog songs by catalog id.
///
/// `Song.id` is the catalog id whenever the library knows one, so this is
/// an exact lookup with no guessing. Songs without one are reported, not
/// searched for: a title-and-artist fallback is proposed in
/// docs/notes/musickit-findings.md but not decided.
nonisolated enum PlaylistSongMatcher {
    /// The prefix `LibrarySongSnapshot.song` gives songs with no catalog id.
    static let libraryIDPrefix = "library-"

    static func catalogID(of song: Song) -> String? {
        song.id.hasPrefix(libraryIDPrefix) || song.id.isEmpty ? nil : song.id
    }

    /// Looks up every catalog id once, keeps the songs' order, and leaves
    /// out repeats (the first one stays).
    static func match(_ songs: [EraSong], lookup: any CatalogSongLookup) async throws -> PlaylistSongMatch {
        var seen = Set<String>()
        let unique = songs.filter { seen.insert($0.song.id).inserted }
        let ids = unique.compactMap { catalogID(of: $0.song) }
        let found = ids.isEmpty ? [:] : try await lookup.songs(catalogIDs: ids)

        var result = PlaylistSongMatch(matched: [], unmatched: [])
        for song in unique {
            guard let id = catalogID(of: song.song) else {
                result.unmatched.append(.init(song: song, reason: .noCatalogID))
                continue
            }
            if let catalog = found[id] {
                result.matched.append(.init(song: song, catalog: catalog))
            } else {
                result.unmatched.append(.init(song: song, reason: .notInCatalog))
            }
        }
        return result
    }
}
