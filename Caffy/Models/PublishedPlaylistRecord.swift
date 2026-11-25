import Foundation
import SwiftData

/// Which Apple Music playlist Caffy published for an era.
///
/// Kept in the listening history store, which is never rebuilt, rather than
/// with the eras, which can be. Without it, clearing the derived store would
/// forget which library playlists are Caffy's, and the next publish would
/// make duplicates of them. Eras are matched by `eraID`, which stays the same
/// while an era grows.
///
/// Main-actor bound like the era models, since only `PlaylistLedger` (on
/// the main actor) reads and writes it.
@Model
final class PublishedPlaylistRecord {
    @Attribute(.unique) var eraID: String
    var playlistID: String
    var url: URL?
    /// The name it was published under.
    var name: String
    /// The catalog ids last published, in order.
    var songIDs: [String]
    var publishedAt: Date
    /// The photo added to the "Caffinated" album as this playlist's cover
    /// (see `CoverAlbum`). Kept so it's added once, and stays the same photo
    /// even as the era's newest photo changes. `nil` until added.
    var coverPhotoID: String?

    init(eraID: String, link: PlaylistLink) {
        self.eraID = eraID
        playlistID = link.playlistID
        url = link.url
        name = link.name
        songIDs = link.songIDs
        publishedAt = link.publishedAt
    }

    var link: PlaylistLink {
        PlaylistLink(playlistID: playlistID, url: url, name: name, songIDs: songIDs, publishedAt: publishedAt)
    }

    func update(from link: PlaylistLink) {
        assign(link.playlistID, to: \.playlistID)
        assign(link.url, to: \.url)
        assign(link.name, to: \.name)
        assign(link.songIDs, to: \.songIDs)
        assign(link.publishedAt, to: \.publishedAt)
    }
}
