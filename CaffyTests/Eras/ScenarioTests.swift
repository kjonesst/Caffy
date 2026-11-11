import Foundation
import Testing
@testable import Caffy

/// Tests for the `Scenario` fixture builder itself, so the era tests built on
/// it can trust what it produces.
struct ScenarioTests {
    private static func days(_ scenario: Scenario, from start: Date) -> Int {
        scenario.calendar.dateComponents([.day], from: start, to: scenario.cursor).day!
    }

    private static func distance(_ coordinate: Coordinate?, to place: FixturePlace) -> Double? {
        coordinate.map { $0.distance(to: place.coordinate) }
    }

    // MARK: - Determinism

    @Test func sameStepsAndSeedGiveTheSameResult() {
        func build() -> Scenario {
            Scenario(seed: 42)
                .listen(to: "Tame Impala", genre: "Psychedelic")
                .live(at: .sydney, days: 30)
                .trip(to: .melbourne, nights: 2)
        }
        let first = build()
        let second = build()
        #expect(first.moments == second.moments)
        #expect(first.plays == second.plays)
    }

    @Test func differentSeedsGiveDifferentTimes() {
        let a = Scenario(seed: 1).live(at: .sydney, days: 14)
        let b = Scenario(seed: 2).live(at: .sydney, days: 14)
        #expect(a.moments.map(\.start) != b.moments.map(\.start))
    }

    // MARK: - Living at home

    @Test func photosPerWeekIsRespected() {
        let scenario = Scenario().live(at: .sydney, days: 28, photosPerWeek: 3)
        #expect(scenario.moments.count == 12)

        let busy = Scenario().live(at: .sydney, days: 7, photosPerWeek: 14)
        #expect(busy.moments.count == 14)
    }

    @Test func momentsAreInTimeOrderWithUniqueIDs() {
        let scenario = Scenario().live(at: .sydney, days: 60, photosPerWeek: 10)
        let starts = scenario.moments.map(\.start)
        #expect(starts == starts.sorted())
        #expect(Set(scenario.moments.map(\.id)).count == scenario.moments.count)
        for (previous, next) in zip(scenario.moments, scenario.moments.dropFirst()) {
            #expect(previous.end < next.start)
        }
    }

    @Test func homePhotosStayNearHome() throws {
        let scenario = Scenario().live(at: .sydney, days: 30)
        for moment in scenario.moments {
            let distance = try #require(Self.distance(moment.coordinate, to: .sydney))
            #expect(distance < 5_000)
        }
    }

    @Test func momentsAreWellFormed() {
        let scenario = Scenario().live(at: .sydney, days: 30, photosPerWeek: 7)
        for moment in scenario.moments {
            #expect(!moment.photoIDs.isEmpty)
            #expect(moment.photoIDs.contains(moment.coverID))
            #expect(moment.start <= moment.end)
            #expect(scenario.day(of: moment.start) == scenario.day(of: moment.end))
        }
    }

    // MARK: - Trips

    @Test func overnightTripCrossesFourAMAtTheDestination() throws {
        let home = Scenario().live(at: .sydney, days: 7)
        let scenario = home.trip(to: .melbourne, nights: 2, photosPerDay: 2)
        let tripMoments = scenario.moments.dropFirst(home.moments.count)

        #expect(tripMoments.count == 6)
        #expect(Self.days(scenario, from: home.cursor) == 3)
        for moment in tripMoments {
            let distance = try #require(Self.distance(moment.coordinate, to: .melbourne))
            #expect(distance < 5_000)
        }
        let first = try #require(tripMoments.first)
        let last = try #require(tripMoments.last)
        #expect(scenario.calendar.component(.hour, from: first.start) >= 13)
        #expect(scenario.calendar.component(.hour, from: last.end) <= 12)
    }

    @Test func dayTripStaysWithinOneDay() {
        let scenario = Scenario().dayTrip(to: .wollongong, photos: 3)
        #expect(scenario.moments.count == 3)
        #expect(Set(scenario.moments.map { scenario.day(of: $0.start) }).count == 1)
        for moment in scenario.moments {
            let hour = scenario.calendar.component(.hour, from: moment.start)
            #expect((10...17).contains(hour))
        }
    }

