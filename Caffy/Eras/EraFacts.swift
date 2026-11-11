import Foundation

/// Everything a title and summary are written from, for one era.
///
/// Plain facts with no wording in them, so the same facts can go to the
/// template narrator now and an on-device language model later.
nonisolated struct EraFacts: Equatable, Sendable {
    /// How an era relates to where the user lived before it.
    enum HomeChange: Equatable, Sendable {
        /// Living somewhere the user hasn't lived before.
        case newHome
        /// Back in a place the user lived before.
        case backHome
    }

    let id: String
    let kind: EraKind
    let start: Date
    /// `nil` for the era the user is living through now.
    let end: Date?
    /// When the era's last photo was taken.
    let lastPhoto: Date
    let momentCount: Int
    /// Set when the era starts because the user moved.
    let homeChange: HomeChange?
    /// Home's name for a home era; the destinations in visit order for a trip.
    /// Empty when no name is known.
    let placeNames: [String]
    /// The latitude of the era's place, to tell southern seasons from
    /// northern ones. `nil` when no photo has a location.
    let latitude: Double?
    /// Everything played during the era. A home era leaves out the days of
    /// trips inside it; a trip covers its whole days, travel included.
    let listening: ListeningProfile
    /// The previous home era's listening, for describing how music changed.
    /// `nil` for trips and for the first home era.
    let previousListening: ListeningProfile?

    var isCurrent: Bool { end == nil }
}

nonisolated extension EraFacts {
    /// Gathers the facts for every draft, in the same order.
    ///
    /// `names` maps place cluster ids (see `HomeTimeline.clusters`) to their
    /// names, as found by `placeNames(for:moments:home:namer:)`.
    static func make(
        for drafts: [EraDraft],
        moments: [PhotoMoment],
        plays: [ListeningEvent],
        home: HomeTimeline,
        names: [Int: PlaceName],
        now: Date,
        calendar: Calendar
    ) -> [EraFacts] {
        let byID = Dictionary(moments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sortedPlays = plays.sorted { ($0.interval.start, $0.song.id) < ($1.interval.start, $1.song.id) }
        let ordered = drafts.sorted { ($0.start, $0.id) < ($1.start, $1.id) }

        // Trips own the whole local days they cover, so the travel there and
        // back counts as the trip's music and not the season's.
        let tripDays = ordered
            .filter { $0.kind == .trip }
            .map { wholeDays(from: $0.start, to: lastPhoto(of: $0, byID: byID), calendar: calendar) }

        var facts: [String: EraFacts] = [:]
        var previousHome: (listening: ListeningProfile, clusterID: Int?)?
        var homesLivedIn = Set<Int>()

        for draft in ordered {
            let last = lastPhoto(of: draft, byID: byID)
            let draftMoments = draft.momentIDs.compactMap { byID[$0] }

            switch draft.kind {
            case .trip:
                let days = wholeDays(from: draft.start, to: last, calendar: calendar)
                let destinations = uniqueInOrder(draftMoments.compactMap { $0.coordinate.flatMap(home.cluster(containing:))?.id })
                facts[draft.id] = EraFacts(
                    id: draft.id,
                    kind: .trip,
                    start: draft.start,
                    end: draft.end,
                    lastPhoto: last,
                    momentCount: draft.momentIDs.count,
                    homeChange: nil,
                    placeNames: destinations.compactMap { names[$0]?.locality },
                    latitude: draft.centre?.latitude,
                    listening: ListeningProfile(Self.plays(in: days, from: sortedPlays, excluding: [])),
                    previousListening: nil
                )

            case .home:
                let interval = DateInterval(start: draft.start, end: max(draft.start, draft.end ?? now))
                let listening = ListeningProfile(Self.plays(in: interval, from: sortedPlays, excluding: tripDays))
                let clusterID = draft.centre.flatMap(home.cluster(containing:))?.id
                    ?? home.home(on: draft.start)?.id

                var change: HomeChange?
                if draft.startReason == .homeChange, let clusterID {
                    change = homesLivedIn.contains(clusterID) ? .backHome : .newHome
                }
                facts[draft.id] = EraFacts(
                    id: draft.id,
                    kind: .home,
                    start: draft.start,
                    end: draft.end,
                    lastPhoto: last,
                    momentCount: draft.momentIDs.count,
                    homeChange: change,
                    placeNames: clusterID.flatMap { names[$0]?.locality }.map { [$0] } ?? [],
                    latitude: draft.centre?.latitude,
                    listening: listening,
                    previousListening: previousHome?.listening
                )
                previousHome = (listening, clusterID)
                if let clusterID { homesLivedIn.insert(clusterID) }
            }
        }
        return drafts.map { facts[$0.id]! }
    }

    /// The place clusters whose names the eras need, lowest id first: each
    /// home era's home and each trip's destinations.
    static func clustersToName(for drafts: [EraDraft], moments: [PhotoMoment], home: HomeTimeline) -> [Int] {
        let byID = Dictionary(moments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ids = Set<Int>()
        for draft in drafts {
            switch draft.kind {
            case .home:
                if let id = draft.centre.flatMap(home.cluster(containing:))?.id ?? home.home(on: draft.start)?.id {
                    ids.insert(id)
                }
            case .trip:
                for moment in draft.momentIDs.compactMap({ byID[$0] }) {
                    if let id = moment.coordinate.flatMap(home.cluster(containing:))?.id {
                        ids.insert(id)
                    }
                }
            }
        }
        return ids.sorted()
    }

    /// Looks up the name of every place the eras need, one at a time in id
    /// order so the lookups always happen in the same order.
    static func placeNames(
        for drafts: [EraDraft],
        moments: [PhotoMoment],
        home: HomeTimeline,
        namer: some PlaceNamer
    ) async -> [Int: PlaceName] {
        var names: [Int: PlaceName] = [:]
        for id in clustersToName(for: drafts, moments: moments, home: home) {
            names[id] = await namer.name(for: home.clusters[id].centre)
        }
        return names
    }

    // MARK: - Helpers

    private static func lastPhoto(of draft: EraDraft, byID: [String: PhotoMoment]) -> Date {
        draft.momentIDs.last.flatMap { byID[$0]?.end } ?? draft.end ?? draft.start
    }

    /// From midnight on `start`'s day to midnight after `end`'s day.
    private static func wholeDays(from start: Date, to end: Date, calendar: Calendar) -> DateInterval {
        let first = calendar.startOfDay(for: start)
        let last = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(start, end)))!
        return DateInterval(start: first, end: last)
    }

    /// Plays starting in `interval` (half-open) and in none of `excluded`.
    /// `plays` must be sorted by start.
    private static func plays(in interval: DateInterval, from plays: [ListeningEvent], excluding excluded: [DateInterval]) -> [ListeningEvent] {
        var low = 0
        var high = plays.count
        while low < high {
            let middle = (low + high) / 2
            if plays[middle].interval.start < interval.start { low = middle + 1 } else { high = middle }
        }
        let relevant = excluded.filter { $0.intersects(interval) }
        var result: [ListeningEvent] = []
        var index = low
        while index < plays.count, plays[index].interval.start < interval.end {
            let time = plays[index].interval.start
            if !relevant.contains(where: { $0.start <= time && time < $0.end }) {
                result.append(plays[index])
            }
            index += 1
        }
        return result
    }

    private static func uniqueInOrder(_ ids: [Int]) -> [Int] {
        var seen = Set<Int>()
        return ids.filter { seen.insert($0).inserted }
    }
}
