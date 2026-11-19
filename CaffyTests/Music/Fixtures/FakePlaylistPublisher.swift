import Foundation
@testable import Caffy

/// An Apple Music library of playlists, kept in memory. Records every call,
/// so tests can check what was written and that nothing else was.
actor FakePlaylistPublisher: PlaylistPublishing {
    enum Call: Equatable {
        case create(name: String, catalogIDs: [String])
        case fetch(id: String)
        case replaceTracks(id: String, catalogIDs: [String])
        case rename(id: String, name: String)
    }

    private(set) var calls: [Call] = []
    private(set) var playlists: [String: PublishedPlaylist] = [:]
    private var nextID = 1

    /// The calls that changed the library (everything but fetches).
    var writes: [Call] {
        calls.filter { if case .fetch = $0 { false } else { true } }
    }

    /// Removes a playlist, as if the user deleted it in Apple Music.
    func delete(_ id: String) {
        playlists[id] = nil
    }

    func create(name: String, description: String?, catalogIDs: [String]) async throws -> PublishedPlaylist {
        calls.append(.create(name: name, catalogIDs: catalogIDs))
        let id = "p.\(nextID)"
        nextID += 1
        let playlist = PublishedPlaylist(
            id: id, name: name, url: URL(string: "https://music.example/\(id)"), tracks: Self.tracks(catalogIDs)
        )
        playlists[id] = playlist
        return playlist
    }

    func playlist(id: String) async throws -> PublishedPlaylist? {
        calls.append(.fetch(id: id))
        return playlists[id]
    }

    func replaceTracks(of id: String, with catalogIDs: [String]) async throws -> PublishedPlaylist {
        calls.append(.replaceTracks(id: id, catalogIDs: catalogIDs))
        guard var playlist = playlists[id] else { throw PlaylistPublishingError.playlistNotFound(id: id) }
        playlist.tracks = Self.tracks(catalogIDs)
        playlists[id] = playlist
        return playlist
    }

    func rename(_ id: String, to name: String) async throws -> PublishedPlaylist {
        calls.append(.rename(id: id, name: name))
        guard var playlist = playlists[id] else { throw PlaylistPublishingError.playlistNotFound(id: id) }
        playlist.name = name
        playlists[id] = playlist
        return playlist
    }

    private static func tracks(_ ids: [String]) -> [PublishedTrack] {
        ids.map { PublishedTrack(id: "i.\($0)", title: "Title \($0)", artist: "Artist \($0)") }
    }
}

/// A catalog that knows a fixed set of songs. Records each lookup.
actor FakeCatalogLookup: CatalogSongLookup {
    private let known: [String: CatalogSong]
    private(set) var lookups: [[String]] = []

    /// A catalog with a song for each id, titled after it.
    init(knowing ids: [String]) {
        known = Dictionary(uniqueKeysWithValues: ids.map {
            ($0, CatalogSong(id: $0, title: "Title \($0)", artist: "Artist \($0)", artworkURL: URL(string: "https://art.example/\($0).jpg")))
        })
    }

    func songs(catalogIDs: [String]) async throws -> [String: CatalogSong] {
        lookups.append(catalogIDs)
        return known.filter { catalogIDs.contains($0.key) }
    }
}

extension EraSong {
    /// A near-play era song with the given id.
    static func fixture(_ id: String, evidence: SongEvidence = .nearPlay) -> EraSong {
        EraSong(song: Song(id: id, title: "Song \(id)", artist: "Artist \(id)"), evidence: evidence, score: 1)
    }
}
