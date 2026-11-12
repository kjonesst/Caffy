import Foundation
import SwiftData

/// How well real listening data covers the user's photo moments: the
/// go/no-go check for matching songs to moments (README roadmap step 3).
///
/// Every moment is matched twice: once with only the library's last-played
/// dates (what the library says with nothing recorded), and once with the
/// history Caffy has recorded (what the app actually uses).
nonisolated struct ListeningCoverage: Equatable, Sendable {
    /// How long ago something happened.
    enum Age: Int, CaseIterable, Comparable, Sendable {
        case day, week, month, year, older

        static func of(_ date: Date, now: Date) -> Age {
            let days = now.timeIntervalSince(date) / (24 * 60 * 60)
            switch days {
            case ..<1: return .day
            case ..<7: return .week
            case ..<30: return .month
            case ..<365: return .year
            default: return .older
            }
        }

        var label: String {
            switch self {
            case .day: "≤ 1 day"
            case .week: "≤ 7 days"
            case .month: "≤ 30 days"
            case .year: "≤ 1 year"
            case .older: "older"
            }
        }

        static func < (lhs: Age, rhs: Age) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// How a group of moments matched.
    struct MatchCounts: Equatable, Sendable {
        /// Songs played near the moment.
        var near = 0
        /// Only songs from the same day.
        var looseOnly = 0
        var none = 0

        var total: Int { near + looseOnly + none }
        var nearShare: Double { total == 0 ? 0 : Double(near) / Double(total) }

        static func + (lhs: MatchCounts, rhs: MatchCounts) -> MatchCounts {
            MatchCounts(near: lhs.near + rhs.near, looseOnly: lhs.looseOnly + rhs.looseOnly, none: lhs.none + rhs.none)
        }
    }

    /// The go/no-go answer, judged on the last 30 days of moments.
    enum Verdict: Equatable, Sendable {
        case tooEarly(daysRecorded: Int)
        case noRecentMoments
        case pass(nearShare: Double)
        case borderline(nearShare: Double)
        case fail(nearShare: Double)
    }

    /// Thresholds for the verdict. Set before recording starts; don't tune
    /// them to the numbers.
    static let daysNeeded = 14
    static let passShare = 0.4
    static let borderlineShare = 0.2

    let now: Date
    let hasMusicAccess: Bool
    let hasPhotoAccess: Bool

    let librarySongs: Int
    let songsWithLastPlayed: Int
    let songsWithoutCatalogID: Int
    /// Songs by how long ago they were last played.
    let lastPlayedAges: [Age: Int]

    /// When Caffy first read the library, if it has.
    let recordingSince: Date?
    let libraryReads: Int
    let exactPlays: Int
    let estimatedPlays: Int
    /// Estimated plays whose window was too long to match to a moment.
    let unmatchablePlays: Int

    let moments: Int
    /// Moments by age, matched with last-played dates only.
    let lastPlayedMatches: [Age: MatchCounts]
    /// Moments by age, matched with recorded history.
    let recordedMatches: [Age: MatchCounts]

    /// What `dateAdded` could add to each era's songs.
    let additions: LibraryAdditionsReport

    init(
        moments: [PhotoMoment],
        songs: [LibrarySongSnapshot]?,
        recordedPlays: [ListeningEvent],
        recordingSince: Date?,
        libraryReads: Int,
        hasPhotoAccess: Bool = true,
        eras: [LibraryAdditions.EraWindow] = [],
        now: Date,
        calendar: Calendar,
        config: EraBuildConfig = .standard
    ) {
        self.now = now
        hasMusicAccess = songs != nil
        self.hasPhotoAccess = hasPhotoAccess
        let songs = songs ?? []

        librarySongs = songs.count
        songsWithLastPlayed = songs.count { $0.lastPlayedDate != nil }
        songsWithoutCatalogID = songs.count { $0.catalogID == nil }
        var ages: [Age: Int] = [:]
        for date in songs.compactMap(\.lastPlayedDate) {
            ages[Age.of(date, now: now), default: 0] += 1
        }
        lastPlayedAges = ages

        self.recordingSince = recordingSince
        self.libraryReads = libraryReads
        exactPlays = recordedPlays.count { !$0.isEstimated }
        estimatedPlays = recordedPlays.count { $0.isEstimated }
        unmatchablePlays = recordedPlays.count { !$0.isMatchable }

        self.moments = moments.count
        let lastPlayed = MediaPlayerListeningSource.plays(from: songs)
        lastPlayedMatches = Self.counts(MusicMatcher.match(moments, with: lastPlayed, calendar: calendar, config: config), now: now)
        recordedMatches = Self.counts(MusicMatcher.match(moments, with: recordedPlays, calendar: calendar, config: config), now: now)
        additions = LibraryAdditionsReport(songs: songs, eras: eras, now: now, calendar: calendar, config: config)
    }

    private static func counts(_ matched: [MatchedMoment], now: Date) -> [Age: MatchCounts] {
        var counts: [Age: MatchCounts] = [:]
        for moment in matched {
            let age = Age.of(moment.moment.end, now: now)
            if moment.songs.isEmpty {
                counts[age, default: MatchCounts()].none += 1
            } else if moment.songs.allSatisfy(\.isLoose) {
                counts[age, default: MatchCounts()].looseOnly += 1
            } else {
                counts[age, default: MatchCounts()].near += 1
            }
        }
        return counts
    }

    /// Whole days since recording started.
    var daysRecorded: Int {
        recordingSince.map { max(0, Int(now.timeIntervalSince($0) / (24 * 60 * 60))) } ?? 0
    }

    /// Recorded-history matches for moments from the last 30 days.
    var recentRecordedMatches: MatchCounts {
        [Age.day, .week, .month].reduce(MatchCounts()) { $0 + (recordedMatches[$1] ?? MatchCounts()) }
    }

    var verdict: Verdict {
        guard daysRecorded >= Self.daysNeeded else { return .tooEarly(daysRecorded: daysRecorded) }
        let recent = recentRecordedMatches
        guard recent.total > 0 else { return .noRecentMoments }
        let share = recent.nearShare
        if share >= Self.passShare { return .pass(nearShare: share) }
        if share >= Self.borderlineShare { return .borderline(nearShare: share) }
        return .fail(nearShare: share)
    }

    // MARK: - Text

    /// The whole report as plain text, to read on the phone and share.
    var text: String {
        var lines: [String] = []
        lines.append("Caffy listening coverage, \(now.formatted(date: .abbreviated, time: .shortened))")
        lines.append("Music access: \(hasMusicAccess ? "yes" : "no") · Photo access: \(hasPhotoAccess ? "yes" : "no")")

        lines.append("")
        lines.append("LIBRARY")
        lines.append("Songs: \(librarySongs) · last-played date: \(songsWithLastPlayed) · no catalog id: \(songsWithoutCatalogID)")
        lines.append("Last played: " + Age.allCases.map { "\($0.label) \(lastPlayedAges[$0] ?? 0)" }.joined(separator: " · "))

        lines.append("")
        lines.append("RECORDED HISTORY")
        if let recordingSince {
            lines.append("Recording since \(recordingSince.formatted(date: .abbreviated, time: .omitted)) (\(daysRecorded) days) · library reads: \(libraryReads)")
        } else {
            lines.append("Not recording yet")
        }
        lines.append("Plays: \(exactPlays) exact · \(estimatedPlays) estimated (\(unmatchablePlays) too vague to match)")

        lines.append("")
        lines.append("MOMENTS: \(moments) (near / same day only / none)")
        lines.append(Self.row("", "last-played only", "recorded history"))
        for age in Age.allCases {
            lines.append(Self.row(age.label, Self.cell(lastPlayedMatches[age]), Self.cell(recordedMatches[age])))
        }
        let allLastPlayed = lastPlayedMatches.values.reduce(MatchCounts(), +)
        let allRecorded = recordedMatches.values.reduce(MatchCounts(), +)
        lines.append(Self.row("all", Self.cell(allLastPlayed), Self.cell(allRecorded)))

        lines.append("")
        lines.append(additions.text)

        lines.append("")
        lines.append("VERDICT: \(verdictText)")
        lines.append(
            "Pass: ≥ \(Self.percent(Self.passShare)) of the last 30 days' moments have songs played near them, "
                + "after \(Self.daysNeeded) days of recording. Borderline: \(Self.percent(Self.borderlineShare))–\(Self.percent(Self.passShare)). "
                + "Then spot-check 10 matched moments (pass: 7 right)."
        )
        return lines.joined(separator: "\n")
    }

    private var verdictText: String {
        switch verdict {
        case .tooEarly(let days): "Too early: \(days) of \(Self.daysNeeded) days recorded"
        case .noRecentMoments: "No moments in the last 30 days to judge"
        case .pass(let share): "Pass (\(Self.percent(share)) near)"
        case .borderline(let share): "Borderline (\(Self.percent(share)) near): try background recording"
        case .fail(let share): "Fail (\(Self.percent(share)) near): music becomes era-level only"
        }
    }

    private static func cell(_ counts: MatchCounts?) -> String {
        let counts = counts ?? MatchCounts()
        return "\(counts.near) / \(counts.looseOnly) / \(counts.none)"
    }

    private static func row(_ label: String, _ first: String, _ second: String) -> String {
        label.padding(toLength: 10, withPad: " ", startingAt: 0)
            + first.padding(toLength: 18, withPad: " ", startingAt: 0)
            + second
    }

    private static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }
}

