import Foundation
import SwiftData

/// Saves the era pipeline's results into SwiftData, and loads frozen eras
/// back for the next run.
///
/// This is the only part of the era code that knows about SwiftData. The
/// pipeline works on plain values; this copies them into `Era`, `Moment` and
/// `CaffyPlaylist`, keeping existing objects wherever it can so playlists
/// and anything else attached to an era survive each sync.
@MainActor
struct EraStore {
    let context: ModelContext

    /// Every saved frozen era, oldest first, ready to pass to `EraPipeline.run`.
    func frozenEras() throws -> [FrozenEra] {
        let eras = try context.fetch(FetchDescriptor<Era>(predicate: #Predicate { $0.isFrozen }))
        return eras
            .compactMap(\.frozen)
            .sorted { ($0.draft.start, $0.draft.id) < ($1.draft.start, $1.draft.id) }
    }

    /// Makes the database match `result`.
    ///
    /// - Moments are matched by `momentID` and updated in place. Moments in
    ///   eras that were already frozen keep their songs, unless they were
    ///   never matched (`nil`).
    /// - An era that was already frozen takes its library additions once,
    ///   while it has none, and keeps them after that: `dateAdded` doesn't
    ///   change, so they're as stable as the rest of a frozen era.
    /// - Eras are matched by `eraID`, or else by sharing the most moments, so
    ///   an era whose first photo changed keeps its object and playlist.
    /// - Eras and moments that are no longer in the result are deleted,
    ///   including sample data from before the pipeline ran.
    /// - A playlist's `lastUpdated` moves to `now` only when its songs change.
    func save(_ result: EraPipelineResult, moments: [PhotoMoment], now: Date) throws {
        let storedEras = try context.fetch(FetchDescriptor<Era>())
        let storedMoments = try context.fetch(FetchDescriptor<Moment>())

        // Remember each era's moments and songs before anything moves.
        var momentIDsBefore: [PersistentIdentifier: Set<String>] = [:]
        var songIDsBefore: [PersistentIdentifier: Set<String>] = [:]
        for era in storedEras {
            momentIDsBefore[era.persistentModelID] = Set(era.moments.compactMap(\.momentID))
            songIDsBefore[era.persistentModelID] = Set(era.songs.map(\.id))
        }
        let lockedEraIDs = Set(storedEras.filter(\.isFrozen).compactMap(\.eraID))

        let moments = saveMoments(result, moments: moments, stored: storedMoments, lockedEraIDs: lockedEraIDs)

        var unmatched = storedEras.sorted { ($0.startDate, $0.eraID ?? "") < ($1.startDate, $1.eraID ?? "") }
        for built in result.eras {
            let era: Era
            if let index = matchIndex(for: built.draft, in: unmatched, momentIDsBefore: momentIDsBefore) {
                era = unmatched.remove(at: index)
            } else {
                era = Era(title: "", whenLabel: "", summary: "", startDate: built.draft.start, palette: built.palette)
                context.insert(era)
            }
            era.update(from: built)
            let isLocked = era.eraID.map(lockedEraIDs.contains) ?? false
            if !isLocked {
                era.assign(built.addedSongs, to: \.addedSongs)
            } else if (era.addedSongs ?? []).isEmpty && !built.addedSongs.isEmpty {
                era.addedSongs = built.addedSongs
            }
            for id in built.draft.momentIDs {
                // Set only when it moves, like `assign`, so an unchanged
                // moment isn't saved again.
                if let moment = moments[id], moment.era !== era {
                    moment.era = era
                }
            }

            let songIDs = Set(era.songs.map(\.id))
            if let playlist = era.playlist {
                playlist.assign(built.content.title, to: \.name)
                if songIDs != songIDsBefore[era.persistentModelID] {
                    playlist.lastUpdated = now
                }
            } else {
                era.playlist = CaffyPlaylist(name: built.content.title, lastUpdated: now)
            }
        }

        for era in unmatched {
            // Moments that moved to another era must not go with this one.
            era.moments.removeAll { $0.momentID.map { moments[$0] != nil } ?? false }
            context.delete(era)
        }
        try context.save()
    }

    /// Updates, adds and deletes moments to match the result. Returns the
    /// moments that belong to an era, by `momentID`.
    private func saveMoments(
        _ result: EraPipelineResult,
        moments: [PhotoMoment],
        stored: [Moment],
        lockedEraIDs: Set<String>
    ) -> [String: Moment] {
        var eraOfMoment: [String: String] = [:]
        for era in result.eras {
            for id in era.draft.momentIDs { eraOfMoment[id] = era.draft.id }
        }

        var existing: [String: Moment] = [:]
        for moment in stored {
            if let id = moment.momentID, existing[id] == nil, eraOfMoment[id] != nil {
                existing[id] = moment
            } else if moment.momentID != nil {
                // Gone from the library or no longer in any era (or a duplicate).
                context.delete(moment)
            }
            // Moments without an id are sample data; they go with their era.
        }

        var saved: [String: Moment] = [:]
        for photo in moments.sorted(by: { ($0.start, $0.id) < ($1.start, $1.id) }) {
            guard let eraID = eraOfMoment[photo.id], saved[photo.id] == nil else { continue }
            let matches = result.matches[photo.id]
            if let moment = existing[photo.id] {
                moment.update(from: photo)
                // A frozen era's songs stay as they are, except that a moment
                // never matched may still get some: it may have frozen before
                // its listening was recorded (or before listening was
                // connected at all), and would otherwise stay empty for good.
                if !lockedEraIDs.contains(eraID) || moment.songs == nil {
                    moment.setMatches(matches)
                }
                saved[photo.id] = moment
            } else {
                let moment = Moment(date: photo.start, songs: nil)
                moment.setMatches(matches)
                moment.update(from: photo)
                context.insert(moment)
                saved[photo.id] = moment
            }
        }
        return saved
    }

    // MARK: - One-off fixes

    /// The `UserDefaults` key (shared with `@AppStorage`) recording that
    /// `resetEmptyFrozenMomentSongs()` has run.
    static let resetEmptyFrozenMomentSongsKey = "didResetEmptyFrozenMomentSongs"

    /// Before moment songs could be `nil`, a moment that froze before any
    /// listening was recorded was saved with `[]`, which now means "matched,
    /// nothing found", so it would never get songs. This sets those back to
    /// `nil`, once: afterwards `[]` means what it says.
    func resetEmptyFrozenMomentSongsOnce(defaults: UserDefaults) throws {
        guard !defaults.bool(forKey: Self.resetEmptyFrozenMomentSongsKey) else { return }
        try resetEmptyFrozenMomentSongs()
        defaults.set(true, forKey: Self.resetEmptyFrozenMomentSongsKey)
    }

    /// Sets every frozen moment with empty songs back to never matched.
    /// Returns how many changed.
    @discardableResult
    func resetEmptyFrozenMomentSongs() throws -> Int {
        let eras = try context.fetch(FetchDescriptor<Era>(predicate: #Predicate { $0.isFrozen }))
        var reset = 0
        for moment in eras.flatMap(\.moments) where moment.songs?.isEmpty == true {
            moment.setMatches(nil)
            reset += 1
        }
        if reset > 0 { try context.save() }
        return reset
    }

    /// The stored era to reuse for `draft`: the one with the same id, or else
    /// the one sharing the most moments (earliest first on a tie).
    private func matchIndex(
        for draft: EraDraft,
        in candidates: [Era],
        momentIDsBefore: [PersistentIdentifier: Set<String>]
    ) -> Int? {
        if let index = candidates.firstIndex(where: { $0.eraID == draft.id }) {
            return index
        }
        let wanted = Set(draft.momentIDs)
        var best: (index: Int, overlap: Int)?
        for (index, era) in candidates.enumerated() {
            let overlap = momentIDsBefore[era.persistentModelID]?.intersection(wanted).count ?? 0
            if overlap > (best?.overlap ?? 0) {
                best = (index, overlap)
            }
        }
        return best?.index
    }
}
