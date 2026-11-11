import Foundation
import Photos
import SwiftData

/// How a sync went.
enum LibrarySyncOutcome: Equatable {
    /// The database now matches the library.
    case synced(eras: Int, moments: Int)
    /// Caffy may not read the photo library, so nothing changed.
    case noAccess
    /// Another sync was running; it will run again once it finishes.
    case queued
    /// Saving failed; the database is as it was before.
    case failed(String)
}

/// Keeps the saved eras in step with the user's photo library.
///
/// One sync: read every photo → group into moments → fetch listening →
/// run the era pipeline (with saved frozen eras) → save. The pipeline and
/// the photo reading run off the main actor; reading and saving the database
/// happens here, on it.
///
/// A sync asked for while one is running isn't lost: the running one goes
/// round again when it finishes, so the database always ends up matching the
/// latest library.
@MainActor
final class LibrarySync {
    private let context: ModelContext
    private let reader: any PhotoLibraryReader
    private let listening: any ListeningSource
    private let pipeline: EraPipeline
    private let calendar: Calendar
    private let now: () -> Date

    private var isRunning = false
    private var runAgain = false
    private var changeRelay: PhotoLibraryChangeRelay?
    private var pendingChange: Task<Void, Never>?

    init(
        context: ModelContext,
        reader: any PhotoLibraryReader,
        listening: any ListeningSource,
        pipeline: EraPipeline,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        self.context = context
        self.reader = reader
        self.listening = listening
        self.pipeline = pipeline
        self.calendar = calendar
        self.now = now
    }

    /// The app's sync: the real photo library, Apple's place names, photo
    /// colours from thumbnails, and no listening until MusicKit is connected.
    static func live(context: ModelContext) -> LibrarySync {
        LibrarySync(
            context: context,
            reader: PhotoKitLibraryReader(),
            listening: MockListeningSource(events: []),
            pipeline: EraPipeline(namer: MapKitPlaceLookup.cachedNamer(), sampler: PhotoKitColorSampler())
        )
    }

    /// Syncs now, or, if a sync is running, makes it go round once more.
    @discardableResult
    func sync() async -> LibrarySyncOutcome {
        guard !isRunning else {
            runAgain = true
            return .queued
        }
        isRunning = true
        defer { isRunning = false }

        var outcome: LibrarySyncOutcome
        repeat {
            runAgain = false
            outcome = await syncOnce()
        } while runAgain
        return outcome
    }

    private func syncOnce() async -> LibrarySyncOutcome {
        guard let photos = await reader.photos() else { return .noAccess }
        let moments = await Self.group(photos)
        let now = now()

        var plays: [ListeningEvent] = []
        if let first = moments.first {
            // A day before the first photo, so its moment can match songs.
            let span = DateInterval(start: first.start.addingTimeInterval(-24 * 60 * 60), end: max(now, first.start))
            plays = (try? await listening.plays(in: span)) ?? []
        }

        do {
            let store = EraStore(context: context)
            let frozen = try store.frozenEras()
            let result = await pipeline.run(moments: moments, plays: plays, frozen: frozen, now: now, calendar: calendar)
            try store.save(result, moments: moments, now: now)
            return .synced(eras: result.eras.count, moments: moments.count)
        } catch {
            context.rollback()
            return .failed(error.localizedDescription)
        }
    }

    /// Grouping a large library takes a moment, so it happens off the main actor.
    @concurrent
    private static func group(_ photos: [PhotoItem]) async -> [PhotoMoment] {
        MomentGrouper.group(photos)
    }

    // MARK: - Library changes

    /// Syncs again whenever the photo library changes while Caffy is open,
    /// two seconds after the last change (so an import of many photos means
    /// one sync, not hundreds). Only call this once photo access is granted.
    func observeLibraryChanges() {
        guard changeRelay == nil else { return }
        let relay = PhotoLibraryChangeRelay { [weak self] in
            // Unwrapped once here, so the task below captures a constant.
            guard let self else { return }
            Task { @MainActor in self.libraryChanged() }
        }
        PHPhotoLibrary.shared().register(relay)
        changeRelay = relay
    }

    private func libraryChanged() {
        pendingChange?.cancel()
        pendingChange = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await sync()
        }
    }
}

/// Passes PhotoKit's change notifications (which arrive on a background
/// queue) to a closure.
private nonisolated final class PhotoLibraryChangeRelay: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }
}
