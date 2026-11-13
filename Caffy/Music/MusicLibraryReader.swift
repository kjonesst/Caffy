import Foundation
import MediaPlayer

/// One song in the user's music library, as it stood when the library was
/// read: who it's by, and how often and how recently it was played.
nonisolated struct LibrarySongSnapshot: Hashable, Sendable {
    /// The library's own id for the song. It can change after a library
    /// reset or an iCloud Music Library resync.
    let persistentID: UInt64
    /// The Apple Music catalog id, or `nil` for songs that aren't in the
    /// catalog (such as imported files).
    let catalogID: String?
    let title: String
    let artist: String
    var genre: String? = nil
    /// The song's length in seconds.
    var duration: TimeInterval = 0
    /// When the song was last played on any of the user's devices, as far as
    /// this device knows. `nil` if it has never been played.
    var lastPlayedDate: Date? = nil
    /// How many times the song has been played to the end.
    var playCount: Int = 0
    /// When the song was added to the library. Later plays don't change it,
    /// so it often reaches back years, but a library resync can reset it.
    /// `nil` when the library doesn't know.
    var dateAdded: Date? = nil
    /// How many times the song was skipped.
    var skipCount: Int = 0
    /// The library's id for the song's album, or `nil` when it has none.
    var albumID: UInt64? = nil
    var albumTitle: String? = nil

    init(
        persistentID: UInt64,
        catalogID: String?,
        title: String,
        artist: String,
        genre: String? = nil,
        duration: TimeInterval = 0,
        lastPlayedDate: Date? = nil,
        playCount: Int = 0,
        dateAdded: Date? = nil,
        skipCount: Int = 0,
        albumID: UInt64? = nil,
        albumTitle: String? = nil
    ) {
        self.persistentID = persistentID
        self.catalogID = Self.normalisedCatalogID(catalogID)
        self.title = title
        self.artist = artist
        self.genre = genre
        self.duration = duration
        self.lastPlayedDate = lastPlayedDate
        self.playCount = playCount
        self.dateAdded = dateAdded
        self.skipCount = skipCount
        // `albumPersistentID` is 0 for songs without an album.
        self.albumID = albumID == 0 ? nil : albumID
        self.albumTitle = albumTitle
    }

    /// The key that tracks this song between library reads.
    var key: String { String(persistentID) }

    /// The song as the rest of Caffy sees it. Its id is the catalog id when
    /// there is one, so the same song matches across a `persistentID` change,
    /// and `library-<persistentID>` otherwise.
    var song: Song {
        Song(
            id: catalogID ?? "library-\(persistentID)",
            title: title,
            artist: artist,
            genre: genre
        )
    }

    /// `playbackStoreID` is an empty string, or `"0"`, for songs that aren't
    /// in the catalog. Both mean "no catalog id".
    static func normalisedCatalogID(_ id: String?) -> String? {
        guard let id, !id.isEmpty, id != "0" else { return nil }
        return id
    }
}

/// Reads every song in the user's music library.
///
/// A protocol so listening history can be tested without a music library
/// (the simulator has none).
nonisolated protocol MusicLibraryReader: Sendable {
    /// Every song in the library, or `nil` when Caffy may not read it.
    func songs() async -> [LibrarySongSnapshot]?
}

/// Reads the music library with the MediaPlayer framework.
///
/// Unlike MusicKit, this needs no developer token, so it works with free
/// provisioning. It sees songs in the user's library only (including
/// iCloud Music Library songs when Sync Library is on), not catalog songs
/// played without being added.
nonisolated struct MediaPlayerLibraryReader: MusicLibraryReader {
    /// `@concurrent` so a large library is read off the main actor.
    @concurrent
    func songs() async -> [LibrarySongSnapshot]? {
        // Never prompts: onboarding owns the Apple Music prompt, which
        // covers the media library too.
        guard MPMediaLibrary.authorizationStatus() == .authorized else { return nil }
        let items = MPMediaQuery.songs().items ?? []
        return items.map { item in
            LibrarySongSnapshot(
                persistentID: item.persistentID,
                catalogID: item.playbackStoreID,
                title: item.title ?? "Unknown song",
                artist: item.artist ?? "Unknown artist",
                genre: item.genre,
                duration: item.playbackDuration,
                lastPlayedDate: item.lastPlayedDate,
                playCount: item.playCount,
                dateAdded: item.dateAdded,
                skipCount: item.skipCount,
                albumID: item.albumPersistentID,
                albumTitle: item.albumTitle
            )
        }
    }
}
