import Foundation

/// An era as it was saved when it froze. Its words and colours never change.
nonisolated struct FrozenEra: Equatable, Sendable {
    let draft: EraDraft
    let content: EraContent
    let palette: EraPalette
}

/// One finished era: its moments, words, colours and library additions.
nonisolated struct BuiltEra: Equatable, Sendable {
    let draft: EraDraft
    let content: EraContent
    let palette: EraPalette
    /// Frozen eras are never re-cut, renamed or recoloured again.
    let isFrozen: Bool
    /// Songs added to the library during this era, best first. Whether a
    /// frozen era takes them is `EraStore`'s call.
    var addedSongs: [EraSong] = []
}

/// Everything the pipeline works out from a library.
nonisolated struct EraPipelineResult: Equatable, Sendable {
    /// Oldest first.
    let eras: [BuiltEra]
    /// The songs for each moment, keyed by moment id, strongest first.
    ///
    /// Moments from before any listening data are left out, so they're
    /// saved as never matched (`nil`) rather than matched with nothing (`[]`).
    let matches: [String: [EraSong]]

    /// `matches` without evidence or weights.
    var songs: [String: [Song]] {
        matches.mapValues { $0.map(\.song) }
    }

    /// An era's playlist as `Era.songs` will build it once saved.
    func playlist(for era: BuiltEra, config: EraBuildConfig = .standard) -> [EraSong] {
        // Newest moment first, like `Era.momentsNewestFirst`.
        let momentSongs = era.draft.momentIDs.reversed().map { matches[$0] ?? [] }
        return EraPlaylist.build(momentSongs: momentSongs, added: era.addedSongs, includeLoose: config.includeLoosePlaysInEraPlaylist)
    }
}

/// Runs every stage, from moments, plays and the music library to finished
/// eras: match → home → segment → library additions → palette → title.
///
/// Apart from the place names and photo colours it asks for (in a fixed
/// order), this is a pure function of its input.
nonisolated struct EraPipeline: Sendable {
    let namer: any PlaceNamer
    let sampler: any ColorSampler
    var config: EraBuildConfig = .standard

    /// `@concurrent` so the work happens off the main actor even when called
    /// from it (this project runs plain `async` functions on the caller's actor).
    @concurrent
    func run(
        moments: [PhotoMoment],
        plays: [ListeningEvent],
        library: [LibrarySongSnapshot] = [],
        frozen: [FrozenEra] = [],
        now: Date,
        calendar: Calendar
    ) async -> EraPipelineResult {
        let build = EraBuilder.build(
            moments: moments, plays: plays, frozen: frozen.map(\.draft),
            now: now, calendar: calendar, config: config
        )
        let matched = MusicMatcher.match(moments, with: plays, calendar: calendar, config: config)
        let matches = Self.matches(matched, plays: plays, calendar: calendar)

        let windows = build.drafts.map {
            LibraryAdditions.EraWindow(id: $0.id, start: $0.start, end: $0.end ?? now, isTrip: $0.kind == .trip)
        }
        let additions = LibraryAdditions.candidates(eras: windows, library: library, calendar: calendar, config: config)
            .mapValues { $0.map { EraSong(song: $0.snapshot.song, evidence: .libraryAdded, score: $0.score) } }

        let saved = Dictionary(frozen.map { ($0.draft.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Eras without saved words and colours. Ones that only froze just
        // now are included: they get their final words and colours here.
        let open = build.drafts.filter { saved[$0.id] == nil }

        let names = await EraFacts.placeNames(for: open, moments: moments, home: build.home, namer: namer)
        // Facts for every era, so the first open one can compare its music
        // with the frozen era before it.
        let facts = EraFacts.make(
            for: build.drafts, moments: moments, plays: plays,
            home: build.home, names: names, now: now, calendar: calendar
        )
        let factsByID = Dictionary(facts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let lastSavedPalette = open.first.flatMap { first in
            build.drafts
                .filter { saved[$0.id] != nil && ($0.start, $0.id) < (first.start, first.id) }
                .last
                .flatMap { saved[$0.id]?.palette }
        }
        let palettes = await PaletteBuilder.palettes(
            for: open, moments: moments, sampler: sampler, after: lastSavedPalette, config: config
        )
        let narrator = TemplateNarrator(calendar: calendar, now: now, config: config)

        let eras = build.drafts.map { draft in
            if let saved = saved[draft.id] {
                return BuiltEra(
                    draft: draft, content: saved.content, palette: saved.palette,
                    isFrozen: true, addedSongs: additions[draft.id] ?? []
                )
            }
            return BuiltEra(
                draft: draft,
                content: narrator.content(for: factsByID[draft.id]!),
                palette: palettes[draft.id]!,
                isFrozen: build.frozenIDs.contains(draft.id),
                addedSongs: additions[draft.id] ?? []
            )
        }
        return EraPipelineResult(eras: eras, matches: matches)
    }

    /// Each moment's songs with their evidence, keyed by moment id. Moments
    /// with no songs, on a day before the first play, are left out: no
    /// listening data reaches them yet.
    static func matches(_ matched: [MatchedMoment], plays: [ListeningEvent], calendar: Calendar) -> [String: [EraSong]] {
        let firstDay = plays.map(\.interval.start).min().map { calendar.startOfDay(for: $0) }
        var result: [String: [EraSong]] = [:]
        for moment in matched where result[moment.id] == nil {
            let reached = firstDay.map { calendar.startOfDay(for: moment.moment.start) >= $0 } ?? false
            guard !moment.songs.isEmpty || reached else { continue }
            result[moment.id] = moment.songs.map {
                EraSong(song: $0.song, evidence: $0.isLoose ? .loosePlay : .nearPlay, score: $0.score)
            }
        }
        return result
    }
}

nonisolated extension BuiltEra {
    /// This era as it should be saved once frozen.
    var frozen: FrozenEra {
        FrozenEra(draft: draft, content: content, palette: palette)
    }
}
