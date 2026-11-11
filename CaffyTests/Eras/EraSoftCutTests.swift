import Foundation
import Testing
@testable import Caffy

/// Tests for `EraSegmenter`'s soft cuts, which keep home eras season-sized
/// and start a new era when the music changes.
struct EraSoftCutTests {
    // MARK: - Fixtures

    private static let day: TimeInterval = 24 * 60 * 60

    private static func eras(_ scenario: Scenario, now: Date? = nil, config: EraBuildConfig = .standard) -> [EraDraft] {
        let home = HomeInference.infer(scenario.moments, calendar: scenario.calendar, config: config)
        return EraSegmenter.segment(
            scenario.moments,
            plays: scenario.plays,
            home: home,
            now: now ?? scenario.now,
            calendar: scenario.calendar,
            config: config
        )
    }

    /// How long a home era is, from its first photo to its last.
    private static func length(_ draft: EraDraft, in scenario: Scenario) -> TimeInterval {
        let byID = Dictionary(uniqueKeysWithValues: scenario.moments.map { ($0.id, $0) })
        return byID[draft.momentIDs.last!]!.end.timeIntervalSince(byID[draft.momentIDs.first!]!.start)
    }

    private static func homeEras(_ drafts: [EraDraft]) -> [EraDraft] {
        drafts.filter { $0.kind == .home }
    }

    // MARK: - Season length

