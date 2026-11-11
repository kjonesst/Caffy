import Foundation
import Testing
@testable import Caffy

/// The plan's scenario table, run end to end through `EraPipeline`: photos
/// and plays in, finished eras with words and colours out.
struct ScenarioTableTests {
    private static let day: TimeInterval = 24 * 60 * 60

    private static func length(_ era: BuiltEra, in scenario: Scenario) -> TimeInterval {
        let byID = Dictionary(uniqueKeysWithValues: scenario.moments.map { ($0.id, $0) })
        return byID[era.draft.momentIDs.last!]!.end.timeIntervalSince(byID[era.draft.momentIDs.first!]!.start)
    }

    // MARK: - Trips

    @Test func weekendTrip() async {
        // 2 February 2026 is a Monday, so the trip leaves on a Friday.
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 25)
            .listen(to: "Fred again..", genre: "Electronic")
            .trip(to: .melbourne, nights: 2)
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 21)
        let result = await PipelineHarness.run(scenario)

        #expect(result.kinds == [.home, .trip])
        #expect(result.titles[1] == "A weekend in Melbourne")
        // The trip's moments carry the trip's music.
        let tripSongs = result.eras[1].draft.momentIDs.flatMap { result.songs[$0] ?? [] }
        #expect(!tripSongs.isEmpty)
        #expect(tripSongs.allSatisfy { $0.artist == "Fred again.." })
        // The season and the trip are printed in different colours.
        #expect(result.eras[0].palette != result.eras[1].palette)
    }

    @Test func singleOvernight() async {
        let scenario = Scenario()
            .live(at: .sydney, days: 22)
            .trip(to: .hobart, nights: 1)
            .live(at: .sydney, days: 21)
        let result = await PipelineHarness.run(scenario)
        #expect(result.kinds == [.home, .trip])
        #expect(result.titles[1] == "A night in Hobart")
    }

    @Test func dayTrip() async {
        let scenario = Scenario()
            .live(at: .sydney, days: 21)
            .dayTrip(to: .wollongong)
            .live(at: .sydney, days: 21)
        let result = await PipelineHarness.run(scenario)
        #expect(result.kinds == [.home])
        #expect(result.eras[0].draft.momentIDs.count == scenario.moments.count)
    }

    @Test func multiCityTrip() async {
        let scenario = Scenario()
            .live(at: .sydney, days: 21)
            .trip(to: .melbourne, nights: 2)
            .trip(to: .hobart, nights: 2)
            .live(at: .sydney, days: 21)
        let result = await PipelineHarness.run(scenario)
        #expect(result.kinds == [.home, .trip])
        #expect(result.titles[1] == "Melbourne & Hobart")
    }

    // MARK: - Life at home

    @Test func semesterAtHome() async {
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .alsoListen(to: "Pond", genre: "Psychedelic")
            .live(at: .sydney, days: 112)
        let result = await PipelineHarness.run(scenario)
        #expect(result.kinds == [.home])
        #expect(result.eras[0].draft.isCurrent)
    }

    @Test func semesterWithAMusicShift() async throws {
        let before = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 63)
        let scenario = before
            .listen(to: "Fred again..", genre: "Electronic")
            .live(at: .sydney, days: 56)
        let result = await PipelineHarness.run(scenario)

        #expect(result.titles == ["On repeat: Tame Impala", "On repeat: Fred again.."])
        #expect(result.eras[1].content.summary == "Electronic takes over from Psychedelic.")
        #expect(abs(result.eras[1].draft.start.timeIntervalSince(before.cursor)) <= 7 * Self.day)
    }

    @Test func exchangeSemesterAway() async {
        let scenario = Scenario()
            .live(at: .sydney, days: 60)
            .live(at: .melbourne, days: 50)
            .trip(to: .sydney, nights: 2)
            .live(at: .melbourne, days: 50)
            .live(at: .sydney, days: 60)
        let result = await PipelineHarness.run(scenario)

        #expect(result.kinds == [.home, .home, .trip, .home])
        #expect(result.titles[1] == "New in Melbourne")
        #expect(result.titles[2].hasSuffix("in Sydney"))
        #expect(result.titles[3] == "Back in Sydney")
    }

    @Test func gapOfSeveralMonths() async {
        let scenario = Scenario()
            .live(at: .sydney, days: 40)
            .gap(days: 120)
            .live(at: .sydney, days: 40)
        let result = await PipelineHarness.run(scenario)
        #expect(result.eras.map(\.draft.startReason) == [.firstMoment, .longGap])
        #expect(result.eras.map(\.isFrozen) == [true, false])
    }

    @Test func veryLongStretch() async {
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 540)
        let result = await PipelineHarness.run(scenario)
        #expect(result.eras.count >= 5)
        for era in result.eras.dropLast() {
            let length = Self.length(era, in: scenario)
            #expect(length >= 30 * Self.day && length <= 120 * Self.day)
        }
    }

    // MARK: - Missing data

    @Test func noLocation() async {
        let scenario = Scenario()
            .unlocated()
            .live(at: .sydney, days: 40)
            .trip(to: .melbourne, nights: 2)
            .live(at: .sydney, days: 40)
        let result = await PipelineHarness.run(scenario)
        let cities = ["Sydney", "Melbourne", "Hobart", "Wollongong"]

        #expect(result.kinds == [.home])
        #expect(result.titles.allSatisfy { title in !cities.contains { title.contains($0) } })
        // No readable photo colours, so a designed preset.
        #expect(EraPalette.presets.contains(result.eras[0].palette))
    }

    @Test func noListening() async {
        let scenario = Scenario()
            .live(at: .sydney, days: 60)
            .trip(to: .hobart, nights: 3)
            .live(at: .sydney, days: 20)
        let result = await PipelineHarness.run(scenario)
        #expect(result.eras.map(\.content.summary) == ["A quiet one for music.", "No music on this one."])
        #expect(result.songs.values.allSatisfy { $0.isEmpty })
    }

    @Test func singlePhotoBetweenGaps() async throws {
        // Three days with a photo every other day give a single moment.
        let scenario = Scenario()
            .live(at: .sydney, days: 40)
            .gap(days: 40)
            .live(at: .sydney, days: 3)
            .gap(days: 40)
            .live(at: .sydney, days: 40)
        let result = await PipelineHarness.run(scenario)
        #expect(result.eras.count == 3)
        let single = result.eras[1]
        #expect(single.draft.momentIDs.count == 1)
        #expect(single.content.title.hasPrefix("One day in "))
    }

    // MARK: - Always the same

    @Test func shuffledInputGivesTheSameEras() async {
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 50)
            .trip(to: .hobart, nights: 3)
            .listen(to: "Fred again..", genre: "Electronic")
            .live(at: .sydney, days: 90)
            .gap(days: 30)
            .live(at: .melbourne, days: 40)
        let pipeline = EraPipeline(namer: FixturePlaceNamer(), sampler: PipelineHarness.sampler(for: scenario.moments))
        let forward = await pipeline.run(moments: scenario.moments, plays: scenario.plays, now: scenario.now, calendar: scenario.calendar)

        var random = SplitMix64(seed: 3)
        var moments = scenario.moments
        var plays = scenario.plays
        for index in moments.indices.reversed() { moments.swapAt(index, random.int(in: 0...index)) }
        for index in plays.indices.reversed() { plays.swapAt(index, random.int(in: 0...index)) }
        let shuffled = await pipeline.run(moments: moments, plays: plays, now: scenario.now, calendar: scenario.calendar)

        #expect(shuffled == forward)
    }

    @Test func tenYearsRunsInAReasonableTime() async {
        var scenario = Scenario().listen(to: "Tame Impala", genre: "Psychedelic")
        for round in 0..<40 {
            scenario = scenario
                .live(at: .sydney, days: 80, photosPerWeek: 7)
                .trip(to: round.isMultiple(of: 2) ? .melbourne : .hobart, nights: 3)
        }
        let start = ContinuousClock.now
        let result = await PipelineHarness.run(scenario)
        let elapsed = ContinuousClock.now - start

        #expect(result.kinds.filter { $0 == .trip }.count == 40)
        // Generous, because tests run as an unoptimised Debug build.
        #expect(elapsed < .seconds(2))
    }
}
