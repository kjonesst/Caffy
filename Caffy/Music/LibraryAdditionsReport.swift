import Foundation

/// How much `dateAdded` can tell about each era: the go/no-go check for
/// filling era playlists from library additions.
///
/// Built from the library and the eras with `LibraryAdditions`, the same steps
/// the pipeline would run, so what this shows is what eras would get.
nonisolated struct LibraryAdditionsReport: Equatable, Sendable {
    /// Additions on one local day.
    struct DayCount: Equatable, Sendable {
        /// The day's midnight.
        let day: Date
        let count: Int
    }

    /// Additions in one month.
    struct MonthCount: Equatable, Sendable {
        /// The first moment of the month.
        let month: Date
        let count: Int
    }

    /// How a saved era's playlist splits by where its songs came from.
    struct PlaylistSplit: Equatable, Sendable {
        var near = 0
        var added = 0
        var loose = 0

        init(near: Int = 0, added: Int = 0, loose: Int = 0) {
            self.near = near
            self.added = added
            self.loose = loose
        }

        init(_ songs: [EraSong]) {
            near = songs.count { $0.evidence == .nearPlay }
            added = songs.count { $0.evidence == .libraryAdded }
            loose = songs.count { $0.evidence == .loosePlay }
        }
    }

    /// One era's songs after each step.
    struct EraRow: Equatable, Sendable {
        let era: LibraryAdditions.EraWindow
        /// Ended more than `freezeAfter` ago.
        let isPast: Bool
        /// Every song added in the era's window.
        let raw: Int
        /// …played enough to count.
        let played: Int
        /// …after bulk days.
        let afterBulkDays: Int
        /// …after album collapsing.
        let afterAlbums: Int
        /// The era's songs, best first: every one left after album collapsing.
        let songs: [LibraryAdditions.Candidate]
        /// The saved era's playlist, if known.
        var playlist: PlaylistSplit? = nil

        var top: ArraySlice<LibraryAdditions.Candidate> { songs.prefix(LibraryAdditionsReport.topSongsShown) }
    }

    static let topDaysShown = 15
    static let monthsShown = 36
    static let topSongsShown = 5
    /// A past era with at least this many songs counts as filled.
    static let enoughSongs = 5
    /// A single day holding this share of the library suggests `dateAdded`
    /// was reset by a resync.
    static let resetWarningShare = 0.3

    let now: Date
    let calendar: Calendar
    let bulkDayThreshold: Int

    let librarySongs: Int
    let songsWithDateAdded: Int
    let songsWithoutDateAdded: Int
    let earliestAdded: Date?
    let latestAdded: Date?

    /// The days with the most additions, most first (the earlier day wins a tie).
    let topDays: [DayCount]
    /// Days with more than `bulkDayThreshold` additions, oldest first.
    let bulkDays: [Date]
    /// The biggest day's additions as a share of the whole library.
    let biggestDayShare: Double
    /// Additions per month for the last `monthsShown` months, oldest first,
    /// empty months included.
    let months: [MonthCount]

    /// Oldest first.
    let eras: [EraRow]

    init(
        songs: [LibrarySongSnapshot],
        eras: [LibraryAdditions.EraWindow],
        playlists: [String: PlaylistSplit] = [:],
        now: Date,
        calendar: Calendar,
        config: EraBuildConfig = .standard
    ) {
        self.now = now
        self.calendar = calendar
        bulkDayThreshold = config.bulkDayThreshold

        let filtered = LibraryAdditions.filtered(library: songs, calendar: calendar, config: config)
        librarySongs = songs.count
        songsWithDateAdded = filtered.dated.count
        songsWithoutDateAdded = songs.count - filtered.dated.count
        earliestAdded = filtered.dated.first?.dateAdded
        latestAdded = filtered.dated.last?.dateAdded

        let days = filtered.additionsPerDay
            .map { DayCount(day: $0.key, count: $0.value) }
            .sorted { ($1.count, $0.day) < ($0.count, $1.day) }
        topDays = Array(days.prefix(Self.topDaysShown))
        bulkDays = filtered.bulkDays
        biggestDayShare = songs.isEmpty ? 0 : Double(days.first?.count ?? 0) / Double(songs.count)
        months = Self.months(of: filtered.dated, now: now, calendar: calendar)

        let raw = LibraryAdditions.assign(filtered.dated, to: eras, config: config)
        let played = LibraryAdditions.assign(filtered.eligible, to: eras, config: config)
        let afterBulkDays = LibraryAdditions.assign(filtered.afterBulkDays, to: eras, config: config)
        let afterAlbums = LibraryAdditions.assign(filtered.afterAlbums, to: eras, config: config)
        let ranked = LibraryAdditions.ranked(afterAlbums, eras: eras, config: config)
        self.eras = eras
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
            .map { era in
                EraRow(
                    era: era,
                    isPast: now.timeIntervalSince(era.end) > config.freezeAfter,
                    raw: raw[era.id]?.count ?? 0,
                    played: played[era.id]?.count ?? 0,
                    afterBulkDays: afterBulkDays[era.id]?.count ?? 0,
                    afterAlbums: afterAlbums[era.id]?.count ?? 0,
                    songs: ranked[era.id] ?? [],
                    playlist: playlists[era.id]
                )
            }
    }

    private static func months(of dated: [LibrarySongSnapshot], now: Date, calendar: Calendar) -> [MonthCount] {
        guard let thisMonth = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
        let starts = (0..<monthsShown).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }
        guard let first = starts.first else { return [] }
        var counts: [Date: Int] = [:]
        for song in dated {
            guard let added = song.dateAdded, added >= first,
                  let month = calendar.dateInterval(of: .month, for: added)?.start
            else { continue }
            counts[month, default: 0] += 1
        }
        return starts.map { MonthCount(month: $0, count: counts[$0] ?? 0) }
    }

    /// The day with the most additions, if any song has a `dateAdded`.
    var biggestDay: DayCount? { topDays.first }

    var pastEras: Int { eras.count { $0.isPast } }
    /// Past eras with at least `enoughSongs` songs.
    var filledPastEras: Int { eras.count { $0.isPast && $0.songs.count >= Self.enoughSongs } }

    // MARK: - Text

    /// This section of the coverage report, as plain text.
    var text: String {
        var lines: [String] = []
        lines.append("LIBRARY ADDITIONS")
        guard librarySongs > 0 else {
            lines.append("No library songs to read")
            return lines.joined(separator: "\n")
        }
        lines.append("Date added: \(songsWithDateAdded) · none: \(songsWithoutDateAdded)")
        if let earliestAdded, let latestAdded {
            lines.append("From \(day(earliestAdded)) to \(day(latestAdded))")
        }
        if let biggestDay {
            lines.append("Biggest day: \(day(biggestDay.day)), \(biggestDay.count) songs (\(Self.percent(biggestDayShare)) of the library)")
            if biggestDayShare >= Self.resetWarningShare {
                lines.append("! Date added may have been reset by a resync that day; additions before it can't be trusted.")
            }
        }
        lines.append("Bulk days (> \(bulkDayThreshold) additions): \(bulkDays.count)")

        lines.append("")
        lines.append("Top days:")
        for entry in topDays {
            lines.append("  \(day(entry.day))  \(entry.count)")
        }

        lines.append("")
        lines.append("By month (last \(Self.monthsShown)):")
        let most = months.map(\.count).max() ?? 0
        for entry in months {
            let width = most == 0 || entry.count == 0 ? 0 : max(1, Int((Double(entry.count) / Double(most) * 30).rounded()))
            let bar = String(repeating: "█", count: width)
            lines.append("  \(month(entry.month))  \(bar)\(width > 0 ? " " : "")\(entry.count)")
        }

        lines.append("")
        if eras.isEmpty {
            lines.append("No saved eras yet: sync from Home first")
        } else {
            lines.append("Eras: added / played / bulk days / albums")
            for row in eras {
                let era = row.era
                let name = era.title.isEmpty ? era.id : era.title
                // The current era's window ends at `now`.
                let end = era.end < now ? day(era.end) : "now"
                lines.append("\(name) · \(era.isTrip ? "trip" : "home") · \(day(era.start)) – \(end)")
                lines.append("  \(row.raw) / \(row.played) / \(row.afterBulkDays) / \(row.afterAlbums)")
                if let playlist = row.playlist {
                    lines.append("  playlist: near \(playlist.near) · added \(playlist.added) · loose \(playlist.loose)")
                }
                for (rank, candidate) in row.top.enumerated() {
                    let song = candidate.snapshot
                    lines.append("  \(rank + 1). \(song.title) – \(song.artist) (\(song.playCount) plays)")
                }
            }
            lines.append("")
            lines.append("Past eras with ≥ \(Self.enoughSongs) songs: \(filledPastEras) of \(pastEras)")
        }
        return lines.joined(separator: "\n")
    }

    /// `2024-03-09`, in the report's calendar.
    private func day(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `2024-03`, in the report's calendar.
    private func month(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    private static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }
}
