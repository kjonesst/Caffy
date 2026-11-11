import Foundation

/// The eras worked out from a library, before names, colours and words.
nonisolated struct EraBuild: Sendable {
    let home: HomeTimeline
    /// Every era, oldest first, frozen ones included.
    let drafts: [EraDraft]
    /// The eras that are frozen after this build: those passed in as frozen,
    /// plus any that froze just now.
    let frozenIDs: Set<String>
}

/// Works out every era from the whole library, keeping frozen eras as they are.
///
/// A pure function: the same moments, plays, frozen eras and `now` always
/// give the same eras.
///
/// - Moments already in a frozen era stay there.
/// - A new moment dated inside a frozen era (an old photo imported late)
///   joins that era without re-cutting it; the shortest era wins when a trip
///   and its season both contain it.
/// - Other new moments dated before the last frozen era ends are cut into
///   eras of their own, separately within each gap between frozen eras.
/// - Everything after the last frozen era is cut as usual.
/// - Photos that have gone from the library leave their frozen era, and a
///   frozen era with no photos left disappears.
///
/// An era freezes once it ended more than `freezeAfter` ago and every era
/// that started before it has frozen too. So frozen eras are always the
/// oldest ones, and a trip can't freeze while the season around it is still
/// going.
nonisolated enum EraBuilder {
    static func build(
        moments: [PhotoMoment],
        plays: [ListeningEvent],
        frozen: [EraDraft] = [],
        now: Date,
        calendar: Calendar,
        config: EraBuildConfig = .standard
    ) -> EraBuild {
        let sortedMoments = moments.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        let home = HomeInference.infer(sortedMoments, calendar: calendar, config: config)
        let order = Dictionary(sortedMoments.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Frozen eras, keeping only the photos still in the library.
        var kept: [(draft: EraDraft, momentIDs: [String])] = frozen
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
            .map { ($0, $0.momentIDs.filter { order[$0] != nil }) }
        let frozenMomentIDs = Set(kept.flatMap(\.momentIDs))
        let boundary = kept.compactMap(\.draft.end).max()

        // Sort every other moment: into a frozen era, a gap, or after them all.
        var gaps: [Int: [PhotoMoment]] = [:]
        var after: [PhotoMoment] = []
        for moment in sortedMoments where !frozenMomentIDs.contains(moment.id) {
            guard let boundary, moment.start <= boundary else {
                after.append(moment)
                continue
            }
            let containing = kept.indices
                .filter { kept[$0].draft.start <= moment.start && moment.start <= (kept[$0].draft.end ?? boundary) }
                .min { a, b in
                    let lengthA = (kept[a].draft.end ?? boundary).timeIntervalSince(kept[a].draft.start)
                    let lengthB = (kept[b].draft.end ?? boundary).timeIntervalSince(kept[b].draft.start)
                    return (lengthA, kept[a].draft.id) < (lengthB, kept[b].draft.id)
                }
            if let containing {
                kept[containing].momentIDs.append(moment.id)
            } else {
                // The gap before the first frozen era that starts after it.
                let gap = kept.firstIndex { $0.draft.start > moment.start } ?? kept.count
                gaps[gap, default: []].append(moment)
            }
        }

        var drafts: [EraDraft] = kept.compactMap { era in
            guard !era.momentIDs.isEmpty else { return nil }
            let ids = era.momentIDs.sorted { order[$0]! < order[$1]! }
            let draft = era.draft
            return EraDraft(id: draft.id, kind: draft.kind, momentIDs: ids, start: draft.start, end: draft.end, centre: draft.centre, startReason: draft.startReason)
        }
        for gap in gaps.keys.sorted() {
            drafts += EraSegmenter.segment(gaps[gap]!, plays: plays, home: home, now: now, calendar: calendar, config: config)
        }

        var fresh = EraSegmenter.segment(after, plays: plays, home: home, now: now, calendar: calendar, config: config)
        if let boundary {
            fresh = explainFirstAfterFrozen(fresh, frozen: drafts, boundary: boundary, home: home, config: config)
        }
        drafts += fresh
        drafts.sort { ($0.start, $0.id) < ($1.start, $1.id) }

        return EraBuild(
            home: home,
            drafts: drafts,
            frozenIDs: frozenIDs(of: drafts, alreadyFrozen: Set(frozen.map(\.id)), now: now, config: config)
        )
    }

    /// Which eras are frozen: walking oldest first, each one that was frozen
    /// or ended more than `freezeAfter` ago, until the first that isn't.
    static func frozenIDs(of drafts: [EraDraft], alreadyFrozen: Set<String>, now: Date, config: EraBuildConfig) -> Set<String> {
        let cutoff = now.addingTimeInterval(-config.freezeAfter)
        var ids = Set<String>()
        for draft in drafts.sorted(by: { ($0.start, $0.id) < ($1.start, $1.id) }) {
            if alreadyFrozen.contains(draft.id) {
                ids.insert(draft.id)
                continue
            }
            guard let end = draft.end, end < cutoff else { break }
            ids.insert(draft.id)
        }
        return ids
    }

    /// The first home era after the frozen ones was cut on its own, so its
    /// start reason only says "first moment". Says why it really starts
    /// there when the reason is a move or a long gap.
    private static func explainFirstAfterFrozen(
        _ drafts: [EraDraft],
        frozen: [EraDraft],
        boundary: Date,
        home: HomeTimeline,
        config: EraBuildConfig
    ) -> [EraDraft] {
        guard let index = drafts.firstIndex(where: { $0.kind == .home }),
              drafts[index].startReason == .firstMoment,
              let lastHome = frozen.filter({ $0.kind == .home }).max(by: { ($0.start, $0.id) < ($1.start, $1.id) })
        else { return drafts }

        let first = drafts[index]
        let reason: EraBoundaryReason
        if home.home(on: first.start)?.id != home.home(on: lastHome.start)?.id {
            reason = .homeChange
        } else if first.start.timeIntervalSince(boundary) >= config.longGap {
            reason = .longGap
        } else {
            return drafts
        }
        var updated = drafts
        updated[index] = EraDraft(
            id: first.id, kind: first.kind, momentIDs: first.momentIDs,
            start: first.start, end: first.end, centre: first.centre, startReason: reason
        )
        return updated
    }
}
