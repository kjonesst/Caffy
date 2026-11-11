import Foundation
import Testing
@testable import Caffy

/// Tests for `HomeInference`, which works out where home is from photo
/// locations alone.
struct HomeInferenceTests {
    // MARK: - Fixtures

    private static func timeline(_ scenario: Scenario, config: EraBuildConfig = .standard) -> HomeTimeline {
        HomeInference.infer(scenario.moments, calendar: scenario.calendar, config: config)
    }

    /// The fixture city a cluster sits in, for readable expectations.
    private static func name(_ cluster: PlaceCluster?) -> String? {
        guard let cluster else { return nil }
        let places: [FixturePlace] = [.sydney, .melbourne, .hobart, .wollongong]
        return places.first { $0.coordinate.distance(to: cluster.centre) < 10_000 }?.name
    }

    /// Noon on the scenario's `day`th day (0 is its first day).
    private static func noon(_ scenario: Scenario, day: Int) -> Date {
        let date = scenario.calendar.date(byAdding: .day, value: day, to: scenario.start)!
        return scenario.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
    }

    /// Noon on the day after `scenario`'s last filled-in day, plus `days`.
    private static func noon(after scenario: Scenario, plus days: Int = 0) -> Date {
        let date = scenario.calendar.date(byAdding: .day, value: days, to: scenario.cursor)!
        return scenario.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
    }

    private static func residenceNames(_ timeline: HomeTimeline) -> [String?] {
        timeline.residences.map { name(timeline.clusters[$0.clusterID]) }
    }

    // MARK: - No data

    @Test func noPhotosMeansNoHome() {
        let timeline = Self.timeline(Scenario())
        #expect(timeline.clusters.isEmpty)
        #expect(timeline.home(on: .now) == nil)
        #expect(timeline.isHome(FixturePlace.hobart.coordinate, on: .now))
    }

    @Test func unlocatedPhotosMeanNoHome() {
        let timeline = Self.timeline(Scenario().unlocated().live(at: .sydney, days: 60))
        #expect(timeline.days.isEmpty)
        #expect(timeline.home(on: .now) == nil)
    }

    // MARK: - Settled at home

    @Test func steadyLifeAtHomeIsOneResidence() throws {
        let scenario = Scenario().live(at: .sydney, days: 90)
        let timeline = Self.timeline(scenario)

        #expect(timeline.clusters.count == 1)
        let residence = try #require(timeline.residences.first)
        #expect(timeline.residences.count == 1)
        #expect(residence.share == 1)
        // Before, during and long after the photos.
        for date in [Self.noon(scenario, day: -10), Self.noon(scenario, day: 45), Self.noon(after: scenario, plus: 200)] {
            #expect(Self.name(timeline.home(on: date)) == "Sydney")
        }
    }

    @Test func neighbourhoodsAcrossTheCityAreOnePlace() {
        let timeline = Self.timeline(Scenario().live(at: .sydney, days: 60, photosPerWeek: 14))
        #expect(timeline.clusters.count == 1)
    }

    // MARK: - Trips

    @Test func frequentWeekendsAwayDontMoveHome() {
        var scenario = Scenario()
        for _ in 0..<5 {
            scenario = scenario.live(at: .sydney, days: 12).trip(to: .melbourne, nights: 2)
        }
        scenario = scenario.live(at: .sydney, days: 12)
        let timeline = Self.timeline(scenario)

        #expect(Self.residenceNames(timeline) == ["Sydney"])
        for moment in scenario.moments {
            let coordinate = moment.coordinate!
            let inSydney = coordinate.distance(to: FixturePlace.sydney.coordinate) < 10_000
            #expect(Self.name(timeline.home(on: moment.start)) == "Sydney")
            #expect(timeline.isHome(coordinate, on: moment.start) == inSydney)
        }
    }

    @Test func dayTripIsAwayButNeverHome() {
        let before = Scenario().live(at: .sydney, days: 30)
        let scenario = before.dayTrip(to: .wollongong).live(at: .sydney, days: 30)
        let timeline = Self.timeline(scenario)
        let tripDay = Self.noon(after: before)

        #expect(Self.residenceNames(timeline) == ["Sydney"])
        #expect(Self.name(timeline.home(on: tripDay)) == "Sydney")
        #expect(!timeline.isHome(FixturePlace.wollongong.coordinate, on: tripDay))
    }

    // MARK: - Moving

    @Test func exchangeSemesterBecomesHome() {
        let before = Scenario().live(at: .sydney, days: 60)
        let firstHalf = before.live(at: .melbourne, days: 60)
        let weekendBack = firstHalf.trip(to: .sydney, nights: 2)
        let semester = weekendBack.live(at: .melbourne, days: 60)
        let scenario = semester.live(at: .sydney, days: 60)
        let timeline = Self.timeline(scenario)

        #expect(Self.residenceNames(timeline) == ["Sydney", "Melbourne", "Sydney"])
        #expect(Self.name(timeline.home(on: Self.noon(scenario, day: 30))) == "Sydney")
        #expect(Self.name(timeline.home(on: Self.noon(after: before, plus: 30))) == "Melbourne")
        #expect(Self.name(timeline.home(on: Self.noon(after: semester, plus: 30))) == "Sydney")

        // Going back to Sydney for a weekend mid-semester is a trip.
        let weekend = Self.noon(after: firstHalf, plus: 1)
        #expect(Self.name(timeline.home(on: weekend)) == "Melbourne")
        #expect(!timeline.isHome(FixturePlace.sydney.coordinate, on: weekend))
        #expect(timeline.isHome(FixturePlace.melbourne.coordinate, on: weekend))
    }

