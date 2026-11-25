import Foundation
import SwiftData

/// Cover art Caffy has looked up for one Apple Music catalog song.
///
/// Kept in the listening history store, which is never rebuilt, so a
/// rebuild of the eras doesn't look every cover up again. A `nil` url means
/// the catalog had no art for the song, or didn't return it; that's tried
/// again after a while (`ArtworkResolver.retryNotFoundAfter`).
///
/// Main-actor bound like the era models, since only `ArtworkFiller` (on the
/// main actor) reads and writes it.
@Model
final class CatalogArtwork {
    @Attribute(.unique) var catalogID: String
    var url: URL?
    var fetchedAt: Date
    /// Whether the catalog returned the song at all, so publishing knows
    /// which songs can go into a playlist without asking again. `nil` for
    /// entries saved before this was recorded (see `ArtworkCacheEntry.inCatalog`).
    var isInCatalog: Bool?

    init(catalogID: String, entry: ArtworkCacheEntry) {
        self.catalogID = catalogID
        url = entry.url
        fetchedAt = entry.fetchedAt
        isInCatalog = entry.isInCatalog
    }

    var entry: ArtworkCacheEntry {
        ArtworkCacheEntry(url: url, fetchedAt: fetchedAt, isInCatalog: isInCatalog)
    }

    func update(from entry: ArtworkCacheEntry) {
        assign(entry.url, to: \.url)
        assign(entry.fetchedAt, to: \.fetchedAt)
        assign(entry.isInCatalog, to: \.isInCatalog)
    }
}
