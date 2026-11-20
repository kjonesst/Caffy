import Foundation

/// What Caffy knows about one song's cover art.
nonisolated struct ArtworkCacheEntry: Equatable, Sendable {
    /// `nil` when the catalog had no art for the song, or didn't return it.
    var url: URL?
    var fetchedAt: Date
}

/// Works out which covers to look up, looks them up, and puts them on songs.
///
/// Plain values and a `CatalogSongLookup`, so it's tested without MusicKit.
/// Batching (and narrowing down bad responses) is the lookup's job: the live
/// one goes through `CatalogBatcher`. `ArtworkFiller` stores the results.
nonisolated struct ArtworkResolver: Sendable {
    let lookup: any CatalogSongLookup
    /// How long a song the catalog gave no art for waits before it's tried
    /// again, in case the catalog has it later.
    var retryNotFoundAfter: TimeInterval = 7 * 24 * 60 * 60

    /// The catalog ids among `songs` that need looking up: not cached, or
    /// cached as not found long enough ago. Each once, in order. Songs with
    /// no catalog id are skipped.
    func idsToFetch(_ songs: [Song], cache: [String: ArtworkCacheEntry], now: Date) -> [String] {
        let ids = songs.compactMap { PlaylistSongMatcher.catalogID(of: $0) }
        return MusicKitCatalog.uniqued(ids).filter { id in
            guard let entry = cache[id] else { return true }
            return entry.url == nil && now.timeIntervalSince(entry.fetchedAt) >= retryNotFoundAfter
        }
    }

    /// Looks up `ids` and returns an entry for every one of them: its art,
    /// or `nil` if the catalog gave none. If the lookup fails, this throws
    /// and nothing should be cached, so the next try asks again.
    func fetch(_ ids: [String], now: Date) async throws -> [String: ArtworkCacheEntry] {
        guard !ids.isEmpty else { return [:] }
        let found = try await lookup.songs(catalogIDs: ids)
        return Dictionary(uniqueKeysWithValues: ids.map { id in
            (id, ArtworkCacheEntry(url: found[id]?.artworkURL, fetchedAt: now))
        })
    }

    /// `songs` with art from `urls` (by catalog id). Songs without an entry
    /// keep whatever they had.
    static func apply(_ urls: [String: URL], to songs: [Song]) -> [Song] {
        songs.map { song in
            guard let id = PlaylistSongMatcher.catalogID(of: song), let url = urls[id] else { return song }
            var song = song
            song.artworkURL = url
            return song
        }
    }

    static func apply(_ urls: [String: URL], to songs: [EraSong]) -> [EraSong] {
        let updated = apply(urls, to: songs.map(\.song))
        return zip(songs, updated).map { song, withArt in
            var song = song
            song.song = withArt
            return song
        }
    }

    /// A pipeline result with art on every song `urls` has a cover for.
    ///
    /// Applied before saving, so a sync saves songs with the art they
    /// already have rather than without it (which would change every
    /// moment, and then change it back when art is filled in again).
    static func apply(_ urls: [String: URL], to result: EraPipelineResult) -> EraPipelineResult {
        guard !urls.isEmpty else { return result }
        let eras = result.eras.map { era in
            var era = era
            era.addedSongs = apply(urls, to: era.addedSongs)
            return era
        }
        return EraPipelineResult(eras: eras, matches: result.matches.mapValues { apply(urls, to: $0) })
    }
}
