import Foundation

/// Orders an era's songs into its playlist. A pure function.
///
/// 1. Songs played near the era's moments, strongest evidence first:
///    a. near more of the era's moments first;
///    b. then songs with a near play Caffy saw happen before seeded-only
///       ones (see `NearEvidence.isSeededOnly`);
///    c. then by matcher weight summed over every moment;
///    d. then by title, then id.
/// 2. Songs added to the library during the era, by their score.
/// 3. Songs only played on the same day as a moment, by summed weight, and
///    only when `includeLoosePlaysInEraPlaylist` is on. Matching same-day plays
///    against a single last-played date is what used to fill the newest era
///    with almost every song in the library.
///
/// Nothing is capped. A song found more than one way appears once, with its
/// strongest evidence. Ties among additions and loose plays go to the song
/// seen first, then to the lower id, so the order never depends on
/// dictionary order.
nonisolated enum EraPlaylist {
    /// What an era's moments say about one song played near them.
    struct NearEvidence: Equatable, Sendable {
        /// How many of the era's moments the song was played near.
        var moments = 0
        /// Whether any of those near plays is known to be observed, or not
        /// known either way (`EraSong.hasObservedPlay` is `nil`).
        var hasObservedOrUnknown = false

        /// The song's only near evidence in the era is seeded: every moment
        /// it's near knows its plays there, and none of them was observed
        /// (`EraSong.hasObservedPlay == false` everywhere). Seeded plays are
        /// one per song (its last-played date from before recording), so in
        /// practice this is a single seeded play, perhaps near more than one
        /// moment. Unknown evidence never counts as seeded-only.
        var isSeededOnly: Bool { moments > 0 && !hasObservedOrUnknown }
    }

    /// - Parameters:
    ///   - momentSongs: each moment's songs, newest moment first.
    ///   - seededNeedCorroboration: `EraBuildConfig.seededPlaysNeedCorroboration`.
    ///   - corroborated: the era's songs that are corroborated (see
    ///     `EraPipeline.corroboratedSongIDs`). `nil` when not known, and then
    ///     nothing is left out.
    static func build(
        momentSongs: [[EraSong]],
        added: [EraSong],
        includeLoose: Bool = EraBuildConfig.standard.includeLoosePlaysInEraPlaylist,
        seededNeedCorroboration: Bool = EraBuildConfig.standard.seededPlaysNeedCorroboration,
        corroborated: Set<String>? = nil
    ) -> [EraSong] {
        let plays = momentSongs.flatMap { $0 }
        let evidence = nearEvidence(momentSongs: momentSongs)
        let near = summed(plays.filter { $0.evidence == .nearPlay }).map(\.entry).sorted { a, b in
            let ea = evidence[a.song.id]!, eb = evidence[b.song.id]!
            if ea.moments != eb.moments { return ea.moments > eb.moments }
            if ea.isSeededOnly != eb.isSeededOnly { return !ea.isSeededOnly }
            if a.score != b.score { return a.score > b.score }
            return (a.song.title, a.song.id) < (b.song.title, b.song.id)
        }
        // Highest score first, then the song seen first, then the lower id.
        let loose = includeLoose
            ? summed(plays.filter { $0.evidence == .loosePlay })
                .sorted { ($1.entry.score, $0.firstSeen, $0.entry.song.id) < ($0.entry.score, $1.firstSeen, $1.entry.song.id) }
                .map(\.entry)
            : []
        let additions = added
            .enumerated()
            .sorted { ($1.element.score, $0.offset) < ($0.element.score, $1.offset) }
            .map(\.element)

        var seen = Set<String>()
        if seededNeedCorroboration, let corroborated {
            seen = dropped(evidence, corroborated: corroborated)
        }
        return (near + additions + loose).filter { seen.insert($0.song.id).inserted }
    }

    /// The seeded-only songs that `seededPlaysNeedCorroboration` leaves out:
    /// those not in `corroborated`.
    static func dropped(_ evidence: [String: NearEvidence], corroborated: Set<String>) -> Set<String> {
        Set(evidence.filter { $0.value.isSeededOnly && !corroborated.contains($0.key) }.keys)
    }

    /// The evidence for every song played near one of `momentSongs`, by song id.
    static func nearEvidence(momentSongs: [[EraSong]]) -> [String: NearEvidence] {
        var result: [String: NearEvidence] = [:]
        for songs in momentSongs {
            var counted = Set<String>()
            for entry in songs where entry.evidence == .nearPlay {
                let id = entry.song.id
                if counted.insert(id).inserted {
                    result[id, default: NearEvidence()].moments += 1
                }
                if entry.hasObservedPlay != false {
                    result[id, default: NearEvidence()].hasObservedOrUnknown = true
                }
            }
        }
        return result
    }

    /// One entry per song, its scores added up, its plays observed if any
    /// were, in the order first seen.
    private static func summed(_ songs: [EraSong]) -> [(entry: EraSong, firstSeen: Int)] {
        var totals: [String: EraSong] = [:]
        var order: [String] = []
        for entry in songs {
            if var total = totals[entry.song.id] {
                total.score += entry.score
                total.hasObservedPlay = merged(total.hasObservedPlay, entry.hasObservedPlay)
                totals[entry.song.id] = total
            } else {
                totals[entry.song.id] = entry
                order.append(entry.song.id)
            }
        }
        return order.enumerated().map { (entry: totals[$1]!, firstSeen: $0) }
    }

    /// Observed if either was; unknown if either was and neither observed.
    private static func merged(_ a: Bool?, _ b: Bool?) -> Bool? {
        if a == true || b == true { return true }
        if a == nil || b == nil { return nil }
        return false
    }
}
