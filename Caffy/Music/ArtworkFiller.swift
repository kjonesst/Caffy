import Foundation
import SwiftData

/// Puts catalog cover art on the songs Caffy has saved, and remembers it.
///
/// After each sync, `fill(now:)` finds saved songs without art, looks up only
/// the ones not already cached, caches the answers in `CatalogArtwork`, and
/// writes the art onto moments' songs and eras' library additions. Before
/// the next save, `cachedURLs()` lets the sync put the same art on the
/// pipeline's songs, so nothing changes needlessly.
///
/// The context's container must include both stores (`CaffyStore`).
@MainActor
struct ArtworkFiller {
    let context: ModelContext
    let resolver: ArtworkResolver

    /// Every cached cover, by catalog id.
    func cachedURLs() throws -> [String: URL] {
        try cache().compactMapValues(\.url)
    }

    /// Looks up missing art and puts it on saved songs. Returns how many
    /// songs got art. Throws if the lookup fails; nothing is cached then.
    @discardableResult
    func fill(now: Date) async throws -> Int {
        let missing = try songsWithoutArt()
        guard !missing.isEmpty else { return 0 }

        var cache = try cache()
        let fetched = try await resolver.fetch(resolver.idsToFetch(missing, cache: cache, now: now), now: now)
        if !fetched.isEmpty {
            try store(fetched)
            cache.merge(fetched) { _, new in new }
        }
        return try applyToSavedSongs(cache.compactMapValues(\.url))
    }

    // MARK: - Saved songs

    private func songsWithoutArt() throws -> [Song] {
        let momentSongs = try context.fetch(FetchDescriptor<Moment>()).flatMap { $0.songs ?? [] }
        let addedSongs = try context.fetch(FetchDescriptor<Era>()).flatMap { ($0.addedSongs ?? []).map(\.song) }
        return (momentSongs + addedSongs).filter { $0.artworkURL == nil }
    }

    /// Writes art onto saved songs, only where it changes anything.
    private func applyToSavedSongs(_ urls: [String: URL]) throws -> Int {
        guard !urls.isEmpty else { return 0 }
        var changed = 0
        for moment in try context.fetch(FetchDescriptor<Moment>()) {
            guard let songs = moment.songs else { continue }
            let updated = ArtworkResolver.apply(urls, to: songs)
            changed += zip(songs, updated).count { $0.artworkURL != $1.artworkURL }
            moment.assign(updated, to: \.songs)
        }
        for era in try context.fetch(FetchDescriptor<Era>()) {
            guard let added = era.addedSongs else { continue }
            let updated = ArtworkResolver.apply(urls, to: added)
            changed += zip(added, updated).count { $0.song.artworkURL != $1.song.artworkURL }
            era.assign(updated, to: \.addedSongs)
        }
        if context.hasChanges { try context.save() }
        return changed
    }

    // MARK: - Cache

    private func cache() throws -> [String: ArtworkCacheEntry] {
        let records = try context.fetch(FetchDescriptor<CatalogArtwork>())
        return Dictionary(records.map { ($0.catalogID, $0.entry) }, uniquingKeysWith: { first, _ in first })
    }

    private func store(_ entries: [String: ArtworkCacheEntry]) throws {
        let existing = try context.fetch(FetchDescriptor<CatalogArtwork>())
        let byID = Dictionary(existing.map { ($0.catalogID, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, entry) in entries {
            if let record = byID[id] {
                record.assign(entry.url, to: \.url)
                record.assign(entry.fetchedAt, to: \.fetchedAt)
            } else {
                context.insert(CatalogArtwork(catalogID: id, url: entry.url, fetchedAt: entry.fetchedAt))
            }
        }
        try context.save()
    }
}
