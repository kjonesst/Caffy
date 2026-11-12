import Foundation

/// Why a real `ListeningSource` couldn't answer.
nonisolated enum ListeningSourceError: Error, Equatable {
    /// Caffy may not read the music library.
    case noAccess
}

/// Plays straight from the music library's "last played" dates, with no
/// saved history: one play per song, at the last time it was played.
///
/// This is all the library says without Caffy recording anything, so it's
/// the baseline the coverage report compares recorded history against.
nonisolated struct MediaPlayerListeningSource: ListeningSource {
    let reader: any MusicLibraryReader

    func plays(in interval: DateInterval) async throws -> [ListeningEvent] {
        guard let songs = await reader.songs() else { throw ListeningSourceError.noAccess }
        return Self.plays(from: songs).filter { $0.interval.intersects(interval) }
    }

    /// One exact play with no length at each song's `lastPlayedDate`, oldest
    /// first. A moment's match window is much longer than a song, so it
    /// doesn't matter whether the date marks the start or the end of a play.
    static func plays(from songs: [LibrarySongSnapshot]) -> [ListeningEvent] {
        songs
            .compactMap { song in
                song.lastPlayedDate.map { ListeningEvent(song: song.song, interval: DateInterval(start: $0, duration: 0)) }
            }
            .sorted { ($0.interval.start, $0.song.id) < ($1.interval.start, $1.song.id) }
    }
}
