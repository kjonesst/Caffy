import Foundation

/// Splits moments into eras: overnight trips, and season-sized stretches of
/// life at home around them.
///
/// A pure function: the same moments, home timeline and `now` always give
/// the same eras.
///
/// 1. **Label** each moment home or away using the home timeline. A moment
///    without a location takes the label of the nearest located moment within
///    `unlocatedInheritWindow`, and otherwise counts as home.
/// 2. **Trips:** each run of away moments (split where two are more than
///    `maxTripGap` apart) that crosses `overnightCutoffHour` becomes a trip
///    era. Runs that don't are day trips and stay in the home era.
/// 3. **Home stretches:** the remaining moments, cut wherever there's a gap
///    of at least `longGap` with no photos at all, or home moved. Trips sit
///    inside a home era's dates without breaking it.
/// 4. **Soft cuts** keep home eras season-sized. Every change of day between
///    two home moments is a candidate, scored by the photo gap and by how
///    much the music changed (`musicWindow` either side, trips left out).
///    A candidate scoring at least `strongCutScore` is cut when both sides
///    stay at least `minEraLength` long. Then any era still longer than
///    `maxEraLength` is cut at its best candidate, preferring one that
///    leaves the earlier part near `targetEraLength`.
nonisolated enum EraSegmenter {
    static func segment(
        _ moments: [PhotoMoment],
        plays: [ListeningEvent] = [],
        home: HomeTimeline,
        now: Date,
        calendar: Calendar,
        config: EraBuildConfig = .standard
    ) -> [EraDraft] {
        let latestAllowed = now.addingTimeInterval(config.futureTolerance)
        let sorted = moments
            .filter { $0.start <= latestAllowed }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        guard !sorted.isEmpty else { return [] }

        let isAway = awayLabels(of: sorted, home: home, config: config)
        let tripRuns = awayRuns(in: sorted, isAway: isAway, config: config)
            .filter { crossesNight(sorted[$0.first!], sorted[$0.last!], calendar: calendar, config: config) }

        var inTrip = Array(repeating: false, count: sorted.count)
        for run in tripRuns {
            for index in run { inTrip[index] = true }
        }

        // Number the stretches between long gaps, counting every moment.
        var gapGroup = Array(repeating: 0, count: sorted.count)
        for index in sorted.indices.dropFirst() {
            let gap = sorted[index].start.timeIntervalSince(sorted[index - 1].end)
            gapGroup[index] = gapGroup[index - 1] + (gap >= config.longGap ? 1 : 0)
        }

        let latest = sorted.last!
        var drafts: [EraDraft] = []

        for run in tripRuns {
            let tripMoments = run.map { sorted[$0] }
            let isLatest = tripMoments.last == latest
            drafts.append(EraDraft(
                id: tripMoments[0].id,
                kind: .trip,
                momentIDs: tripMoments.map(\.id),
                start: tripMoments[0].start,
                end: isLatest && now.timeIntervalSince(latest.end) < config.currentTripWindow ? nil : tripMoments.last!.end,
                centre: destination(of: tripMoments, home: home),
                startReason: .trip
            ))
        }

        let tripTimes = tripRuns.map { DateInterval(start: sorted[$0.first!].start, end: sorted[$0.last!].end) }
        let music = MusicIndex(plays, excludingTrips: tripTimes, calendar: calendar)
        let homeEras = homeStretches(in: sorted, inTrip: inTrip, gapGroup: gapGroup, home: home)
            .flatMap { softCuts($0, moments: sorted, music: music, calendar: calendar, config: config) }

        for (position, stretch) in homeEras.enumerated() {
            let stretchMoments = stretch.indices.map { sorted[$0] }
            let first = stretchMoments[0]
            let last = stretchMoments.last!
            let isCurrent = position == homeEras.count - 1 && now.timeIntervalSince(last.end) < config.longGap
            drafts.append(EraDraft(
                id: first.id,
                kind: .home,
                momentIDs: stretchMoments.map(\.id),
                start: first.start,
                end: isCurrent ? nil : last.end,
                centre: home.home(on: first.start)?.centre
                    ?? MomentGrouper.representativeCoordinate(of: stretchMoments.compactMap(\.coordinate)),
                startReason: stretch.reason
            ))
        }

        return drafts.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    // MARK: - Labels

    /// Whether each moment (in time order) is away from home.
    private static func awayLabels(of moments: [PhotoMoment], home: HomeTimeline, config: EraBuildConfig) -> [Bool] {
        let located: [Bool?] = moments.map { moment in
            moment.coordinate.map { !home.isHome($0, on: moment.start) }
        }

        // The nearest located moment before and after each one.
        var previous = Array<Int?>(repeating: nil, count: moments.count)
        var next = Array<Int?>(repeating: nil, count: moments.count)
        var lastSeen: Int?
        for index in moments.indices {
            previous[index] = lastSeen
            if located[index] != nil { lastSeen = index }
        }
        lastSeen = nil
        for index in moments.indices.reversed() {
            next[index] = lastSeen
            if located[index] != nil { lastSeen = index }
        }

        return moments.indices.map { index in
            if let label = located[index] { return label }
            let moment = moments[index]
            let before = previous[index].map { (index: $0, gap: moment.start.timeIntervalSince(moments[$0].end)) }
            let after = next[index].map { (index: $0, gap: moments[$0].start.timeIntervalSince(moment.end)) }
            // The nearer neighbour wins; the earlier one wins a tie.
            let nearest = [before, after]
                .compactMap { $0 }
                .filter { $0.gap <= config.unlocatedInheritWindow }
                .min { $0.gap < $1.gap }
            return nearest.flatMap { located[$0.index] } ?? false
        }
    }

    /// Runs of consecutive away moments, as indexes into `moments`. A run
    /// splits where two away moments are more than `maxTripGap` apart.
    private static func awayRuns(in moments: [PhotoMoment], isAway: [Bool], config: EraBuildConfig) -> [[Int]] {
        var runs: [[Int]] = []
        var current: [Int] = []
        for index in moments.indices {
            guard isAway[index] else {
                if !current.isEmpty { runs.append(current) }
                current = []
                continue
            }
            if let last = current.last, moments[index].start.timeIntervalSince(moments[last].end) > config.maxTripGap {
                runs.append(current)
                current = []
            }
            current.append(index)
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// Whether the time from `first`'s start to `last`'s end includes the
    /// overnight cutoff hour (04:00 by default) in local time.
    private static func crossesNight(_ first: PhotoMoment, _ last: PhotoMoment, calendar: Calendar, config: EraBuildConfig) -> Bool {
        let cutoff = DateComponents(hour: config.overnightCutoffHour, minute: 0, second: 0)
        guard let night = calendar.nextDate(after: first.start, matching: cutoff, matchingPolicy: .nextTime) else {
            return false
        }
        return night <= last.end
    }

    /// The trip's main place: the cluster with the most moments (the first
    /// visited wins a tie), or the middle of its photos when none of them
    /// is in a cluster. `nil` when no photo has a location.
    private static func destination(of moments: [PhotoMoment], home: HomeTimeline) -> Coordinate? {
        let coordinates = moments.compactMap(\.coordinate)
        var counts: [Int: Int] = [:]
        var firstSeen: [Int: Int] = [:]
        for (position, coordinate) in coordinates.enumerated() {
            guard let cluster = home.cluster(containing: coordinate) else { continue }
            counts[cluster.id, default: 0] += 1
            if firstSeen[cluster.id] == nil { firstSeen[cluster.id] = position }
        }
        if let main = counts.min(by: { ($1.value, firstSeen[$0.key]!) < ($0.value, firstSeen[$1.key]!) }) {
            return home.clusters[main.key].centre
        }
        return MomentGrouper.representativeCoordinate(of: coordinates)
    }

    // MARK: - Home stretches

    private struct Stretch {
        var indices: [Int]
        let reason: EraBoundaryReason
    }

    /// The moments outside trips, split at long gaps and moves.
    private static func homeStretches(in moments: [PhotoMoment], inTrip: [Bool], gapGroup: [Int], home: HomeTimeline) -> [Stretch] {
        var stretches: [Stretch] = []
        var previous: (index: Int, homeID: Int?)?

        for index in moments.indices where !inTrip[index] {
            let homeID = home.home(on: moments[index].start)?.id
            if let previous {
                if homeID != previous.homeID {
                    stretches.append(Stretch(indices: [index], reason: .homeChange))
                } else if gapGroup[index] != gapGroup[previous.index] {
                    stretches.append(Stretch(indices: [index], reason: .longGap))
                } else {
                    stretches[stretches.count - 1].indices.append(index)
                }
            } else {
                stretches.append(Stretch(indices: [index], reason: .firstMoment))
            }
            previous = (index, homeID)
        }
        return stretches
    }

    // MARK: - Soft cuts

    /// Splits one home stretch into season-sized eras. See the type's
    /// description for the rules.
    private static func softCuts(
        _ stretch: Stretch,
        moments: [PhotoMoment],
        music: MusicIndex,
        calendar: Calendar,
        config: EraBuildConfig
    ) -> [Stretch] {
        let indices = stretch.indices
        guard indices.count > 1 else { return [stretch] }
        func start(_ position: Int) -> Date { moments[indices[position]].start }
        func end(_ position: Int) -> Date { moments[indices[position]].end }

        // A candidate cut at `position` starts a new era with that moment.
        struct Candidate {
            let position: Int
            let score: Double
        }
        // Music is compared over whole local days: the window's worth of days
        // up to and including the day of the last moment before the cut, and
        // from the day of the first moment after it.
        //
        // Calendar maths is slow, so the window edges step whole days of
        // seconds from a known midnight instead. A local day is 23 to 25
        // hours long, so an edge two hours before a midnight, or twelve hours
        // after one, always lands on the right side of it.
        let day: TimeInterval = 24 * 60 * 60
        let windowDays = max(1, Int((config.musicWindow / day).rounded()))
        let reachBack = Double(windowDays - 1) * day
        let localDays = indices.map { calendar.startOfDay(for: moments[$0].start) }

        var candidates: [Candidate] = []
        for position in 1..<indices.count where localDays[position] != localDays[position - 1] {
            let gap = start(position).timeIntervalSince(end(position - 1))
            let lastDayBefore = localDays[position - 1]
            let firstDayAfter = localDays[position]
            let before = music.profile(
                fromDay: lastDayBefore.addingTimeInterval(-reachBack - 2 * 60 * 60),
                toDay: lastDayBefore.addingTimeInterval(12 * 60 * 60)
            )
            let after = music.profile(
                fromDay: firstDayAfter.addingTimeInterval(-2 * 60 * 60),
                toDay: firstDayAfter.addingTimeInterval(reachBack + 12 * 60 * 60)
            )
            let enoughMusic = before.playCount >= config.musicMinPlays && after.playCount >= config.musicMinPlays
            let change = enoughMusic ? before.distance(to: after) : 0
            let score = config.gapWeight * min(1, gap / config.longGap) + config.musicChangeWeight * change
            candidates.append(Candidate(position: position, score: score))
        }

        var cuts: [Int: EraBoundaryReason] = [:]
        /// The era a cut at `position` would split, as the positions of its
        /// first moment and one past its last.
        func piece(around position: Int) -> (low: Int, high: Int) {
            let low = cuts.keys.filter { $0 < position }.max() ?? 0
            let high = cuts.keys.filter { $0 > position }.min() ?? indices.count
            return (low, high)
        }
        /// How long each side would be after cutting `low..<high` at `position`.
        func sides(cutting position: Int, low: Int, high: Int) -> (before: TimeInterval, after: TimeInterval) {
            (end(position - 1).timeIntervalSince(start(low)), end(high - 1).timeIntervalSince(start(position)))
        }

        // Clear changes in music, strongest first.
        let strongest = candidates
            .filter { $0.score >= config.strongCutScore }
            .sorted { ($1.score, $0.position) < ($0.score, $1.position) }
        for candidate in strongest {
            let (low, high) = piece(around: candidate.position)
            let (before, after) = sides(cutting: candidate.position, low: low, high: high)
            if before >= config.minEraLength && after >= config.minEraLength {
                cuts[candidate.position] = .musicChange
            }
        }

        // Then eras that are still too long, oldest first.
        var cutMade = true
        while cutMade {
            cutMade = false
            let starts = [0] + cuts.keys.sorted()
            for (number, low) in starts.enumerated() {
                let high = number + 1 < starts.count ? starts[number + 1] : indices.count
                guard end(high - 1).timeIntervalSince(start(low)) > config.maxEraLength else { continue }

                let best = candidates
                    .filter { $0.position > low && $0.position < high }
                    .compactMap { candidate -> (position: Int, value: Double)? in
                        let (before, after) = sides(cutting: candidate.position, low: low, high: high)
                        guard before >= config.minEraLength, after >= config.minEraLength else { return nil }
                        let closeness = 1 - min(1, abs(before - config.targetEraLength) / config.targetEraLength)
                        return (candidate.position, candidate.score + config.targetLengthWeight * closeness)
                    }
                    .min { ($1.value, $0.position) < ($0.value, $1.position) }
                if let best {
                    cuts[best.position] = .maxLength
                    cutMade = true
                    break
                }
            }
        }

        let bounds = [0] + cuts.keys.sorted() + [indices.count]
        return zip(bounds, bounds.dropFirst()).map { low, high in
            Stretch(indices: Array(indices[low..<high]), reason: low == 0 ? stretch.reason : cuts[low]!)
        }
    }
}

/// Plays added up per local day, leaving out plays during trips, for quickly
/// summing up the listening either side of a candidate cut.
private nonisolated struct MusicIndex {
    /// One local day's plays (by start time) per artist and genre.
    private struct Day {
        let start: Date
        var plays = 0
        var artists: [String: Int] = [:]
        var genres: [String: Int] = [:]
    }

    /// Days with at least one play, oldest first.
    private let days: [Day]

    init(_ events: [ListeningEvent], excludingTrips trips: [DateInterval], calendar: Calendar) {
        // Trips never overlap, so both lists can be walked once, side by side.
        let sortedTrips = trips.sorted { $0.start < $1.start }
        var kept: [ListeningEvent] = []
        var trip = 0
        for play in events.sorted(by: { ($0.interval.start, $0.song.id) < ($1.interval.start, $1.song.id) }) {
            let time = play.interval.start
            while trip < sortedTrips.count, sortedTrips[trip].end < time {
                trip += 1
            }
            if trip < sortedTrips.count, sortedTrips[trip].start <= time {
                continue
            }
            kept.append(play)
        }

        // The plays are in time order, so a new day only needs working out
        // when a play starts past the end of the current one.
        var days: [Day] = []
        var dayEnd: Date?
        for play in kept {
            if dayEnd.map({ play.interval.start >= $0 }) ?? true {
                let start = calendar.startOfDay(for: play.interval.start)
                days.append(Day(start: start))
                dayEnd = calendar.date(byAdding: .day, value: 1, to: start)!
            }
            days[days.count - 1].plays += 1
            days[days.count - 1].artists[play.song.artist, default: 0] += 1
            if let genre = play.song.genre {
                days[days.count - 1].genres[genre, default: 0] += 1
            }
        }
        self.days = days
    }

    /// The listening on the local days whose midnight is at or after `first`
    /// and before `end`.
    func profile(fromDay first: Date, toDay end: Date) -> ListeningProfile {
        var plays = 0
        var artists: [String: Int] = [:]
        var genres: [String: Int] = [:]
        var index = firstIndex(startingAtOrAfter: first)
        while index < days.count, days[index].start < end {
            plays += days[index].plays
            artists.merge(days[index].artists, uniquingKeysWith: +)
            genres.merge(days[index].genres, uniquingKeysWith: +)
            index += 1
        }
        return ListeningProfile(playCount: plays, artistPlays: artists, genrePlays: genres)
    }

    private func firstIndex(startingAtOrAfter date: Date) -> Int {
        var low = 0
        var high = days.count
        while low < high {
            let middle = (low + high) / 2
            if days[middle].start < date {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}
