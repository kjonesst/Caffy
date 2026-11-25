import Foundation
import SwiftData

/// How well real listening data covers the user's photo moments: the
/// go/no-go check for matching songs to moments (README roadmap step 3).
///
/// Every moment is matched three times: with only the library's last-played
/// dates (what the library says with nothing recorded), with the history
/// Caffy has recorded (what the app actually uses), and with only the plays
/// Caffy saw happen (recorded history without seeded plays: what recording
/// adds). The verdict reads the last one.
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

    /// The go/no-go answer, judged on the moments since recording began,
    /// matched with observed plays only.
    enum Verdict: Equatable, Sendable {
        case tooEarly(daysRecorded: Int)
        case noMomentsSinceRecording
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
    /// Last-played dates from before recording began (`ListeningEvent.isSeeded`).
    let seededPlays: Int
    /// Exact plays Caffy saw happen.
    let exactPlays: Int
    let estimatedPlays: Int
    /// Estimated plays whose window was too long to match to a moment.
    let unmatchablePlays: Int

    let moments: Int
    /// Moments by age, matched with last-played dates only.
    let lastPlayedMatches: [Age: MatchCounts]
    /// Moments by age, matched with recorded history.
    let recordedMatches: [Age: MatchCounts]
    /// Moments by age, matched with observed plays only (recorded history
    /// without seeded plays).
    let observedMatches: [Age: MatchCounts]
    /// Moments that started once recording had begun, matched with observed
    /// plays only. What the verdict judges.
    let observedSinceRecording: MatchCounts

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
        playlists: [String: LibraryAdditionsReport.PlaylistSplit] = [:],
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
        seededPlays = recordedPlays.count { $0.isSeeded }
        exactPlays = recordedPlays.count { !$0.isEstimated && !$0.isSeeded }
        estimatedPlays = recordedPlays.count { $0.isEstimated && !$0.isSeeded }
        unmatchablePlays = recordedPlays.count { !$0.isMatchable }

        self.moments = moments.count
        let lastPlayed = MediaPlayerListeningSource.plays(from: songs)
        lastPlayedMatches = Self.counts(MusicMatcher.match(moments, with: lastPlayed, calendar: calendar, config: config), now: now)
        recordedMatches = Self.counts(MusicMatcher.match(moments, with: recordedPlays, calendar: calendar, config: config), now: now)
        let observed = MusicMatcher.match(moments, with: recordedPlays.filter { !$0.isSeeded }, calendar: calendar, config: config)
        observedMatches = Self.counts(observed, now: now)
        observedSinceRecording = recordingSince.map { since in
            Self.counts(observed.filter { $0.moment.start >= since }, now: now).values.reduce(MatchCounts(), +)
        } ?? MatchCounts()
        additions = LibraryAdditionsReport(songs: songs, eras: eras, playlists: playlists, now: now, calendar: calendar, config: config)
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

    /// Judged on `observedSinceRecording`: most of a 30-day window would
    /// predate recording, and seeded plays aren't what recording adds.
    var verdict: Verdict {
        guard daysRecorded >= Self.daysNeeded else { return .tooEarly(daysRecorded: daysRecorded) }
        let judged = observedSinceRecording
        guard judged.total > 0 else { return .noMomentsSinceRecording }
        let share = judged.nearShare
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
        lines.append(
            "Plays: \(seededPlays) seeded (last-played dates from before recording) · \(exactPlays) observed exact · "
                + "\(estimatedPlays) estimated (\(unmatchablePlays) too vague to match)"
        )

        lines.append("")
        lines.append("MOMENTS: \(moments) (near / same day only / none)")
        lines.append(Self.row("", "last-played only", "recorded history", "observed only"))
        for age in Age.allCases {
            lines.append(Self.row(
                age.label, Self.cell(lastPlayedMatches[age]), Self.cell(recordedMatches[age]), Self.cell(observedMatches[age])
            ))
        }
        let allLastPlayed = lastPlayedMatches.values.reduce(MatchCounts(), +)
        let allRecorded = recordedMatches.values.reduce(MatchCounts(), +)
        let allObserved = observedMatches.values.reduce(MatchCounts(), +)
        lines.append(Self.row("all", Self.cell(allLastPlayed), Self.cell(allRecorded), Self.cell(allObserved)))
        lines.append("Since recording began, observed only: \(Self.cell(observedSinceRecording))")

        lines.append("")
        lines.append(additions.text)

        lines.append("")
        lines.append("VERDICT: \(verdictText)")
        lines.append(
            "Pass: ≥ \(Self.percent(Self.passShare)) of the moments since recording began have songs Caffy saw played near them "
                + "(observed only), after \(Self.daysNeeded) days of recording. Borderline: \(Self.percent(Self.borderlineShare))–\(Self.percent(Self.passShare)). "
                + "Then spot-check 10 matched moments (pass: 7 right)."
        )
        return lines.joined(separator: "\n")
    }

    private var verdictText: String {
        switch verdict {
        case .tooEarly(let days): "Too early: \(days) of \(Self.daysNeeded) days recorded"
        case .noMomentsSinceRecording: "No moments since recording began to judge"
        case .pass(let share): "Pass (\(Self.percent(share)) near)"
        case .borderline(let share): "Borderline (\(Self.percent(share)) near): try background recording"
        case .fail(let share): "Fail (\(Self.percent(share)) near): music becomes era-level only"
        }
    }

    private static func cell(_ counts: MatchCounts?) -> String {
        let counts = counts ?? MatchCounts()
        return "\(counts.near) / \(counts.looseOnly) / \(counts.none)"
    }

    private static func row(_ label: String, _ first: String, _ second: String, _ third: String) -> String {
        label.padding(toLength: 11, withPad: " ", startingAt: 0)
            + first.padding(toLength: 18, withPad: " ", startingAt: 0)
            + second.padding(toLength: 18, withPad: " ", startingAt: 0)
            + third
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
        let (eras, playlists) = savedEras(in: container.mainContext, now: now)
        return ListeningCoverage(
            moments: moments,
            songs: songs,
            recordedPlays: recorded,
            recordingSince: history.since,
            libraryReads: history.reads,
            hasPhotoAccess: photos != nil,
            eras: eras,
            playlists: playlists,
            now: now,
            calendar: calendar
        )
    }

    /// The eras the last sync saved, and how each one's playlist splits.
    /// Sample data (no `eraID`) is left out.
    @MainActor
    private static func savedEras(
        in context: ModelContext,
        now: Date
    ) -> (eras: [LibraryAdditions.EraWindow], playlists: [String: LibraryAdditionsReport.PlaylistSplit]) {
        let saved = (try? context.fetch(FetchDescriptor<Era>(predicate: #Predicate { $0.eraID != nil }))) ?? []
        var eras: [LibraryAdditions.EraWindow] = []
        var playlists: [String: LibraryAdditionsReport.PlaylistSplit] = [:]
        for era in saved {
            guard let id = era.eraID else { continue }
            eras.append(LibraryAdditions.EraWindow(
                id: id,
                title: era.title,
                start: era.startDate,
                end: era.endDate ?? now,
                isTrip: era.kind == .trip
            ))
            playlists[id] = LibraryAdditionsReport.PlaylistSplit(era)
        }
        return (eras, playlists)
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
