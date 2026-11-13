import Foundation
import SwiftData

/// What one recording pass found.
nonisolated struct RecordSummary: Equatable, Sendable {
    let songCount: Int
    let newExactPlays: Int
    let newEstimatedPlays: Int

    var newPlays: Int { newExactPlays + newEstimatedPlays }
}

/// One recording pass: what it found, and the library it read, so a sync can
/// use the same read instead of reading the library again.
nonisolated struct RecordPass: Sendable {
    /// `nil` when Caffy may not read the library, or saving failed.
    let summary: RecordSummary?
    /// `nil` when Caffy may not read the library.
    let library: [LibrarySongSnapshot]?
}

/// Builds Caffy's own listening history, one library read at a time.
///
/// Each pass reads every library song, compares it with what the last pass
/// saw (`LibrarySongState`), and saves the plays in between as `RecordedPlay`s
/// (see `PlayHistoryDiff`). The more often it runs, the tighter the windows
/// of estimated plays.
///
/// An actor with its own model context, so comparing a library of thousands
/// of songs doesn't hold up the main actor every time the app comes back.
actor ListeningRecorder: ModelActor {
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: any ModelExecutor

    private let reader: any MusicLibraryReader
    private let maxEstimatedWindow: TimeInterval
    /// The pass under way, if any, so a second call waits for it instead of
    /// comparing against half-saved state.
    private var inFlight: Task<RecordPass, Never>?

    init(modelContainer: ModelContainer, reader: any MusicLibraryReader, config: EraBuildConfig = .standard) {
        self.modelContainer = modelContainer
        modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.reader = reader
        maxEstimatedWindow = config.maxEstimatedPlayWindow
    }

    /// Reads the library and saves any new plays. Returns `nil` when Caffy
    /// may not read the library, or saving failed. If a pass is already
    /// running, waits for it and returns what it found.
    @discardableResult
    func record(now: Date) async -> RecordSummary? {
        await pass(now: now).summary
    }

    /// Like `record(now:)`, but also returns the library it read.
    func pass(now: Date) async -> RecordPass {
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { await self.recordOnce(now: now) }
        inFlight = task
        let pass = await task.value
        inFlight = nil
        return pass
    }

    private func recordOnce(now: Date) async -> RecordPass {
        guard let songs = await reader.songs() else { return RecordPass(summary: nil, library: nil) }
        return RecordPass(summary: savePlays(songs, now: now), library: songs)
    }

    /// Compares `songs` with the last pass and saves the new plays.
    private func savePlays(_ songs: [LibrarySongSnapshot], now: Date) -> RecordSummary? {
        // Nothing below suspends, so the comparison and save happen in one go.
        do {
            var latest = FetchDescriptor<ListeningCheck>(sortBy: [SortDescriptor(\.at, order: .reverse)])
            latest.fetchLimit = 1
            let previousCheck = try modelContext.fetch(latest).first?.at

            let stored = try modelContext.fetch(FetchDescriptor<LibrarySongState>())
            var states = Dictionary(stored.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

            var exact = 0
            var estimated = 0
            for song in songs {
                let state = states[song.key]
                let previous = state.map { PlayHistoryDiff.State(lastPlayedDate: $0.lastPlayedDate, playCount: $0.playCount) }
                let plays = PlayHistoryDiff.newPlays(
                    previous: previous, current: song, previousCheck: previousCheck,
                    now: now, maxEstimatedWindow: maxEstimatedWindow
                )
                for play in plays {
                    modelContext.insert(RecordedPlay(play, recordedAt: now))
                    if play.isEstimated { estimated += 1 } else { exact += 1 }
                }

                if let state {
                    // Set only when something changed, so unchanged songs
                    // aren't saved again on every pass.
                    if state.lastPlayedDate != song.lastPlayedDate || state.playCount != song.playCount {
                        state.lastPlayedDate = song.lastPlayedDate
                        state.playCount = song.playCount
                        state.updatedAt = now
                    }
                } else {
                    let new = LibrarySongState(key: song.key, lastPlayedDate: song.lastPlayedDate, playCount: song.playCount, firstSeenAt: now)
                    modelContext.insert(new)
                    states[song.key] = new
                }
            }

            modelContext.insert(ListeningCheck(at: now, songCount: songs.count, newExactPlays: exact, newEstimatedPlays: estimated))
            try modelContext.save()
            return RecordSummary(songCount: songs.count, newExactPlays: exact, newEstimatedPlays: estimated)
        } catch {
            modelContext.rollback()
            return nil
        }
    }
}

/// Plays from Caffy's recorded listening history.
///
/// Every song's current last-played time is recorded as an exact play, so
/// after a recording pass this covers everything `MediaPlayerListeningSource`
/// sees, plus every earlier play Caffy noticed.
nonisolated struct RecordedListeningSource: ListeningSource {
    let container: ModelContainer

    func plays(in interval: DateInterval) async throws -> [ListeningEvent] {
        try await Self.plays(in: interval, container: container)
    }

    /// `@concurrent`, with its own model context, so a long history is read
    /// off the main actor.
    @concurrent
    private static func plays(in interval: DateInterval, container: ModelContainer) async throws -> [ListeningEvent] {
        let context = ModelContext(container)
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<RecordedPlay>(
            predicate: #Predicate { $0.start <= end && $0.end >= start },
            sortBy: [SortDescriptor(\.start)]
        )
        return unique(try context.fetch(descriptor).map(\.event))
    }

    /// Drops plays of the same song over the same interval, keeping the
    /// first. The same catalog song seen again under a new library id records
    /// its last play a second time.
    static func unique(_ plays: [ListeningEvent]) -> [ListeningEvent] {
        struct Key: Hashable {
            let songID: String
            let interval: DateInterval
        }
        var seen = Set<Key>()
        return plays.filter { seen.insert(Key(songID: $0.song.id, interval: $0.interval)).inserted }
    }
}
