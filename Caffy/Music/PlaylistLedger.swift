import Foundation
import SwiftData

/// Keeps track of which Apple Music playlist belongs to which era.
///
/// Each link is saved twice: on the era's `CaffyPlaylist`, which views read,
/// and in a `PublishedPlaylistRecord`, which survives a rebuild of the
/// derived store. After a sync, `relinkPlaylists()` copies records back onto
/// playlists that lost their link.
///
/// The context's container must include both stores (`CaffyStore`).
@MainActor
struct PlaylistLedger {
    let context: ModelContext

    /// The saved link for an era, from the durable record.
    func link(forEraID eraID: String) throws -> PlaylistLink? {
        try record(forEraID: eraID)?.link
    }

    /// Saves a link for an era: the durable record, and the era's playlist
    /// if the era is in the database.
    func save(_ link: PlaylistLink, forEraID eraID: String) throws {
        if let record = try record(forEraID: eraID) {
            record.update(from: link)
        } else {
            context.insert(PublishedPlaylistRecord(eraID: eraID, link: link))
        }
        let eras = try context.fetch(FetchDescriptor<Era>(predicate: #Predicate { $0.eraID == eraID }))
        for era in eras {
            era.playlist?.apply(link)
        }
        try context.save()
    }

    /// Gives every era playlist the link its record holds, where it differs.
    /// Returns how many playlists changed.
    @discardableResult
    func relinkPlaylists() throws -> Int {
        let records = try context.fetch(FetchDescriptor<PublishedPlaylistRecord>())
        guard !records.isEmpty else { return 0 }
        let byEra = Dictionary(records.map { ($0.eraID, $0.link) }, uniquingKeysWith: { first, _ in first })
        var changed = 0
        for era in try context.fetch(FetchDescriptor<Era>()) {
            guard let eraID = era.eraID, let link = byEra[eraID], let playlist = era.playlist else { continue }
            if playlist.link?.playlistID != link.playlistID
                || playlist.appleMusicURL != link.url
                || playlist.publishedSongIDs != link.songIDs {
                playlist.apply(link)
                changed += 1
            }
        }
        if changed > 0 { try context.save() }
        return changed
    }

    /// The photo already put in the cover album for an era's playlist.
    func coverPhotoID(forEraID eraID: String) throws -> String? {
        try record(forEraID: eraID)?.coverPhotoID
    }

    /// Records the photo put in the cover album. Needs a saved link first.
    func setCoverPhotoID(_ photoID: String, forEraID eraID: String) throws {
        guard let record = try record(forEraID: eraID) else { return }
        record.assign(photoID, to: \.coverPhotoID)
        try context.save()
    }

    private func record(forEraID eraID: String) throws -> PublishedPlaylistRecord? {
        var descriptor = FetchDescriptor<PublishedPlaylistRecord>(predicate: #Predicate { $0.eraID == eraID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
