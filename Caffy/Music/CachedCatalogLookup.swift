import Foundation

/// A catalog lookup that answers from the artwork cache first.
///
/// Each sync's artwork pass already asks the catalog about every saved song
/// and caches whether it was found (`CatalogArtwork`). So when a pill is
/// tapped, most of an era's songs are already known, and only songs never
/// looked up go to `live`. That keeps publishing to one network step: the
/// publisher's own fetch of the songs to add.
nonisolated struct CachedCatalogLookup: CatalogSongLookup {
    let cache: [String: ArtworkCacheEntry]
    let live: any CatalogSongLookup
    /// Caffy's own copies of the songs, by catalog id, for the titles and
    /// artists of cached answers (the cache keeps only art and presence).
    let songs: [String: Song]

    init(cache: [String: ArtworkCacheEntry], live: any CatalogSongLookup, songs: [Song]) {
        self.cache = cache
        self.live = live
        self.songs = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func songs(catalogIDs: [String]) async throws -> [String: CatalogSong] {
        var found: [String: CatalogSong] = [:]
        var unknown: [String] = []
        for id in MusicKitCatalog.uniqued(catalogIDs) {
            switch cache[id]?.inCatalog {
            case true?:
                let song = songs[id]
                found[id] = CatalogSong(id: id, title: song?.title ?? "", artist: song?.artist ?? "", artworkURL: cache[id]?.url)
            case false?:
                continue
            case nil:
                unknown.append(id)
            }
        }
        if !unknown.isEmpty {
            found.merge(try await live.songs(catalogIDs: unknown)) { cached, _ in cached }
        }
        return found
    }
}
