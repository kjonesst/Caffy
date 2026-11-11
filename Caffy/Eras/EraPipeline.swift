import Foundation

/// An era as it was saved when it froze. Its words and colours never change.
nonisolated struct FrozenEra: Equatable, Sendable {
    let draft: EraDraft
    let content: EraContent
    let palette: EraPalette
}

/// One finished era: its moments, words and colours.
nonisolated struct BuiltEra: Equatable, Sendable {
    let draft: EraDraft
    let content: EraContent
    let palette: EraPalette
    /// Frozen eras are never re-cut, renamed or recoloured again.
    let isFrozen: Bool
}

/// Everything the pipeline works out from a library.
nonisolated struct EraPipelineResult: Equatable, Sendable {
    /// Oldest first.
    let eras: [BuiltEra]
    /// The songs for each moment, keyed by moment id, strongest first.
    let songs: [String: [Song]]
}

/// Runs every stage, from moments and plays to finished eras:
/// match → home → segment → palette → title.
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
        frozen: [FrozenEra] = [],
        now: Date,
        calendar: Calendar
    ) async -> EraPipelineResult {
        let build = EraBuilder.build(
            moments: moments, plays: plays, frozen: frozen.map(\.draft),
            now: now, calendar: calendar, config: config
        )
        let matched = MusicMatcher.match(moments, with: plays, calendar: calendar, config: config)
        let songs = Dictionary(matched.map { ($0.id, $0.songs.map(\.song)) }, uniquingKeysWith: { first, _ in first })

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
                return BuiltEra(draft: draft, content: saved.content, palette: saved.palette, isFrozen: true)
            }
            return BuiltEra(
                draft: draft,
                content: narrator.content(for: factsByID[draft.id]!),
                palette: palettes[draft.id]!,
                isFrozen: build.frozenIDs.contains(draft.id)
            )
        }
        return EraPipelineResult(eras: eras, songs: songs)
    }
}

extension BuiltEra {
    /// This era as it should be saved once frozen.
    var frozen: FrozenEra {
        FrozenEra(draft: draft, content: content, palette: palette)
    }
}