// MARK: - Running it on the device

extension ListeningCoverage {
    /// Reads the photo and music libraries, records a pass, and builds the
    /// report from the real data.
    @MainActor
    static func run(container: ModelContainer, now: Date = .now, calendar: Calendar = .current) async -> ListeningCoverage {
        let photos = await PhotoKitLibraryReader().photos()
        let moments = await group(photos ?? [])
        let reader = MediaPlayerLibraryReader()
        await ListeningRecorder(modelContainer: container, reader: reader).record(now: now)
        let songs = await reader.songs()
        let recorded = (try? await RecordedListeningSource(container: container).plays(in: DateInterval(start: .distantPast, end: now))) ?? []
        let history = historyFacts(in: container.mainContext)
        let eras = savedEras(in: container.mainContext, now: now)
        return ListeningCoverage(
            moments: moments,
            songs: songs,
            recordedPlays: recorded,
            recordingSince: history.since,
            libraryReads: history.reads,
            hasPhotoAccess: photos != nil,
            eras: eras,
            now: now,
            calendar: calendar
        )
    }

    /// The eras the last sync saved. Sample data (no `eraID`) is left out.
    @MainActor
    private static func savedEras(in context: ModelContext, now: Date) -> [LibraryAdditions.EraWindow] {
        let eras = (try? context.fetch(FetchDescriptor<Era>(predicate: #Predicate { $0.eraID != nil }))) ?? []
        return eras.compactMap { era in
            era.eraID.map { id in
                LibraryAdditions.EraWindow(
                    id: id,
                    title: era.title,
                    start: era.startDate,
                    end: era.endDate ?? now,
                    isTrip: era.kind == .trip
                )
            }
        }
    }

    @concurrent
    private static func group(_ photos: [PhotoItem]) async -> [PhotoMoment] {
        MomentGrouper.group(photos)
    }

    @MainActor
    private static func historyFacts(in context: ModelContext) -> (since: Date?, reads: Int) {
        var first = FetchDescriptor<LibrarySongState>(sortBy: [SortDescriptor(\.firstSeenAt)])
        first.fetchLimit = 1
        let since = (try? context.fetch(first))?.first?.firstSeenAt
        let reads = (try? context.fetchCount(FetchDescriptor<ListeningCheck>())) ?? 0
        return (since, reads)
    }
}
