import Foundation
import SwiftData

/// What Caffy last saw of one library song: the counts the next read is
/// compared against to find new plays.
@Model
nonisolated final class LibrarySongState {
    /// `LibrarySongSnapshot.key`: the song's `persistentID`.
    @Attribute(.unique) var key: String
    var lastPlayedDate: Date?
    var playCount: Int
    /// The first time Caffy saw this song.
    var firstSeenAt: Date
    /// The last time its counts changed (or it was first seen).
    var updatedAt: Date

    init(key: String, lastPlayedDate: Date?, playCount: Int, firstSeenAt: Date) {
        self.key = key
        self.lastPlayedDate = lastPlayedDate
        self.playCount = playCount
        self.firstSeenAt = firstSeenAt
        updatedAt = firstSeenAt
    }
}

/// One play Caffy worked out by comparing library reads.
@Model
nonisolated final class RecordedPlay {
    /// `song.id`, as its own column so plays can be looked up by song.
    var songID: String
    var song: Song
    var start: Date
    var end: Date
    /// The play happened somewhere between `start` and `end`, not over all
    /// of it. See `ListeningEvent`.
    var isEstimated: Bool
    /// `false` when the window is too long to match to a moment.
    var isMatchable: Bool
    /// A last-played date from before recording began, not a play Caffy saw
    /// happen. See `ListeningEvent.isSeeded`.
    var isSeeded: Bool = false
    var recordedAt: Date

    init(_ event: ListeningEvent, recordedAt: Date) {
        songID = event.song.id
        song = event.song
        start = event.interval.start
        end = event.interval.end
        isEstimated = event.isEstimated
        isMatchable = event.isMatchable
        isSeeded = event.isSeeded
        self.recordedAt = recordedAt
    }

    var event: ListeningEvent {
        ListeningEvent(song: song, interval: DateInterval(start: start, end: max(start, end)), isEstimated: isEstimated, isMatchable: isMatchable, isSeeded: isSeeded)
    }
}

/// One read of the music library by `ListeningRecorder`.
///
/// The latest one says when the library was last looked at, which bounds the
/// window that new plays found by the next read can fall in.
@Model
nonisolated final class ListeningCheck {
    var at: Date
    var songCount: Int
    /// Observed exact plays. Checks saved before seeded plays were told
    /// apart count seeded ones here too.
    var newExactPlays: Int
    var newEstimatedPlays: Int
    /// Last-played dates from before recording (see `ListeningEvent.isSeeded`).
    var newSeededPlays: Int = 0

    init(at: Date, songCount: Int, newExactPlays: Int, newEstimatedPlays: Int, newSeededPlays: Int = 0) {
        self.at = at
        self.songCount = songCount
        self.newExactPlays = newExactPlays
        self.newEstimatedPlays = newEstimatedPlays
        self.newSeededPlays = newSeededPlays
    }
}

/// Where recorded listening history is kept.
///
/// History can't be rebuilt: it only exists from the day recording started.
/// So it lives in its own store, apart from the eras and moments the pipeline
/// derives (and may one day clear with "Rebuild eras"). Only "Delete all
/// data" should clear it, through `deleteAll(in:)`.
nonisolated enum ListeningHistoryStore {
    static let models: [any PersistentModel.Type] = [LibrarySongState.self, RecordedPlay.self, ListeningCheck.self]

    /// The store's configuration.
    ///
    /// It stays `cloudKitDatabase: .none` for good, even if eras sync through
    /// iCloud one day. iCloud Music Library already syncs play counts between
    /// devices, so two devices recording into one history would count each
    /// play twice, and their estimated windows wouldn't line up closely
    /// enough to remove the copies. Keeping it local is also what makes
    /// `@Attribute(.unique)` safe here (CloudKit doesn't allow it).
    static func configuration(inMemory: Bool = false) -> ModelConfiguration {
        ModelConfiguration(
            "ListeningHistory",
            schema: Schema(models),
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
    }

    /// Clears all recorded listening history. For "Delete all data" only.
    static func deleteAll(in context: ModelContext) throws {
        try context.delete(model: RecordedPlay.self)
        try context.delete(model: LibrarySongState.self)
        try context.delete(model: ListeningCheck.self)
        try context.save()
    }

    // MARK: - One-off fixes

    /// The `UserDefaults` key (shared with `@AppStorage`) recording that
    /// `markSeededPlays(in:)` has run.
    static let markSeededPlaysKey = "didMarkSeededPlays"

    /// Plays recorded before seeded plays were told apart were all saved as
    /// observed. This marks the ones that must be seeded, once.
    static func markSeededPlaysOnce(in context: ModelContext, defaults: UserDefaults) throws {
        guard !defaults.bool(forKey: markSeededPlaysKey) else { return }
        try markSeededPlays(in: context)
        defaults.set(true, forKey: markSeededPlaysKey)
    }

    /// Marks every play that ends before recording began as seeded: the
    /// recorder can't have seen a play from before it first read the library.
    /// Recording began at the earliest `LibrarySongState.firstSeenAt`. Running
    /// it again changes nothing. Returns how many plays changed.
    @discardableResult
    static func markSeededPlays(in context: ModelContext) throws -> Int {
        var first = FetchDescriptor<LibrarySongState>(sortBy: [SortDescriptor(\.firstSeenAt)])
        first.fetchLimit = 1
        guard let recordingStart = try context.fetch(first).first?.firstSeenAt else { return 0 }
        let plays = try context.fetch(FetchDescriptor<RecordedPlay>(
            predicate: #Predicate { $0.end < recordingStart && !$0.isSeeded }
        ))
        for play in plays {
            play.isSeeded = true
        }
        if !plays.isEmpty { try context.save() }
        return plays.count
    }
}

/// Caffy's database: the derived store (eras, moments, places, playlists) and
/// the listening history store, in one container.
nonisolated enum CaffyStore {
    /// Everything the era pipeline derives. Safe to clear and rebuild.
    static let derivedModels: [any PersistentModel.Type] = [Era.self, Moment.self, Place.self, CaffyPlaylist.self]

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        // No name, so the derived store keeps the file it had before
        // listening history had a store of its own.
        let derived = ModelConfiguration(schema: Schema(derivedModels), isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: Schema(derivedModels + ListeningHistoryStore.models),
            configurations: derived, ListeningHistoryStore.configuration(inMemory: inMemory)
        )
    }
}