    @Test func semesterAtHomeIsOneSeason() {
        // 16 weeks with the same music: under `maxEraLength`, no reason to cut.
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 112)
        let drafts = Self.eras(scenario)
        #expect(drafts.count == 1)
        #expect(drafts.first?.isCurrent == true)
    }

    @Test func fiveMonthsAtHomeIsTwoSeasons() {
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 150)
        let drafts = Self.eras(scenario)
        #expect(drafts.map(\.startReason) == [.firstMoment, .maxLength])
        for draft in drafts {
            let length = Self.length(draft, in: scenario)
            #expect(length >= 30 * Self.day && length <= 120 * Self.day)
        }
    }

    @Test(arguments: [3, 7])
    func eighteenMonthsAreSeasonSized(photosPerWeek: Int) {
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 540, photosPerWeek: photosPerWeek)
        let drafts = Self.eras(scenario)

        #expect(drafts.count >= 5)
        #expect(drafts.dropFirst().allSatisfy { $0.startReason == .maxLength })
        // Every era but the still-growing current one is near a season.
        for draft in drafts.dropLast() {
            let length = Self.length(draft, in: scenario)
            #expect(length >= 30 * Self.day && length <= 120 * Self.day)
            #expect(abs(length - 75 * Self.day) <= 20 * Self.day)
        }
        #expect(Self.length(drafts.last!, in: scenario) <= 120 * Self.day)
    }

    @Test func longStretchWithoutListeningIsStillCut() {
        let scenario = Scenario().live(at: .sydney, days: 300)
        let drafts = Self.eras(scenario)
        #expect(drafts.count >= 3)
        #expect(drafts.allSatisfy { Self.length($0, in: scenario) <= 120 * Self.day })
    }

    // MARK: - Music

    @Test func changeInMusicStartsANewEra() throws {
        let before = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 63)
        let scenario = before
            .listen(to: "Fred again..", genre: "Electronic")
            .live(at: .sydney, days: 56)
        let drafts = Self.eras(scenario)

        #expect(drafts.map(\.startReason) == [.firstMoment, .musicChange])
        let second = try #require(drafts.last)
        // Within a week of the switch.
        #expect(abs(second.start.timeIntervalSince(before.cursor)) <= 7 * Self.day)
        #expect(second.isCurrent)
    }

    @Test func recentChangeInMusicWaitsForAMonth() {
        // Only two weeks of the new music: too early to call it an era.
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 63)
            .listen(to: "Fred again..", genre: "Electronic")
            .live(at: .sydney, days: 14)
        #expect(Self.eras(scenario).count == 1)

        let laterOn = scenario.live(at: .sydney, days: 21)
        #expect(Self.eras(laterOn).map(\.startReason) == [.firstMoment, .musicChange])
    }

    @Test func shiftingMixWithoutASwitchIsNoChange() {
        // Both artists all along, just a bit more of one later on.
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic", perDay: 6)
            .alsoListen(to: "Fred again..", genre: "Electronic", perDay: 3)
            .live(at: .sydney, days: 55)
            .listen(to: "Tame Impala", genre: "Psychedelic", perDay: 4)
            .alsoListen(to: "Fred again..", genre: "Electronic", perDay: 5)
            .live(at: .sydney, days: 55)
        #expect(Self.eras(scenario).count == 1)
    }

    @Test func tooLittleListeningIsNoChange() {
        var config = EraBuildConfig()
        config.musicMinPlays = 1_000
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 63)
            .listen(to: "Fred again..", genre: "Electronic")
            .live(at: .sydney, days: 56)
        #expect(Self.eras(scenario, config: config).count == 1)
    }

    @Test func tripMusicDoesntSplitTheSeason() {
        // Something completely different on the trip, the same at home.
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 50)
            .listen(to: "Fred again..", genre: "Electronic", perDay: 20)
            .trip(to: .melbourne, nights: 4)
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 50)
        #expect(Self.eras(scenario).map(\.kind) == [.home, .trip])
    }

    @Test func musicChangeNeedsAMonthOnBothSides() {
        // A switch only 20 days in can't be cut: the first era would be too short.
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 20)
            .listen(to: "Fred again..", genre: "Electronic")
            .live(at: .sydney, days: 80)
        #expect(Self.eras(scenario).count == 1)
    }

    // MARK: - Together with hard cuts

    @Test func longSemesterAwayIsCutLikeAnyHome() {
        let scenario = Scenario()
            .live(at: .sydney, days: 60)
            .live(at: .melbourne, days: 150)
            .live(at: .sydney, days: 60)
        let drafts = Self.eras(scenario)
        #expect(drafts.map(\.startReason) == [.firstMoment, .homeChange, .maxLength, .homeChange])
    }

    @Test func gapsAndMusicCutsCombine() {
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 63)
            .listen(to: "Fred again..", genre: "Electronic")
            .live(at: .sydney, days: 56)
            .gap(days: 90)
            .live(at: .sydney, days: 40)
        #expect(Self.eras(scenario).map(\.startReason) == [.firstMoment, .musicChange, .longGap])
    }

    // MARK: - Determinism and speed

    @Test func inputOrderDoesntMatter() {
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 90)
            .trip(to: .hobart, nights: 3)
            .listen(to: "Fred again..", genre: "Electronic")
            .live(at: .sydney, days: 200)
        let home = HomeInference.infer(scenario.moments, calendar: scenario.calendar)
        func run(_ moments: [PhotoMoment], _ plays: [ListeningEvent]) -> [EraDraft] {
            EraSegmenter.segment(moments, plays: plays, home: home, now: scenario.now, calendar: scenario.calendar)
        }
        #expect(run(scenario.moments, scenario.plays) == run(scenario.moments.reversed(), scenario.plays.reversed()))
    }

    @Test func tenYearsWithListeningIsQuick() {
        var scenario = Scenario().listen(to: "Tame Impala", genre: "Psychedelic")
        for round in 0..<40 {
            scenario = scenario
                .live(at: .sydney, days: 80, photosPerWeek: 7)
                .trip(to: round.isMultiple(of: 2) ? .melbourne : .hobart, nights: 3)
        }
        let home = HomeInference.infer(scenario.moments, calendar: scenario.calendar)
        var drafts: [EraDraft] = []
        let elapsed = ContinuousClock().measure {
            drafts = EraSegmenter.segment(scenario.moments, plays: scenario.plays, home: home, now: scenario.now, calendar: scenario.calendar)
        }
        #expect(drafts.filter { $0.kind == .home }.count >= 40)
        // Generous, because tests run as an unoptimised Debug build.
        #expect(elapsed < .milliseconds(500))
    }
}