    @Test func shortStayElsewhereIsNotHome() {
        let before = Scenario().live(at: .sydney, days: 60)
        let scenario = before.live(at: .melbourne, days: 20, photosPerWeek: 7)
        let timeline = Self.timeline(scenario)
        let stay = Self.noon(after: before, plus: 10)

        #expect(Self.residenceNames(timeline) == ["Sydney"])
        #expect(Self.name(timeline.home(on: stay)) == "Sydney")
        #expect(!timeline.isHome(FixturePlace.melbourne.coordinate, on: stay))
    }

    @Test(arguments: [(27, ["Sydney"]), (28, ["Sydney", "Melbourne", "Sydney"])])
    func homeNeedsFourWeeks(days: Int, expected: [String]) {
        let scenario = Scenario()
            .live(at: .sydney, days: 40, photosPerWeek: 7)
            .live(at: .melbourne, days: days, photosPerWeek: 7)
            .live(at: .sydney, days: 40, photosPerWeek: 7)
        #expect(Self.residenceNames(Self.timeline(scenario)) == expected)
    }

    @Test func adoptionDaysCanBeTuned() {
        var config = EraBuildConfig()
        config.homeAdoptionDays = 14
        let scenario = Scenario()
            .live(at: .sydney, days: 60)
            .live(at: .melbourne, days: 20, photosPerWeek: 7)
        #expect(Self.residenceNames(Self.timeline(scenario, config: config)) == ["Sydney", "Melbourne"])
    }

    @Test func quietWeeksAtHomeStillCountAsHome() {
        // One photo a week at home, but a photo every day on a 10-day trip:
        // home still holds most of the time.
        let scenario = Scenario()
            .live(at: .sydney, days: 42, photosPerWeek: 1)
            .trip(to: .hobart, nights: 9, photosPerDay: 1)
            .live(at: .sydney, days: 42, photosPerWeek: 1)
        let timeline = Self.timeline(scenario)
        #expect(Self.residenceNames(timeline) == ["Sydney"])
    }

    // MARK: - Sparse libraries

    @Test func withoutAResidenceHomeIsWhereMostDaysWereSpent() {
        let scenario = Scenario()
            .live(at: .melbourne, days: 5, photosPerWeek: 7)
            .live(at: .sydney, days: 10, photosPerWeek: 7)
        let timeline = Self.timeline(scenario)
        #expect(timeline.residences.isEmpty)
        #expect(Self.name(timeline.home(on: Self.noon(scenario, day: 2))) == "Sydney")
    }

    @Test func fallbackTieGoesToTheFirstPlace() {
        let scenario = Scenario()
            .live(at: .melbourne, days: 5, photosPerWeek: 7)
            .live(at: .sydney, days: 5, photosPerWeek: 7)
        #expect(Self.name(Self.timeline(scenario).home(on: .now)) == "Melbourne")
    }

    // MARK: - Days

    private static func moment(_ id: String, at date: Date, in place: FixturePlace) -> PhotoMoment {
        PhotoMoment(id: id, start: date, end: date, photoIDs: [id], coverID: id, coverAspectRatio: 1, coordinate: place.coordinate)
    }

    @Test func aDayIsAnchoredWhereItEnds() throws {
        let scenario = Scenario()
        let morning = scenario.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: scenario.start)!
        let evening = scenario.calendar.date(bySettingHour: 20, minute: 0, second: 0, of: scenario.start)!
        let timeline = HomeInference.infer(
            [Self.moment("evening", at: evening, in: .melbourne), Self.moment("morning", at: morning, in: .sydney)],
            calendar: scenario.calendar
        )
        let day = try #require(timeline.days.first)
        #expect(timeline.days.count == 1)
        #expect(Self.name(timeline.clusters[day.clusterID]) == "Melbourne")
        // Sydney was only passed through, so it isn't a place of its own.
        #expect(timeline.cluster(containing: FixturePlace.sydney.coordinate) == nil)
    }

    @Test func daysFollowTheLocalCalendar() {
        let scenario = Scenario()
        let lateNight = scenario.calendar.date(bySettingHour: 23, minute: 30, second: 0, of: scenario.start)!
        let timeline = HomeInference.infer(
            [Self.moment("a", at: lateNight, in: .sydney), Self.moment("b", at: lateNight.addingTimeInterval(60 * 60), in: .sydney)],
            calendar: scenario.calendar
        )
        #expect(timeline.days.map(\.index) == [0, 1])
    }

    // MARK: - Determinism and speed

    @Test func inputOrderDoesntMatter() {
        let scenario = Scenario()
            .live(at: .sydney, days: 40)
            .trip(to: .hobart, nights: 3)
            .live(at: .melbourne, days: 40)
        let forward = HomeInference.infer(scenario.moments, calendar: scenario.calendar)
        let reversed = HomeInference.infer(scenario.moments.reversed(), calendar: scenario.calendar)
        #expect(forward == reversed)
    }

    @Test func tenYearsIsQuick() {
        var scenario = Scenario()
        for round in 0..<40 {
            scenario = scenario
                .live(at: .sydney, days: 80, photosPerWeek: 7)
                .trip(to: round.isMultiple(of: 2) ? .melbourne : .hobart, nights: 3)
        }
        var timeline: HomeTimeline?
        let elapsed = ContinuousClock().measure {
            timeline = HomeInference.infer(scenario.moments, calendar: scenario.calendar)
        }
        #expect(timeline?.residences.count == 1)
        // Generous, because tests run as an unoptimised Debug build.
        #expect(elapsed < .milliseconds(500))
    }
}
