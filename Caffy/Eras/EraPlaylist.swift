import Foundation

/// Orders an era's songs into its playlist. A pure function.
///
/// 1. Songs played near the era's moments, by their matcher weight summed
///    over every moment.
/// 2. Songs added to the library during the era, by their score.
/// 3. Songs only played on the same day as a moment, by summed weight, and
///    only when `includeLoosePlaysInEraPlaylist` is on. Matching same-day plays
///    against a single last-played date is what used to fill the newest era
///    with almost every song in the library.
///
/// A song found more than one way appears once, with its strongest evidence.
/// Ties go to the song seen first, then to the lower id, so the order never
/// depends on dictionary order.
nonisolated enum EraPlaylist {
    static func build(
        momentSongs: [[EraSong]],
        added: [EraSong],
        includeLoose: Bool = EraBuildConfig.standard.includeLoosePlaysInEraPlaylist
    ) -> [EraSong] {
        let plays = momentSongs.flatMap { $0 }
        let near = summed(plays.filter { $0.evidence == .nearPlay })
        let loose = includeLoose ? summed(plays.filter { $0.evidence == .loosePlay }) : []
        let additions = added
            .enumerated()
            .sorted { ($1.element.score, $0.offset) < ($0.element.score, $1.offset) }
            .map(\.element)

        var seen = Set<String>()
        return (near + additions + loose).filter { seen.insert($0.song.id).inserted }
    }

    /// One entry per song, its scores added up, highest first.
    private static func summed(_ songs: [EraSong]) -> [EraSong] {
        var totals: [String: EraSong] = [:]
        var firstSeen: [String: Int] = [:]
        for (position, entry) in songs.enumerated() {
            if var total = totals[entry.song.id] {
                total.score += entry.score
                totals[entry.song.id] = total
            } else {
                totals[entry.song.id] = entry
                firstSeen[entry.song.id] = position
            }
        }
        return totals.values.sorted {
            ($1.score, firstSeen[$0.song.id]!, $0.song.id) < ($0.score, firstSeen[$1.song.id]!, $1.song.id)
        }
    }
}
