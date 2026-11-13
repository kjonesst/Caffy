import Foundation

/// One song attached to a moment, and how strongly it belongs there.
nonisolated struct SongMatch: Hashable, Sendable {
    let song: Song
    /// For a normal match, the sum of the weights of this song's plays near
    /// the moment (a play during the moment counts 1). For a loose match,
    /// the number of plays that day.
    let score: Double
    /// How many of this song's plays counted towards `score`.
    let playCount: Int
    /// `true` when nothing played near the moment, so this song comes from
    /// elsewhere on the same day.
    let isLoose: Bool
}

/// A photo moment with the songs that were playing around it.
nonisolated struct MatchedMoment: Hashable, Sendable, Identifiable {
    let moment: PhotoMoment
    /// Strongest first. Empty when nothing was playing that day.
    let songs: [SongMatch]

    var id: String { moment.id }
}

/// Attaches songs to moments by time.
///
/// A pure function: the same moments and plays always give the same songs.
///
/// Each moment gets a window from `matchWindowBefore` its first photo to
/// `matchWindowAfter` its last. Time inside the window weighs 1; time outside
/// it halves every `matchDecayHalfLife` and stops counting after
/// `matchDecayCutoff`. A play's weight is the average of that over the play's
/// interval, so an exact play inside the window counts 1, and an estimated
/// play known only to fall in a two-hour window counts by how much of that
/// window sits near the moment.
///
/// Plays carry no location, so place plays no part here. An era's music
/// overall comes from every play in its dates, not just the matched ones.
/// Plays that aren't `isMatchable` are skipped here, but still count there.
nonisolated enum MusicMatcher {
    /// Matches songs to every moment. Returns moments oldest first.
    static func match(
        _ moments: [PhotoMoment],
        with plays: [ListeningEvent],
        calendar: Calendar,
        config: EraBuildConfig = .standard
    ) -> [MatchedMoment] {
        let sortedMoments = moments.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        let index = PlayIndex(plays.filter(\.isMatchable))

        return sortedMoments.map { moment in
            let window = DateInterval(
                start: moment.start.addingTimeInterval(-config.matchWindowBefore),
                end: moment.end.addingTimeInterval(config.matchWindowAfter)
            )
            let reach = DateInterval(
                start: window.start.addingTimeInterval(-config.matchDecayCutoff),
                end: window.end.addingTimeInterval(config.matchDecayCutoff)
            )
            let nearby = index.plays(overlapping: reach).map { play in
                (play, weight(of: play.interval, around: window, config: config))
            }
            var songs = rank(nearby, isLoose: false)

            if songs.isEmpty && config.dayFallbackMatching {
                let days = DateInterval(
                    start: calendar.startOfDay(for: moment.start),
                    end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: moment.end))!
                )
                let sameDay = index.plays(overlapping: days).map { ($0, 1.0) }
                songs = rank(sameDay, isLoose: true)
            }
            return MatchedMoment(moment: moment, songs: songs)
        }
    }

    // MARK: - Weighting

    /// How much a play over `play` counts for a moment with this `window`,
    /// from 0 to 1. See the type's description.
    static func weight(of play: DateInterval, around window: DateInterval, config: EraBuildConfig) -> Double {
        let halfLife = config.matchDecayHalfLife
        let cutoff = config.matchDecayCutoff

        // A play with no length: the weight at that one instant.
        guard play.duration > 0 else {
            let distance = max(window.start.timeIntervalSince(play.start), play.start.timeIntervalSince(window.end), 0)
            return decay(at: distance, halfLife: halfLife, cutoff: cutoff)
        }

        var total: TimeInterval = 0
        // The part of the play before the window, by distance from its start.
        if play.start < window.start {
            let near = window.start.timeIntervalSince(min(play.end, window.start))
            let far = window.start.timeIntervalSince(play.start)
            total += decayIntegral(from: near, to: far, halfLife: halfLife, cutoff: cutoff)
        }
        // The part inside the window counts in full.
        let insideStart = max(play.start, window.start)
        let insideEnd = min(play.end, window.end)
        if insideEnd > insideStart {
            total += insideEnd.timeIntervalSince(insideStart)
        }
        // The part after the window, by distance from its end.
        if play.end > window.end {
            let near = max(play.start, window.end).timeIntervalSince(window.end)
            let far = play.end.timeIntervalSince(window.end)
            total += decayIntegral(from: near, to: far, halfLife: halfLife, cutoff: cutoff)
        }
        return total / play.duration
    }

    /// The weight of an instant `distance` seconds outside the window.
    private static func decay(at distance: TimeInterval, halfLife: TimeInterval, cutoff: TimeInterval) -> Double {
        if distance == 0 { return 1 }
        guard halfLife > 0, distance <= cutoff else { return 0 }
        return pow(2, -distance / halfLife)
    }

    /// The decayed weight summed over every instant from `near` to `far`
    /// seconds outside the window. Uses ∫ 2^(−x/h) dx = −(h / ln 2) · 2^(−x/h).
    private static func decayIntegral(from near: TimeInterval, to far: TimeInterval, halfLife: TimeInterval, cutoff: TimeInterval) -> TimeInterval {
        let a = min(near, cutoff)
        let b = min(far, cutoff)
        guard halfLife > 0, b > a else { return 0 }
        return halfLife / log(2.0) * (pow(2, -a / halfLife) - pow(2, -b / halfLife))
    }

    // MARK: - Ranking

    /// Adds up each song's weighted plays and returns every song, strongest
    /// first: highest score, then most plays, then song id so ties never
    /// depend on input order. Nothing is cut here, so every real play reaches
    /// the era's playlist; a moment shows only its top `maxSongsPerMoment`.
    private static func rank(_ weighted: [(ListeningEvent, Double)], isLoose: Bool) -> [SongMatch] {
        var order: [String] = []
        var songs: [String: Song] = [:]
        var scores: [String: Double] = [:]
        var counts: [String: Int] = [:]

        // `weighted` is in time order, so sums and the kept `Song` are the
        // same on every run.
        for (play, weight) in weighted where weight > 0 {
            let id = play.song.id
            if songs[id] == nil {
                songs[id] = play.song
                order.append(id)
            }
            scores[id, default: 0] += weight
            counts[id, default: 0] += 1
        }

        return order
            .map { SongMatch(song: songs[$0]!, score: scores[$0]!, playCount: counts[$0]!, isLoose: isLoose) }
            .sorted { ($1.score, $1.playCount, $0.song.id) < ($0.score, $0.playCount, $1.song.id) }
    }
}

