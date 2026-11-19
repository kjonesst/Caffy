import Foundation
import MusicKit

/// Looks songs up in the Apple Music catalog with MusicKit.
///
/// Needs the MusicKit developer token (the App ID's MusicKit service) and
/// Apple Music access.
nonisolated struct LiveCatalogSongLookup: CatalogSongLookup {
    var batchSize = MusicKitCatalog.defaultBatchSize

    func songs(catalogIDs: [String]) async throws -> [String: CatalogSong] {
        try await MusicKitCatalog.songs(catalogIDs, batchSize: batchSize).mapValues(MusicKitCatalog.catalogSong)
    }
}

/// MusicKit catalog reads shared by the live adapters.
nonisolated enum MusicKitCatalog {
    /// How many ids go in one catalog request. Not yet checked against the
    /// real limit (see docs/notes/musickit-findings.md).
    static let defaultBatchSize = 100

    /// The catalog songs for `ids`, by id. Repeated ids are fetched once, in
    /// batches of `batchSize`. Ids the catalog doesn't return are left out.
    static func songs(_ ids: [String], batchSize: Int) async throws -> [String: MusicKit.Song] {
        let unique = uniqued(ids)
        let size = max(batchSize, 1)
        var found: [String: MusicKit.Song] = [:]
        for start in stride(from: 0, to: unique.count, by: size) {
            let batch = unique[start..<min(start + size, unique.count)]
            let request = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, memberOf: batch.map { MusicItemID($0) })
            for song in try await request.response().items {
                found[song.id.rawValue] = song
            }
        }
        return found
    }

    /// The plain value Caffy keeps from a catalog song.
    static func catalogSong(_ song: MusicKit.Song) -> CatalogSong {
        CatalogSong(
            id: song.id.rawValue,
            title: song.title,
            artist: song.artistName,
            artworkURL: song.artwork?.url(width: 300, height: 300)
        )
    }

    /// `ids` without repeats, first appearance first.
    static func uniqued(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}
