import Foundation

/// A place the user has been, about one city across.
nonisolated struct PlaceCluster: Hashable, Sendable, Identifiable {
    /// The cluster's position in `HomeTimeline.clusters`: 0 is the first
    /// place the user was seen in.
    let id: Int
    /// The first day's location in this place. It never moves, so adding
    /// photos can't shift which cluster an old photo belongs to.
    let centre: Coordinate
}

/// One local calendar day with at least one located photo.
nonisolated struct LocatedDay: Hashable, Sendable {
    /// Midnight at the start of the day.
    let day: Date
    /// Days since the first located day.
    let index: Int
    /// Where the day ended: the location of its last located moment.
    let anchor: Coordinate
    let clusterID: Int
}

/// A stretch of time the user lived in one place.
nonisolated struct Residence: Hashable, Sendable {
    let clusterID: Int
    /// Midnight on the first and last located days in the place.
    let firstDay: Date
    let lastDay: Date
    /// The share of the days in the stretch spent in this place, from 0 to 1.
    let share: Double
}

/// Where home is at any point in the user's history.
nonisolated struct HomeTimeline: Sendable, Equatable {
    let calendar: Calendar
    /// Coordinates this close to a cluster's centre belong to it.
    let radius: Double
    /// Every place seen, in order of first visit.
    let clusters: [PlaceCluster]
    /// Every day with a located photo, oldest first.
    let days: [LocatedDay]
    /// Oldest first.
    let residences: [Residence]
    /// Home when there's no residence at all: the place with the most days.
    let fallbackClusterID: Int?

    /// Home on the day `date` falls on, or `nil` when no photo has a location.
    ///
    /// That's the residence covering the day (the one with the highest share
    /// if several do). Between residences, home is the last one until the
    /// next begins. Before the first residence, it's the first one.
    func home(on date: Date) -> PlaceCluster? {
        guard let first = residences.first else {
            return fallbackClusterID.map { clusters[$0] }
        }
        let day = calendar.startOfDay(for: date)

        let covering = residences.filter { $0.firstDay <= day && day <= $0.lastDay }
        if let best = covering.min(by: Self.isStronger) {
            return clusters[best.clusterID]
        }
        // The residence that ended most recently before this day.
        let ended = residences.filter { $0.lastDay < day }
        if let latest = ended.min(by: { ($1.lastDay, $0.firstDay, $0.clusterID) < ($0.lastDay, $1.firstDay, $1.clusterID) }) {
            return clusters[latest.clusterID]
        }
        return clusters[first.clusterID]
    }

    /// Whether `coordinate` is at home on the day `date` falls on. Always
    /// `true` when home is unknown, because then nothing can be called away.
    func isHome(_ coordinate: Coordinate, on date: Date) -> Bool {
        guard let home = home(on: date) else { return true }
        return cluster(containing: coordinate)?.id == home.id
    }

    /// The nearest cluster within `radius` of `coordinate`. `nil` for a place
    /// the user only passed through and never ended a day in.
    func cluster(containing coordinate: Coordinate) -> PlaceCluster? {
        HomeInference.nearest(to: coordinate, in: clusters, radius: radius)
    }

    /// Higher share first, then the earlier start, then the lower cluster id.
    private static func isStronger(_ a: Residence, than b: Residence) -> Bool {
        (b.share, a.firstDay, a.clusterID) < (a.share, b.firstDay, b.clusterID)
    }
}

