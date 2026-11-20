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

    init(catalogID: String, url: URL?, fetchedAt: Date) {
        self.catalogID = catalogID
        self.url = url
        self.fetchedAt = fetchedAt
    }

    var entry: ArtworkCacheEntry {
        ArtworkCacheEntry(url: url, fetchedAt: fetchedAt)
    }
}
