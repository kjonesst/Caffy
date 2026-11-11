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
/// 3. **Home eras:** the remaining moments, cut wherever there's a gap of at
///    least `longGap` with no photos at all, or home moved. Trips sit inside a
///    home era's dates without breaking it.
///
/// Soft cuts (long eras, changes in music) come in a later step.
nonisolated enum EraSegmenter {
    static func segment(
        _ moments: [PhotoMoment],
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

        let homeStretches = homeStretches(in: sorted, inTrip: inTrip, gapGroup: gapGroup, home: home)
        for (position, stretch) in homeStretches.enumerated() {
            let stretchMoments = stretch.indices.map { sorted[$0] }
            let first = stretchMoments[0]
            let last = stretchMoments.last!
            let isCurrent = position == homeStretches.count - 1 && now.timeIntervalSince(last.end) < config.longGap
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
}