/// Works out where home is from photo locations alone, without asking.
///
/// A pure function: the same moments always give the same timeline.
///
/// 1. Each local day with a located photo is anchored where it ended (its
///    last located moment), because where someone sleeps decides home.
/// 2. Day anchors are grouped into city-sized clusters in date order. A day
///    joins the nearest cluster within `placeClusterRadius`, or starts one.
/// 3. Each calendar day belongs to the nearest located day, so a sparse
///    photographer's quiet weeks at home still count as home, and a trip
///    photographed heavily doesn't outweigh them.
/// 4. A place's days are joined into stretches across absences shorter than
///    `homeAdoptionDays`. A stretch at least that long, where the place holds
///    at least `homeMinShare` of the days, is a residence.
nonisolated enum HomeInference {
    static func infer(_ moments: [PhotoMoment], calendar: Calendar, config: EraBuildConfig = .standard) -> HomeTimeline {
        let anchors = dayAnchors(of: moments, calendar: calendar)
        let radius = config.placeClusterRadius

        // Clusters, and each day's cluster.
        var clusters: [PlaceCluster] = []
        var days: [LocatedDay] = []
        let firstDay = anchors.first?.day
        for (day, anchor) in anchors {
            let clusterID: Int
            if let existing = nearest(to: anchor, in: clusters, radius: radius) {
                clusterID = existing.id
            } else {
                clusterID = clusters.count
                clusters.append(PlaceCluster(id: clusterID, centre: anchor))
            }
            let index = calendar.dateComponents([.day], from: firstDay!, to: day).day!
            days.append(LocatedDay(day: day, index: index, anchor: anchor, clusterID: clusterID))
        }

        let territories = territories(of: days)
        let residences = clusters
            .flatMap { residences(of: $0.id, days: days, territories: territories, config: config) }
            .sorted { ($0.firstDay, $0.clusterID) < ($1.firstDay, $1.clusterID) }

        return HomeTimeline(
            calendar: calendar,
            radius: radius,
            clusters: clusters,
            days: days,
            residences: residences,
            fallbackClusterID: mostTimeSpent(days: days, territories: territories)
        )
    }

    /// For each local day with a located moment, where the day ended. Oldest first.
    private static func dayAnchors(of moments: [PhotoMoment], calendar: Calendar) -> [(day: Date, anchor: Coordinate)] {
        let located = moments
            .filter { $0.coordinate != nil }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }

        var anchors: [(day: Date, anchor: Coordinate)] = []
        for moment in located {
            let day = calendar.startOfDay(for: moment.start)
            let coordinate = moment.coordinate!
            if anchors.last?.day == day {
                anchors[anchors.count - 1].anchor = coordinate
            } else {
                anchors.append((day, coordinate))
            }
        }
        return anchors
    }

    /// The nearest cluster within `radius`, the lower id winning a tie.
    static func nearest(to coordinate: Coordinate, in clusters: [PlaceCluster], radius: Double) -> PlaceCluster? {
        // A degree of latitude is about 111 km anywhere on Earth, so clusters
        // further north or south than that can be skipped without the more
        // expensive distance calculation.
        let latitudeReach = radius / 111_000 + 0.01
        var best: (cluster: PlaceCluster, distance: Double)?
        for cluster in clusters where abs(cluster.centre.latitude - coordinate.latitude) <= latitudeReach {
            let distance = coordinate.distance(to: cluster.centre)
            if distance <= radius, distance < best?.distance ?? .infinity {
                best = (cluster, distance)
            }
        }
        return best?.cluster
    }

    /// The calendar days each located day stands for, as day indexes: itself
    /// and the nearer half of the days without photos on each side. The
    /// territories cover the whole history without overlapping.
    private static func territories(of days: [LocatedDay]) -> [ClosedRange<Int>] {
        days.indices.map { position in
            let index = days[position].index
            // Integer division rounds down, so a day exactly halfway goes to
            // the earlier located day.
            let low = position == 0 ? index : (days[position - 1].index + index) / 2 + 1
            let high = position == days.count - 1 ? index : (index + days[position + 1].index) / 2
            return low...high
        }
    }

    /// The residences in one cluster, oldest first.
    private static func residences(
        of clusterID: Int,
        days: [LocatedDay],
        territories: [ClosedRange<Int>],
        config: EraBuildConfig
    ) -> [Residence] {
        let positions = days.indices.filter { days[$0].clusterID == clusterID }
        guard !positions.isEmpty else { return [] }

        // Split the place's days wherever the user was away long enough.
        var stretches: [[Int]] = [[positions[0]]]
        for (previous, next) in zip(positions, positions.dropFirst()) {
            // Territories don't overlap, so every day between these two
            // belongs to a day spent somewhere else.
            let daysAway = territories[next].lowerBound - territories[previous].upperBound - 1
            if daysAway >= config.homeAdoptionDays {
                stretches.append([next])
            } else {
                stretches[stretches.count - 1].append(next)
            }
        }

        return stretches.compactMap { stretch in
            let first = days[stretch.first!].index
            let last = days[stretch.last!].index
            let length = last - first + 1
            guard length >= config.homeAdoptionDays else { return nil }

            let daysHere = stretch.reduce(0) { total, position in
                let territory = territories[position].clamped(to: first...last)
                return total + territory.count
            }
            let share = Double(daysHere) / Double(length)
            guard share >= config.homeMinShare else { return nil }
            return Residence(
                clusterID: clusterID,
                firstDay: days[stretch.first!].day,
                lastDay: days[stretch.last!].day,
                share: share
            )
        }
    }

    /// The cluster with the most days, the earliest seen winning a tie.
    private static func mostTimeSpent(days: [LocatedDay], territories: [ClosedRange<Int>]) -> Int? {
        var totals: [Int: Int] = [:]
        for (day, territory) in zip(days, territories) {
            totals[day.clusterID, default: 0] += territory.count
        }
        return totals.min { ($1.value, $0.key) < ($0.value, $1.key) }?.key
    }
}
