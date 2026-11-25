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
    /// The era's near songs that are corroborated, for
    /// `seededPlaysNeedCorroboration` (see `EraPipeline.corroboratedSongIDs`).
    var corroboratedSongIDs: Set<String> = []
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
        return EraPlaylist.build(
            momentSongs: momentSongs,
            added: era.addedSongs,
            includeLoose: config.includeLoosePlaysInEraPlaylist,
            seededNeedCorroboration: config.seededPlaysNeedCorroboration,
            corroborated: era.corroboratedSongIDs
        )
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
        let corroborated = Self.corroboratedSongIDs(
            for: build.drafts, matches: matches, plays: plays, library: library, now: now, config: config
        )

        let eras = build.drafts.map { draft in
            if let saved = saved[draft.id] {
                return BuiltEra(
                    draft: draft, content: saved.content, palette: saved.palette,
                    isFrozen: true, addedSongs: additions[draft.id] ?? [],
                    corroboratedSongIDs: corroborated[draft.id] ?? []
                )
            }
            return BuiltEra(
                draft: draft,
                content: narrator.content(for: factsByID[draft.id]!),
                palette: palettes[draft.id]!,
                isFrozen: build.frozenIDs.contains(draft.id),
                addedSongs: additions[draft.id] ?? [],
                corroboratedSongIDs: corroborated[draft.id] ?? []
            )
        }
        return EraPipelineResult(eras: eras, matches: matches)
    }

    /// For each era, by id: its near songs that something besides a seeded
    /// play backs up. A song is corroborated when its `dateAdded` falls in
    /// the era's addition window (`start − additionLeadIn` to `end`, so it
    /// was new then), or when it has an observed play within the era's dates.
    /// Only near songs are checked, which keeps what's saved small.
    static func corroboratedSongIDs(
        for drafts: [EraDraft],
        matches: [String: [EraSong]],
        plays: [ListeningEvent],
        library: [LibrarySongSnapshot],
        now: Date,
        config: EraBuildConfig
    ) -> [String: Set<String>] {
        var added: [String: [Date]] = [:]
        for snapshot in library {
            if let date = snapshot.dateAdded { added[snapshot.song.id, default: []].append(date) }
        }
        var observed: [String: [DateInterval]] = [:]
        for play in plays where !play.isSeeded {
            observed[play.song.id, default: []].append(play.interval)
        }

        var result: [String: Set<String>] = [:]
        for draft in drafts {
            let end = draft.end ?? now
            let dates = DateInterval(start: draft.start, end: max(draft.start, end))
            let additionStart = draft.start.addingTimeInterval(-config.additionLeadIn)
            var near = Set<String>()
            for id in draft.momentIDs {
                for song in matches[id] ?? [] where song.evidence == .nearPlay {
                    near.insert(song.song.id)
                }
            }
            result[draft.id] = near.filter { id in
                (added[id] ?? []).contains { $0 >= additionStart && $0 <= end }
                    || (observed[id] ?? []).contains { $0.intersects(dates) }
            }
        }
        return result
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
                EraSong(
                    song: $0.song, evidence: $0.isLoose ? .loosePlay : .nearPlay, score: $0.score,
                    hasObservedPlay: $0.observedPlayCount > 0
                )
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
