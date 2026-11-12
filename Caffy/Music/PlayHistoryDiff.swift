import Foundation

/// Works out the plays that happened between two reads of one library song.
///
/// The library only keeps a song's last play time and a total play count, so
/// a play's time is known exactly only for the most recent one. Any other new
/// plays are only known to fall somewhere between the earlier read and that
/// last play, so they're recorded as estimates over that window.
///
/// A pure function: the same reads always give the same plays.
nonisolated enum PlayHistoryDiff {
    /// What an earlier read saw of the song.
    struct State: Equatable, Sendable {
        var lastPlayedDate: Date?
        var playCount: Int
    }

    /// The plays between `previous` and `current`.
    ///
    /// - First sighting: one exact play at its `lastPlayedDate`, saved so it
    ///   outlives the next play overwriting the date.
    /// - Date moved forward: one exact play at the new date. If the count went
    ///   up by `n > 1`, the other `n − 1` plays are estimated between the
    ///   later of the earlier read and the old date, and the new date.
    /// - Count went up but the date didn't move (counts synced from another
    ///   device): `n` estimated plays between the earlier read and `now`.
    /// - Count fell, or the date went back or disappeared (the song was
    ///   re-added, or the library was reset): no plays. The caller should
    ///   still save `current` as the new baseline.
    ///
    /// Several estimated plays split their window into equal parts rather
    /// than all covering it: identical plays would be taken for one play
    /// reported twice. A play's matching weight is its average over its
    /// interval, so equal parts add up to the same total as `n` copies of the
    /// whole window. A window longer than `maxEstimatedWindow` (or with no
    /// length) gives plays that aren't `isMatchable`.
    ///
    /// - Parameter previousCheck: when the library was last read, if ever.
    static func newPlays(
        previous: State?,
        current: LibrarySongSnapshot,
        previousCheck: Date?,
        now: Date,
        maxEstimatedWindow: TimeInterval
    ) -> [ListeningEvent] {
        let song = current.song
        guard let previous else {
            return current.lastPlayedDate.map { [exact(song, at: $0)] } ?? []
        }

        let added = current.playCount - previous.playCount
        guard added >= 0 else { return [] }

        let dateMoved: Bool
        switch (previous.lastPlayedDate, current.lastPlayedDate) {
        case let (before?, after?):
            guard after >= before else { return [] }
            dateMoved = after > before
        case (nil, .some):
            dateMoved = true
        case (.some, nil):
            return []
        case (nil, nil):
            dateMoved = false
        }

        if dateMoved, let last = current.lastPlayedDate {
            var plays = [exact(song, at: last)]
            if added > 1 {
                let window = earlierPlaysWindow(before: last, previous: previous, previousCheck: previousCheck)
                plays += estimated(song, count: added - 1, over: window, maxWindow: maxEstimatedWindow)
            }
            return plays
        }

        guard added > 0 else { return [] }
        let start = min(previousCheck ?? previous.lastPlayedDate ?? now, now)
        return estimated(song, count: added, over: DateInterval(start: start, end: now), maxWindow: maxEstimatedWindow)
    }

    /// Where the plays before the latest one fall: after the earlier read
    /// when that's before `last`, otherwise (a play on another device that
    /// synced late) anywhere after the old last-played date.
    private static func earlierPlaysWindow(before last: Date, previous: State, previousCheck: Date?) -> DateInterval {
        let candidates = [previousCheck, previous.lastPlayedDate].compactMap { $0 }
        if let tight = candidates.max(), tight < last {
            return DateInterval(start: tight, end: last)
        }
        if let loose = previous.lastPlayedDate ?? previousCheck, loose < last {
            return DateInterval(start: loose, end: last)
        }
        return DateInterval(start: last, duration: 0)
    }

    private static func exact(_ song: Song, at date: Date) -> ListeningEvent {
        ListeningEvent(song: song, interval: DateInterval(start: date, duration: 0))
    }

    /// `count` estimated plays splitting `window` into equal parts.
    static func estimated(_ song: Song, count: Int, over window: DateInterval, maxWindow: TimeInterval) -> [ListeningEvent] {
        guard count > 0 else { return [] }
        let isMatchable = window.duration > 0 && window.duration <= maxWindow
        let part = window.duration / Double(count)
        return (0..<count).map { index in
            let start = window.start.addingTimeInterval(part * Double(index))
            let end = index == count - 1 ? window.end : window.start.addingTimeInterval(part * Double(index + 1))
            return ListeningEvent(song: song, interval: DateInterval(start: start, end: end), isEstimated: true, isMatchable: isMatchable)
        }
    }
}