    @Test func wollongongIsAwayButSydneyNeighbourhoodsAreNot() {
        let radius = EraBuildConfig.standard.placeClusterRadius
        #expect(FixturePlace.wollongong.coordinate.distance(to: FixturePlace.sydney.coordinate) > radius)
        #expect(FixturePlace.spread * 2 < radius)
    }

    // MARK: - Gaps and missing data

    @Test func gapHasNoPhotosButKeepsListening() {
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic", perDay: 5)
            .gap(days: 10)
        #expect(scenario.moments.isEmpty)
        #expect(scenario.plays.count == 50)
        #expect(Self.days(scenario, from: scenario.start) == 10)
    }

    @Test func silenceStopsListening() {
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic", perDay: 5)
            .live(at: .sydney, days: 2)
            .silence()
            .live(at: .sydney, days: 5)
        #expect(scenario.plays.count == 10)
    }

    @Test func unlocatedPhotosHaveNoCoordinate() {
        let scenario = Scenario()
            .unlocated()
            .live(at: .sydney, days: 7)
            .located()
            .live(at: .sydney, days: 7)
        let half = scenario.moments.count / 2
        #expect(scenario.moments.prefix(half).allSatisfy { $0.coordinate == nil })
        #expect(scenario.moments.suffix(half).allSatisfy { $0.coordinate != nil })
    }

    // MARK: - Listening

    @Test func playsAreOrderedAndUseTheHabitsSongs() {
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic", perDay: 6)
            .alsoListen(to: "Fred again..", genre: "Electronic", perDay: 3)
            .live(at: .sydney, days: 4)

        #expect(scenario.plays.count == 36)
        let starts = scenario.plays.map(\.interval.start)
        #expect(starts == starts.sorted())

        let artists = Dictionary(grouping: scenario.plays, by: \.song.artist).mapValues(\.count)
        #expect(artists == ["Tame Impala": 24, "Fred again..": 12])

        let tameIDs = Set((1...3).map { Scenario.songID(artist: "Tame Impala", track: $0) })
        let ids = Set(scenario.plays.filter { $0.song.artist == "Tame Impala" }.map(\.song.id))
        #expect(ids.isSubset(of: tameIDs))
        #expect(scenario.plays.allSatisfy { !$0.isEstimated && $0.interval.duration >= 180 })
    }

    @Test func listenReplacesTheEarlierHabit() {
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic", perDay: 4)
            .live(at: .sydney, days: 3)
            .listen(to: "Fred again..", genre: "Electronic", perDay: 4)
            .live(at: .sydney, days: 3)
        let artists = scenario.plays.map(\.song.artist)
        #expect(artists.prefix(12).allSatisfy { $0 == "Tame Impala" })
        #expect(artists.suffix(12).allSatisfy { $0 == "Fred again.." })
    }

    @Test func songIDsAreSlugged() {
        #expect(Scenario.songID(artist: "Fred again..", track: 2) == "fx-fred-again---2")
        #expect(Scenario.songID(artist: "Tame Impala", track: 1) == "fx-tame-impala-1")
    }

    // MARK: - Calendar

    @Test func daysStayWholeAcrossDaylightSaving() {
        // Sydney's clocks go back on Sunday 5 April 2026.
        let scenario = Scenario(year: 2026, month: 4, day: 1).live(at: .sydney, days: 10)
        #expect(Self.days(scenario, from: scenario.start) == 10)
        #expect(scenario.calendar.component(.hour, from: scenario.cursor) == 0)
    }

    @Test func fixtureSourceReturnsOverlappingPlaysInOrder() async throws {
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic", perDay: 4)
            .live(at: .sydney, days: 3)
        let secondDay = DateInterval(
            start: scenario.calendar.date(byAdding: .day, value: 1, to: scenario.start)!,
            duration: 24 * 60 * 60
        )
        let plays = try await scenario.listeningSource.plays(in: secondDay)
        #expect(plays.count == 4)
        #expect(plays.allSatisfy { $0.interval.intersects(secondDay) })
        #expect(plays.map(\.interval.start) == plays.map(\.interval.start).sorted())
    }
}
