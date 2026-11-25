import Foundation
import Observation
import SwiftData

/// Publishes an era's playlist to Apple Music when its pill is tapped.
///
/// One tap does everything: works out which of the era's songs are in the
/// catalog (mostly from the artwork cache, see `CachedCatalogLookup`), then
/// creates the playlist, or brings an existing one up to date, and returns
/// the link to open. Each tap checks the playlist is still in the library;
/// one the user deleted in Apple Music is made again, because the tap says
/// they want it. Nothing is published without a tap.
///
/// Created once by `ContentView` and shared through the environment, so every
/// card sees the same publishing state.
@MainActor @Observable
final class EraPublisher {
    enum State: Equatable {
        case idle
        case publishing
        case failed(Failure)
    }

    enum Failure: Equatable {
        /// Apple Music isn't authorized.
        case musicAccess(MusicAccess)
        /// No subscription, or Sync Library is off, so playlists can't be added.
        case libraryAccess(MusicLibraryAccess)
        /// None of the era's songs are in the Apple Music catalog.
        case nothingPublishable
        /// Apple Music couldn't be reached, or the write failed.
        case couldNotReach
    }

    struct ListenResult: Equatable {
        let url: URL
        /// The playlist was just made, so the cover guide may be shown.
        let isFirstPublish: Bool
    }

    private(set) var states: [String: State] = [:]

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let publisher: any PlaylistPublishing
    @ObservationIgnored private let lookup: any CatalogSongLookup
    @ObservationIgnored private let now: () -> Date

    init(
        context: ModelContext,
        publisher: any PlaylistPublishing,
        lookup: any CatalogSongLookup,
        now: @escaping () -> Date = { .now }
    ) {
        self.context = context
        self.publisher = publisher
        self.lookup = lookup
        self.now = now
    }

    /// The app's publisher: MusicKit for the catalog and the library.
    static func live(context: ModelContext) -> EraPublisher {
        EraPublisher(context: context, publisher: LivePlaylistPublisher(), lookup: LiveCatalogSongLookup())
    }

    func state(for era: Era) -> State {
        era.eraID.flatMap { states[$0] } ?? .idle
    }

    /// Whether an era's card offers "Listen in Apple Music": it has songs (or
    /// a playlist already), and it's a real era rather than sample data.
    static func canListen(to era: Era) -> Bool {
        era.eraID != nil && (era.playlist?.appleMusicID != nil || !era.songs.isEmpty)
    }

    /// Publishes or updates the era's playlist and returns its link, or
    /// `nil` when that isn't possible (see `state(for:)` for why). Taps on an
    /// era that's already publishing are ignored.
    func listen(to era: Era, music: MusicAccess, library: MusicLibraryAccess) async -> ListenResult? {
        guard let eraID = era.eraID, states[eraID] != .publishing else { return nil }
        guard music == .authorized else { return fail(eraID, .musicAccess(music)) }
        switch library {
        case .needsSubscription, .syncLibraryOff: return fail(eraID, .libraryAccess(library))
        // `.unknown` means the check itself failed, for example offline: try
        // anyway, and report it if Apple Music can't be reached.
        case .canAddToLibrary, .unknown: break
        }

        states[eraID] = .publishing
        do {
            let ledger = PlaylistLedger(context: context)
            var link = try ledger.link(forEraID: eraID)
            // Deleted in Apple Music since? The tap asks for it, so make it
            // again rather than open a dead link. This reads the on-device
            // library, not the network.
            if let saved = link, try await publisher.playlist(id: saved.playlistID) == nil {
                link = nil
            }
            let eraSongs = era.songs
            let cached = CachedCatalogLookup(
                cache: try ArtworkFiller(context: context, resolver: ArtworkResolver(lookup: lookup)).cache(),
                live: lookup,
                songs: eraSongs.map(\.song)
            )
            let match = try await PlaylistSongMatcher.match(eraSongs, lookup: cached)
            guard !match.catalogIDs.isEmpty || link != nil else { return fail(eraID, .nothingPublishable) }

            let sync = PlaylistSync(publisher: publisher)
            let name = era.title
            let description = Self.description(for: era)
            var outcome = try await sync.publish(name: name, description: description, songIDs: match.catalogIDs, link: link, now: now())
            if case .missing = outcome {
                // Deleted between the check above and the write: make it again.
                outcome = try await sync.publish(name: name, description: description, songIDs: match.catalogIDs, link: nil, now: now())
            }
            guard let published = outcome.link else { return fail(eraID, .nothingPublishable) }
            try ledger.save(published, forEraID: eraID)
            guard let url = published.url else { return fail(eraID, .couldNotReach) }

            states[eraID] = .idle
            if case .created = outcome {
                return ListenResult(url: url, isFirstPublish: true)
            }
            return ListenResult(url: url, isFirstPublish: false)
        } catch {
            context.rollback()
            return fail(eraID, .couldNotReach)
        }
    }

    private func fail(_ eraID: String, _ failure: Failure) -> ListenResult? {
        states[eraID] = .failed(failure)
        return nil
    }

    /// The playlist's description in Apple Music: when, and where if the
    /// era's photos say.
    static func description(for era: Era) -> String {
        let format = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        let dates = "\(era.startDate.formatted(format)) – \(era.endDate?.formatted(format) ?? "now")"
        if let place = era.mainPlaceName {
            return "Made by Caffy from the music you lived with in \(place), \(dates)."
        }
        return "Made by Caffy from the music you lived with, \(dates)."
    }
}

extension Era {
    /// The photo the era is remembered by: the big print in its collage,
    /// which is its newest moment with a photo.
    var highlightMoment: Moment? {
        momentsNewestFirst.first { $0.photoAssetIdentifier != nil }
    }

    /// The place most of the era's moments were at, if they have places.
    var mainPlaceName: String? {
        let names = moments.filter(\.isLive).compactMap { $0.place?.name }
        let counts = Dictionary(names.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }
}
