import Foundation
import MusicKit

/// Publishes playlists into the user's Apple Music library with MusicKit's
/// `MusicLibrary`.
///
/// Needs the MusicKit developer token and Apple Music access, and only works
/// on a device with Sync Library on. Each call looks the playlist up again by
/// id, so a playlist renamed in Apple Music is still found.
nonisolated struct LivePlaylistPublisher: PlaylistPublishing {
    var batchSize = MusicKitCatalog.defaultBatchSize

    func create(name: String, description: String?, catalogIDs: [String]) async throws -> PublishedPlaylist {
        let songs = try await orderedSongs(catalogIDs)
        let playlist = try await MusicLibrary.shared.createPlaylist(name: name, description: description, items: songs)
        return try await Self.published(playlist)
    }

    func playlist(id: String) async throws -> PublishedPlaylist? {
        guard let playlist = try await Self.libraryPlaylist(id: id) else { return nil }
        return try await Self.published(playlist)
    }

    func replaceTracks(of id: String, with catalogIDs: [String]) async throws -> PublishedPlaylist {
        guard let playlist = try await Self.libraryPlaylist(id: id) else {
            throw PlaylistPublishingError.playlistNotFound(id: id)
        }
        let songs = try await orderedSongs(catalogIDs)
        let edited = try await MusicLibrary.shared.edit(playlist, items: songs)
        return try await Self.published(edited)
    }

    func rename(_ id: String, to name: String) async throws -> PublishedPlaylist {
        guard let playlist = try await Self.libraryPlaylist(id: id) else {
            throw PlaylistPublishingError.playlistNotFound(id: id)
        }
        let edited = try await MusicLibrary.shared.edit(playlist, name: name)
        return try await Self.published(edited)
    }

    /// The catalog songs for `ids`, in the same order, repeats included.
    /// Throws if any id isn't in the catalog, so a playlist is never written
    /// with songs silently missing.
    private func orderedSongs(_ ids: [String]) async throws -> [MusicKit.Song] {
        let found = try await MusicKitCatalog.songs(ids, batchSize: batchSize)
        let missing = MusicKitCatalog.uniqued(ids.filter { found[$0] == nil })
        guard missing.isEmpty else { throw PlaylistPublishingError.songsNotInCatalog(ids: missing) }
        return ids.compactMap { found[$0] }
    }

    private static func libraryPlaylist(id: String) async throws -> Playlist? {
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(id))
        return try await request.response().items.first
    }

    /// The playlist with all its tracks loaded, every page of them.
    private static func published(_ playlist: Playlist) async throws -> PublishedPlaylist {
        let detailed = try await playlist.with([.tracks], preferredSource: .library)
        var tracks: [Track] = []
        var page = detailed.tracks
        while let current = page {
            tracks.append(contentsOf: current)
            page = current.hasNextBatch ? try await current.nextBatch() : nil
        }
        return PublishedPlaylist(
            id: detailed.id.rawValue,
            name: detailed.name,
            url: detailed.url,
            tracks: tracks.map { PublishedTrack(id: $0.id.rawValue, title: $0.title, artist: $0.artistName) }
        )
    }
}
