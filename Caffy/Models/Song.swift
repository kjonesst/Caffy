import Foundation

/// A lightweight description of a song.
///
/// This is a plain `struct` (a value type), not a SwiftData model: songs belong to
/// Apple Music, so Caffy only keeps a small reference to each one. Because it's
/// `Codable`, SwiftData can store arrays of songs directly inside `Moment`.
///
/// `nonisolated` lets SwiftData encode and decode songs from any thread, instead of
/// tying the type to the main actor (this project's default).
nonisolated struct Song: Codable, Hashable, Identifiable {
    /// A stable identifier. Later this will be the Apple Music catalog ID.
    let id: String
    let title: String
    let artist: String

    /// Cover art. `nil` shows a placeholder tile.
    var artworkURL: URL? = nil

    /// The song's main genre, used to draw the genre river.
    var genre: String? = nil
}
