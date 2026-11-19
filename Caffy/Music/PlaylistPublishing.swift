import Foundation

/// One track in a published playlist, as the library reports it back.
///
/// `id` is the library's id for the track, which isn't the catalog id the
/// song was added with, so tracks are compared by title and artist.
nonisolated struct PublishedTrack: Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
}

/// A playlist in the user's Apple Music library, as Caffy last saw it.
nonisolated struct PublishedPlaylist: Hashable, Sendable {
    /// The library's id for the playlist. Caffy keeps it to find the
    /// playlist again; names can repeat, so it never looks one up by name.
    let id: String
    var name: String
    /// A link that opens the playlist in Apple Music, when MusicKit gives one.
    var url: URL?
    /// In playlist order.
    var tracks: [PublishedTrack]
}

nonisolated enum PlaylistPublishingError: Error, Equatable {
    /// No playlist in the library has this id, for example because the user
    /// deleted it.
    case playlistNotFound(id: String)
    /// These catalog ids didn't come back from the catalog.
    case songsNotInCatalog(ids: [String])
}

/// Writes Caffy's playlists into the user's Apple Music library.
///
/// A protocol, like `ListeningSource`, so publishing can be tested without a
/// library: `LivePlaylistPublisher` is the real one, and tests use a fake.
/// Songs go in as Apple Music catalog ids, in playlist order.
///
/// Caffy only ever changes playlists it created, so every call but `create`
/// takes the id `create` returned.
nonisolated protocol PlaylistPublishing: Sendable {
    func create(name: String, description: String?, catalogIDs: [String]) async throws -> PublishedPlaylist

    /// The playlist as it is now, or `nil` when no playlist has this id.
    func playlist(id: String) async throws -> PublishedPlaylist?

    /// Sets the playlist's tracks to exactly `catalogIDs`.
    func replaceTracks(of id: String, with catalogIDs: [String]) async throws -> PublishedPlaylist

    func rename(_ id: String, to name: String) async throws -> PublishedPlaylist
}

/// What Caffy remembers about a playlist it published: enough to find it
/// again and to tell whether it needs updating.
nonisolated struct PlaylistLink: Hashable, Sendable {
    var playlistID: String
    var url: URL?
    var name: String
    /// The catalog ids last published, in order.
    var songIDs: [String]
    var publishedAt: Date
}

/// How a publish went.
nonisolated enum PlaylistPublishOutcome: Equatable, Sendable {
    case created(PlaylistLink)
    case updated(PlaylistLink, renamed: Bool, tracksReplaced: Bool)
    /// Name and songs were already as published, so nothing was written.
    case unchanged(PlaylistLink)
    /// The linked playlist is gone from the library. It isn't made again:
    /// the user may have deleted it on purpose.
    case missing(PlaylistLink)
    /// No songs and no playlist yet, so none is made.
    case nothingToPublish

    /// The link to keep afterwards, if any.
    var link: PlaylistLink? {
        switch self {
        case .created(let link), .updated(let link, _, _), .unchanged(let link): link
        case .missing, .nothingToPublish: nil
        }
    }
}

/// Decides how to bring one playlist up to date, and does it.
///
/// Writes only what changed: nothing when the name and songs match what was
/// published, a rename and/or a full track replacement otherwise. A new
/// playlist is only made when there's no link yet and there are songs.
nonisolated struct PlaylistSync: Sendable {
    let publisher: any PlaylistPublishing

    func publish(
        name: String,
        description: String?,
        songIDs: [String],
        link: PlaylistLink?,
        now: Date
    ) async throws -> PlaylistPublishOutcome {
        guard let link else {
            guard !songIDs.isEmpty else { return .nothingToPublish }
            let created = try await publisher.create(name: name, description: description, catalogIDs: songIDs)
            return .created(PlaylistLink(
                playlistID: created.id, url: created.url, name: created.name, songIDs: songIDs, publishedAt: now
            ))
        }

        let renames = link.name != name
        let replacesTracks = link.songIDs != songIDs
        guard renames || replacesTracks else { return .unchanged(link) }
        guard try await publisher.playlist(id: link.playlistID) != nil else { return .missing(link) }

        var updated = link
        if replacesTracks {
            let playlist = try await publisher.replaceTracks(of: link.playlistID, with: songIDs)
            updated.songIDs = songIDs
            updated.url = playlist.url ?? updated.url
        }
        if renames {
            let playlist = try await publisher.rename(link.playlistID, to: name)
            updated.name = playlist.name
            updated.url = playlist.url ?? updated.url
        }
        updated.publishedAt = now
        return .updated(updated, renamed: renames, tracksReplaced: replacesTracks)
    }
}
