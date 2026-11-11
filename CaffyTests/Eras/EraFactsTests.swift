import Foundation
import Testing
@testable import Caffy

/// Tests for `EraFacts`, and for the titles the template narrator writes
/// from them for whole scenarios.
struct EraFactsTests {
    // MARK: - Fixtures

    private struct Built {
        let home: HomeTimeline
        let drafts: [EraDraft]
        let facts: [EraFacts]
        let content: [EraContent]

        var titles: [String] { content.map(\.title) }
    }

    /// Runs the pipeline so far: home, segment, names, facts, templates.
    private static func build(_ scenario: Scenario, namer: some PlaceNamer = SamplePlaceNamer()) async -> Built {
        let home = HomeInference.infer(scenario.moments, calendar: scenario.calendar)
        let drafts = EraSegmenter.segment(scenario.moments, plays: scenario.plays, home: home, now: scenario.now, calendar: scenario.calendar)
        let names = await EraFacts.placeNames(for: drafts, moments: scenario.moments, home: home, namer: namer)
        let facts = EraFacts.make(
            for: drafts, moments: scenario.moments, plays: scenario.plays,
            home: home, names: names, now: scenario.now, calendar: scenario.calendar
        )
        let narrator = TemplateNarrator(calendar: scenario.calendar, now: scenario.now)
        return Built(home: home, drafts: drafts, facts: facts, content: facts.map(narrator.content(for:)))
    }

    /// Home in Sydney with Tame Impala, and a Friday-to-Sunday trip to
    /// Melbourne with Fred again.. (2 February 2026 is a Monday).
    private static let weekendAway = Scenario()
        .listen(to: "Tame Impala", genre: "Psychedelic")
        .live(at: .sydney, days: 25)
        .listen(to: "Fred again..", genre: "Electronic")
        .trip(to: .melbourne, nights: 2)
        .listen(to: "Tame Impala", genre: "Psychedelic")
        .live(at: .sydney, days: 21)

    // MARK: - Weekend away

    @Test func weekendAwayReadsRight() async throws {
        let built = await Self.build(Self.weekendAway)
        #expect(built.drafts.map(\.kind) == [.home, .trip])

        #expect(built.content[1] == EraContent(
            title: "A weekend in Melbourne",
            summary: "The soundtrack: Fred again...",
            whenLabel: "Feb 2026"
        ))
        #expect(built.content[0] == EraContent(
            title: "On repeat: Tame Impala",
            summary: "Hardly anything but Tame Impala.",
            whenLabel: "2026"
        ))
    }

    @Test func tripMusicBelongsToTheTripNotTheSeason() async {
        let built = await Self.build(Self.weekendAway)
        let season = built.facts[0]
        let trip = built.facts[1]
        let fredPlays = Self.weekendAway.plays.filter { $0.song.artist == "Fred again.." }.count

        #expect(trip.listening.artistPlays == ["Fred again..": fredPlays])
        #expect(season.listening.artistPlays.keys.sorted() == ["Tame Impala"])
        // Every play from the first photo on is the season's or the trip's,
        // never both. Plays before the first photo belong to no era.
        let fromFirstPhoto = Self.weekendAway.plays.filter { $0.interval.start >= season.start }.count
        #expect(season.listening.playCount + trip.listening.playCount == fromFirstPhoto)
    }

    @Test func factsNameThePlaces() async {
        let built = await Self.build(Self.weekendAway)
        #expect(built.facts.map(\.placeNames) == [["Sydney"], ["Melbourne"]])
        #expect(built.facts.allSatisfy { ($0.latitude ?? 0) < 0 })
        #expect(built.facts.map(\.previousListening) == [nil, nil])
    }

    // MARK: - Moving

    @Test func movingAwayAndBack() async {
        let scenario = Scenario()
            .live(at: .sydney, days: 60)
            .live(at: .melbourne, days: 50)
            .trip(to: .sydney, nights: 2)
            .live(at: .melbourne, days: 50)
            .live(at: .sydney, days: 60)
        let built = await Self.build(scenario)

        #expect(built.facts.map(\.homeChange) == [nil, .newHome, nil, .backHome])
        #expect(built.titles[1] == "New in Melbourne")
        #expect(built.titles[2].hasSuffix("in Sydney"))
        #expect(built.titles[3] == "Back in Sydney")
        #expect(built.content.map(\.summary) == [
            "A quiet one for music.", "A quiet one for music.", "No music on this one.", "A quiet one for music."
        ])
    }

    // MARK: - Music

    @Test func changeInMusicIsDescribed() async throws {
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 63)
            .listen(to: "Fred again..", genre: "Electronic")
            .live(at: .sydney, days: 56)
        let built = await Self.build(scenario)

        #expect(built.facts.count == 2)
        #expect(built.facts[1].previousListening == built.facts[0].listening)
        #expect(built.titles == ["On repeat: Tame Impala", "On repeat: Fred again.."])
        #expect(built.content[1].summary == "Electronic takes over from Psychedelic.")
    }

    // MARK: - Missing data

    @Test func withoutPlaceNamesTitlesLeavePlacesOut() async {
        let built = await Self.build(Self.weekendAway, namer: OfflinePlaceNamer())
        #expect(built.facts.allSatisfy { $0.placeNames.isEmpty })
        #expect(built.titles[1] == "A weekend away")
        #expect(built.titles.allSatisfy { !$0.contains("Sydney") && !$0.contains("Melbourne") })
    }

    @Test func libraryWithoutLocationsHasNoPlaces() async throws {
        let scenario = Scenario().unlocated().live(at: .sydney, days: 60)
        let built = await Self.build(scenario)
        let facts = try #require(built.facts.first)
        #expect(facts.placeNames.isEmpty)
        #expect(facts.latitude == nil)
        #expect(!built.titles[0].isEmpty)
    }

    // MARK: - Looking up names

    /// Records every coordinate it's asked about, in order.
    private actor Lookups {
        var asked: [Coordinate] = []
        func record(_ coordinate: Coordinate) { asked.append(coordinate) }
    }

    private struct RecordingNamer: PlaceNamer {
        let lookups: Lookups
        func name(for coordinate: Coordinate) async -> PlaceName? {
            await lookups.record(coordinate)
            return await SamplePlaceNamer().name(for: coordinate)
        }
    }

    @Test func eachPlaceIsLookedUpOnceInOrder() async {
        let scenario = Self.weekendAway
            .trip(to: .hobart, nights: 2)
            .live(at: .sydney, days: 14)
            .trip(to: .melbourne, nights: 1)
            .live(at: .sydney, days: 14)
        let home = HomeInference.infer(scenario.moments, calendar: scenario.calendar)
        let drafts = EraSegmenter.segment(scenario.moments, plays: scenario.plays, home: home, now: scenario.now, calendar: scenario.calendar)
        let lookups = Lookups()

        let names = await EraFacts.placeNames(for: drafts, moments: scenario.moments, home: home, namer: RecordingNamer(lookups: lookups))
        let ids = EraFacts.clustersToName(for: drafts, moments: scenario.moments, home: home)

        #expect(ids == ids.sorted())
        #expect(Set(names.keys) == Set(ids))
        #expect(await lookups.asked == ids.map { home.clusters[$0].centre })
        #expect(Set(names.values.map(\.locality)) == ["Sydney", "Melbourne", "Hobart"])
    }

    @Test func sameInputSameWords() async {
        let first = await Self.build(Self.weekendAway)
        let second = await Self.build(Self.weekendAway)
        #expect(first.content == second.content)
    }
}