/// Plays sorted by start time, for quickly finding the ones near a moment.
private nonisolated struct PlayIndex {
    private let plays: [ListeningEvent]
    /// The longest play, so a search can start early enough to catch long
    /// estimated plays that began well before the range.
    private let longest: TimeInterval

    init(_ events: [ListeningEvent]) {
        let sorted = events.sorted {
            ($0.interval.start, $0.interval.end, $0.song.id) < ($1.interval.start, $1.interval.end, $1.song.id)
        }
        // The same song over the same interval twice is one play reported
        // twice (for example by overlapping snapshots), so keep one.
        var unique: [ListeningEvent] = []
        for event in sorted {
            if let last = unique.last, last.song.id == event.song.id, last.interval == event.interval {
                continue
            }
            unique.append(event)
        }
        plays = unique
        longest = unique.map(\.interval.duration).max() ?? 0
    }

    /// Every play that overlaps `range`, in time order. Ranges are half-open,
    /// so a play that ends exactly when `range` starts doesn't count.
    func plays(overlapping range: DateInterval) -> [ListeningEvent] {
        let earliestStart = range.start.addingTimeInterval(-longest)
        var index = firstIndex(startingAtOrAfter: earliestStart)
        var result: [ListeningEvent] = []
        while index < plays.count, plays[index].interval.start < range.end {
            let play = plays[index].interval
            // A play with no length counts if its one instant is in range.
            let overlaps = play.duration == 0 ? play.start >= range.start : play.end > range.start
            if overlaps {
                result.append(plays[index])
            }
            index += 1
        }
        return result
    }

    /// Binary search for the first play starting at or after `date`.
    private func firstIndex(startingAtOrAfter date: Date) -> Int {
        var low = 0
        var high = plays.count
        while low < high {
            let middle = (low + high) / 2
            if plays[middle].interval.start < date {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}
