import Foundation

/// Songs that stand for each era because they were added to the music library
/// during it, ranked by how much the user went on to play them.
///
/// Listening history only reaches back to when Caffy was installed, but a
/// song's `dateAdded` often reaches back years. "Songs you added around this
/// time" is a fair stand-in for what you were into then. It works per era,
/// not per moment.
///
/// A pure function of plain values: no SwiftData, no MediaPlayer. The coverage
/// report runs the same steps, so the two can't drift apart.
///
/// 1. **Eligible:** songs with a `dateAdded`, played at least
///    `minPlayCountForAddition` times.
/// 2. **Bulk days:** a local day with more than `bulkDayThreshold` additions
///    (counting every dated song, played or not) was an import, not taste.
///    Only its `bulkDayKeep` best eligible songs stay.
/// 3. **Albums:** tracks from one album added within `albumAddWindow` of the
///    first count as one album add. Only its `maxTracksPerAlbumAdd` best stay.
/// 4. **Assign:** each song goes to at most one era (see `era(for:in:config:)`).
/// 5. **Score:** `log(1 + plays) − 0.5 × log(1 + skips)`, times
///    `tripAdditionBoost` in trips. Ties go to the earlier addition, then
///    title, then id, so the result never depends on input order.
///
/// There's no cap: an era gets every addition the evidence supports, and
/// quality comes from the filters above, not from a count.
nonisolated enum LibraryAdditions {
    /// What the stage needs to know about an era.
    struct EraWindow: Hashable, Sendable {
        let id: String
        /// Only for reports. Pipeline eras have no title yet at this stage.
        var title: String = ""
        let start: Date
        /// For the era the user is living through now, `now`.
        let end: Date
        let isTrip: Bool
    }

    /// One song chosen for an era, with its score.
    struct Candidate: Hashable, Sendable {
        let snapshot: LibrarySongSnapshot
        let score: Double
    }

    /// The library after each filtering step (1–3), each in order of addition.
    struct Filtered: Equatable, Sendable {
        /// Every song with a `dateAdded`.
        let dated: [LibrarySongSnapshot]
        /// Additions per local day (the day's midnight), counting every dated song.
        let additionsPerDay: [Date: Int]
        /// Days with more than `bulkDayThreshold` additions, oldest first.
        let bulkDays: [Date]
        /// Step 1.
        let eligible: [LibrarySongSnapshot]
        /// Step 2.
        let afterBulkDays: [LibrarySongSnapshot]
        /// Step 3.
        let afterAlbums: [LibrarySongSnapshot]
    }

    /// The songs that stand for each era, best first, keyed by era id. Eras
    /// with none are left out.
    static func candidates(
        eras: [EraWindow],
        library: [LibrarySongSnapshot],
        calendar: Calendar,
        config: EraBuildConfig = .standard
    ) -> [String: [Candidate]] {
        let songs = filtered(library: library, calendar: calendar, config: config).afterAlbums
        return ranked(assign(songs, to: eras, config: config), eras: eras, config: config)
    }

    // MARK: - Steps

    /// Steps 1–3.
    static func filtered(library: [LibrarySongSnapshot], calendar: Calendar, config: EraBuildConfig = .standard) -> Filtered {
        let dated = library.filter { $0.dateAdded != nil }.sorted(by: isAddedBefore)

        var perDay: [Date: Int] = [:]
        var dayOf: [UInt64: Date] = [:]
        for song in dated {
            let day = calendar.startOfDay(for: song.dateAdded!)
            perDay[day, default: 0] += 1
            dayOf[song.persistentID] = day
        }
        let bulkDays = perDay.filter { $0.value > config.bulkDayThreshold }.keys.sorted()
        let isBulk = Set(bulkDays)

        let eligible = dated.filter { $0.playCount >= config.minPlayCountForAddition }

        // Step 2: bulk days keep only their best few.
        var onBulkDays: [Date: [LibrarySongSnapshot]] = [:]
        var afterBulkDays: [LibrarySongSnapshot] = []
        for song in eligible {
            if let day = dayOf[song.persistentID], isBulk.contains(day) {
                onBulkDays[day, default: []].append(song)
            } else {
                afterBulkDays.append(song)
            }
        }
        for songs in onBulkDays.values {
            afterBulkDays += best(songs, keeping: config.bulkDayKeep, config: config)
        }
        afterBulkDays.sort(by: isAddedBefore)

        // Step 3: an album added whole keeps only its best few tracks.
        var byAlbum: [UInt64: [LibrarySongSnapshot]] = [:]
        var afterAlbums: [LibrarySongSnapshot] = []
        for song in afterBulkDays {
            if let album = song.albumID {
                byAlbum[album, default: []].append(song)
            } else {
                afterAlbums.append(song)
            }
        }
        for tracks in byAlbum.values {
            // `tracks` is in order of addition, like `afterBulkDays`.
            var clusters: [[LibrarySongSnapshot]] = []
            for track in tracks {
                if let first = clusters.last?.first,
                   track.dateAdded!.timeIntervalSince(first.dateAdded!) <= config.albumAddWindow {
                    clusters[clusters.count - 1].append(track)
                } else {
                    clusters.append([track])
                }
            }
            for cluster in clusters {
                afterAlbums += best(cluster, keeping: config.maxTracksPerAlbumAdd, config: config)
            }
        }
        afterAlbums.sort(by: isAddedBefore)

        return Filtered(
            dated: dated,
            additionsPerDay: perDay,
            bulkDays: bulkDays,
            eligible: eligible,
            afterBulkDays: afterBulkDays,
            afterAlbums: afterAlbums
        )
    }

    /// Step 4: the songs that belong to each era, keyed by era id, in the
    /// order given. Songs without a `dateAdded`, or that no era reaches, are
    /// left out.
    static func assign(
        _ songs: [LibrarySongSnapshot],
        to eras: [EraWindow],
        config: EraBuildConfig = .standard
    ) -> [String: [LibrarySongSnapshot]] {
        var assigned: [String: [LibrarySongSnapshot]] = [:]
        for song in songs {
            guard let added = song.dateAdded, let era = era(for: added, in: eras, config: config) else { continue }
            assigned[era.id, default: []].append(song)
        }
        return assigned
    }

    /// The one era a song added at `date` belongs to.
    ///
    /// An era reaches from `additionLeadIn` before its start to its end.
    /// When more than one reaches the date, in order:
    /// 1. An era whose own dates contain the date beats one that only reaches
    ///    it through its lead-in.
    /// 2. The shortest era wins. Trips sit inside home eras' dates, so a trip
    ///    takes the songs added during it and the home era the rest.
    /// 3. The later start wins (the music was added ahead of it), then the
    ///    lower id.
    static func era(for date: Date, in eras: [EraWindow], config: EraBuildConfig = .standard) -> EraWindow? {
        eras
            .filter { $0.start.addingTimeInterval(-config.additionLeadIn) <= date && date <= $0.end }
            .min { isBetterClaim($0, than: $1, on: date) }
    }

    /// Whether `a` has the better claim to a song added at `date` (see
    /// `era(for:in:config:)`).
    private static func isBetterClaim(_ a: EraWindow, than b: EraWindow, on date: Date) -> Bool {
        let containsA = a.start <= date
        let containsB = b.start <= date
        if containsA != containsB { return containsA }
        let lengthA = a.end.timeIntervalSince(a.start)
        let lengthB = b.end.timeIntervalSince(b.start)
        if lengthA != lengthB { return lengthA < lengthB }
        if a.start != b.start { return a.start > b.start }
        return a.id < b.id
    }

    /// Step 5: scores each era's songs, best first.
    static func ranked(
        _ assigned: [String: [LibrarySongSnapshot]],
        eras: [EraWindow],
        config: EraBuildConfig = .standard
    ) -> [String: [Candidate]] {
        var isTrip: [String: Bool] = [:]
        for era in eras where isTrip[era.id] == nil { isTrip[era.id] = era.isTrip }
        var result: [String: [Candidate]] = [:]
        for (id, songs) in assigned where !songs.isEmpty {
            result[id] = ranked(songs, isTrip: isTrip[id] ?? false, config: config)
        }
        return result
    }

    // MARK: - Scoring

    /// How strongly a song added in an era stands for it: how much it was
    /// played, less how often it was skipped.
    static func score(_ song: LibrarySongSnapshot, isTrip: Bool = false, config: EraBuildConfig = .standard) -> Double {
        let plays = Double(max(0, song.playCount))
        let skips = Double(max(0, song.skipCount))
        let score = log(1 + plays) - 0.5 * log(1 + skips)
        return isTrip ? score * config.tripAdditionBoost : score
    }

    /// `songs` scored, best first, with deterministic tie-breaks.
    static func ranked(_ songs: [LibrarySongSnapshot], isTrip: Bool = false, config: EraBuildConfig = .standard) -> [Candidate] {
        songs
            .map { Candidate(snapshot: $0, score: score($0, isTrip: isTrip, config: config)) }
            .sorted(by: isRankedBefore)
    }

    /// The best `count` of `songs`, unboosted (steps 2 and 3 run before songs
    /// are assigned to eras).
    private static func best(_ songs: [LibrarySongSnapshot], keeping count: Int, config: EraBuildConfig) -> [LibrarySongSnapshot] {
        ranked(songs, config: config).prefix(max(0, count)).map(\.snapshot)
    }

    private static func isRankedBefore(_ a: Candidate, _ b: Candidate) -> Bool {
        if a.score != b.score { return a.score > b.score }
        return isAddedBefore(a.snapshot, b.snapshot)
    }

    /// Order of addition, then title, then id.
    private static func isAddedBefore(_ a: LibrarySongSnapshot, _ b: LibrarySongSnapshot) -> Bool {
        let addedA = a.dateAdded ?? .distantFuture
        let addedB = b.dateAdded ?? .distantFuture
        if addedA != addedB { return addedA < addedB }
        if a.title != b.title { return a.title < b.title }
        return a.persistentID < b.persistentID
    }
}
