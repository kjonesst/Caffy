import Foundation
import SwiftData

/// The playlist Caffy creates and keeps up to date for an era.
///
/// Once published, it's mirrored into the user's Apple Music library and
/// the `appleMusic…` fields say which playlist there it is. This model lives
/// in the derived store, which can be cleared and rebuilt, so the same link
/// is also kept in a `PublishedPlaylistRecord`, which survives that (see
/// `PlaylistLedger`).
///
/// Fields added after the first release are optional, so an existing
/// database gains them on its own when the app updates.
@Model
final class CaffyPlaylist {
    var name: String
    var lastUpdated: Date

    /// The era this playlist is built from. The other side of `Era.playlist`.
    var era: Era?

    /// The Apple Music library playlist's id. `nil` until published.
    var appleMusicID: String?
    /// Opens the playlist in Apple Music, when MusicKit gave a link.
    var appleMusicURL: URL?
    /// The catalog ids last published, in order.
    var publishedSongIDs: [String]?
    var lastPublished: Date?

    init(name: String, lastUpdated: Date) {
        self.name = name
        self.lastUpdated = lastUpdated
    }

    var songs: [Song] { era?.songs.map(\.song) ?? [] }

    /// The published playlist this one is linked to, or `nil` if it isn't.
    /// `name` is the name it was published under.
    var link: PlaylistLink? {
        guard let appleMusicID else { return nil }
        return PlaylistLink(
            playlistID: appleMusicID,
            url: appleMusicURL,
            name: name,
            songIDs: publishedSongIDs ?? [],
            publishedAt: lastPublished ?? lastUpdated
        )
    }

    /// Links this playlist to a published one. Only what changed is set.
    func apply(_ link: PlaylistLink) {
        assign(link.playlistID, to: \.appleMusicID)
        assign(link.url, to: \.appleMusicURL)
        assign(link.songIDs, to: \.publishedSongIDs)
        assign(link.publishedAt, to: \.lastPublished)
    }
}
