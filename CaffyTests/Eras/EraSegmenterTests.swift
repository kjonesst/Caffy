import Foundation
import Testing
@testable import Caffy

/// Tests for `EraSegmenter`'s hard cuts: overnight trips, day trips, long
/// gaps and moving home.
struct EraSegmenterTests {
    // MARK: - Fixtures

    private static func eras(_ scenario: Scenario, now: Date? = nil, config: EraBuildConfig = .standard) -> [EraDraft] {
        eras(scenario.moments, now: now ?? scenario.now, calendar: scenario.calendar, config: config)
    }

    private static func eras(
        _ moments: [PhotoMoment],
        now: Date,
        calendar: Calendar = base.calendar,
        config: EraBuildConfig = .standard
    ) -> [EraDraft] {
        let home = HomeInference.infer(moments, calendar: calendar, config: config)
        return EraSegmenter.segment(moments, home: home, now: now, calendar: calendar, config: config)
    }

    /// Each era as "kind moments", oldest first, for compact expectations.
    private static func shape(_ drafts: [EraDraft]) -> [String] {
        drafts.map { "\($0.kind.rawValue) \($0.momentIDs.count)" }
    }

    private static func name(_ coordinate: Coordinate?) -> String? {
        guard let coordinate else { return nil }
        let places: [FixturePlace] = [.sydney, .melbourne, .hobart, .wollongong]
        return places.first { $0.coordinate.distance(to: coordinate) < 10_000 }?.name
    }

    /// The ids of the moments a scenario step added.
    private static func ids(added after: Scenario, before: Scenario) -> [String] {
        after.moments.dropFirst(before.moments.count).map(\.id)
    }

    // Hand-made moments, for exact times.

    private static let base = Scenario()

    private static func time(day: Int, hour: Int, minute: Int = 0) -> Date {
        let date = base.calendar.date(byAdding: .day, value: day, to: base.start)!
        return base.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
    }

    private static func moment(_ id: String, day: Int, hour: Int, minute: Int = 0, at place: FixturePlace?) -> PhotoMoment {
        let date = time(day: day, hour: hour, minute: minute)
        return PhotoMoment(id: id, start: date, end: date, photoIDs: [id], coverID: id, coverAspectRatio: 1, coordinate: place?.coordinate)
    }

    /// A photo at noon in Sydney every second day from day 0 to day 60,
    /// skipping `excluded` days.
    private static func homeMoments(excluding excluded: ClosedRange<Int>) -> [PhotoMoment] {
        stride(from: 0, through: 60, by: 2)
            .filter { !excluded.contains($0) }
            .map { moment(String(format: "h%02d", $0), day: $0, hour: 12, at: .sydney) }
    }

    /// Two days after the hand-made home photos end.
    private static let handMadeNow = time(day: 62, hour: 12)

    // MARK: - Basics

    @Test func noMomentsGiveNoEras() {
        #expect(Self.eras(Scenario()).isEmpty)
    }

    @Test func steadyLifeAtHomeIsOneCurrentEra() throws {
        let scenario = Scenario().live(at: .sydney, days: 60)
        let drafts = Self.eras(scenario)
        let era = try #require(drafts.first)

        #expect(Self.shape(drafts) == ["home \(scenario.moments.count)"])
        #expect(era.isCurrent)
        #expect(era.startReason == .firstMoment)
        #expect(era.id == scenario.moments.first?.id)
        #expect(era.start == scenario.moments.first?.start)
        #expect(Self.name(era.centre) == "Sydney")
    }

    // MARK: - Trips

    @Test func weekendTripIsAnEraInsideTheSeason() throws {
        let before = Scenario().live(at: .sydney, days: 21)
        let away = before.trip(to: .melbourne, nights: 2)
        let scenario = away.live(at: .sydney, days: 21)
        let drafts = Self.eras(scenario)

        #expect(drafts.map(\.kind) == [.home, .trip])
        let season = drafts[0]
        let trip = drafts[1]

        #expect(trip.momentIDs == Self.ids(added: away, before: before))
        #expect(trip.startReason == .trip)
        #expect(Self.name(trip.centre) == "Melbourne")
        #expect(!trip.isCurrent)

        // The season carries on around the trip without sharing moments.
        #expect(season.isCurrent)
        #expect(season.momentIDs.count == scenario.moments.count - trip.momentIDs.count)
        #expect(Set(season.momentIDs).isDisjoint(with: trip.momentIDs))
        #expect(season.start < trip.start)
        #expect(Self.name(season.centre) == "Sydney")
    }

    @Test func oneNightAwayIsATrip() {
        let scenario = Scenario()
            .live(at: .sydney, days: 21)
            .trip(to: .hobart, nights: 1)
            .live(at: .sydney, days: 21)
        #expect(Self.eras(scenario).map(\.kind) == [.home, .trip])
    }

    @Test func dayTripStaysInTheSeason() {
        let scenario = Scenario()
            .live(at: .sydney, days: 21)
            .dayTrip(to: .wollongong)
            .live(at: .sydney, days: 21)
        #expect(Self.shape(Self.eras(scenario)) == ["home \(scenario.moments.count)"])
    }

    @Test func multiCityTripIsOneEra() throws {
        let before = Scenario().live(at: .sydney, days: 21)
        let away = before
            .trip(to: .melbourne, nights: 2)
            .trip(to: .hobart, nights: 2)
        let scenario = away.live(at: .sydney, days: 21)
        let trip = try #require(Self.eras(scenario).first { $0.kind == .trip })

        #expect(Self.eras(scenario).filter { $0.kind == .trip }.count == 1)
        #expect(trip.momentIDs == Self.ids(added: away, before: before))
        // As many moments in each city, so the first one visited wins.
        #expect(Self.name(trip.centre) == "Melbourne")
    }

    @Test func tripsWithHomeBetweenAreSeparate() {
        let scenario = Scenario()
            .live(at: .sydney, days: 14)
            .trip(to: .melbourne, nights: 2)
            .live(at: .sydney, days: 14)
            .trip(to: .hobart, nights: 2)
            .live(at: .sydney, days: 14)
        let drafts = Self.eras(scenario)
        #expect(drafts.map(\.kind) == [.home, .trip, .trip])
        #expect(drafts.filter { $0.kind == .trip }.map { Self.name($0.centre) } == ["Melbourne", "Hobart"])
    }

    @Test func awayPhotosDaysApartAreSeparateTrips() {
        // Melbourne, then nothing for six days, then Hobart, with no home
        // photo between.
        let moments = Self.homeMoments(excluding: 21...33) + [
            Self.moment("m1", day: 22, hour: 18, at: .melbourne),
            Self.moment("m2", day: 23, hour: 10, at: .melbourne),
            Self.moment("t1", day: 29, hour: 18, at: .hobart),
            Self.moment("t2", day: 30, hour: 10, at: .hobart)
        ]
        let trips = Self.eras(moments, now: Self.handMadeNow).filter { $0.kind == .trip }
        #expect(trips.map(\.momentIDs) == [["m1", "m2"], ["t1", "t2"]])
    }

    @Test(arguments: [(3, 30, false), (4, 30, true)])
    func aTripMustLastPastFourAM(hour: Int, minute: Int, isTrip: Bool) {
        let moments = Self.homeMoments(excluding: 21...23) + [
            Self.moment("w1", day: 22, hour: 20, at: .wollongong),
            Self.moment("w2", day: 23, hour: hour, minute: minute, at: .wollongong)
        ]
        let trips = Self.eras(moments, now: Self.handMadeNow).filter { $0.kind == .trip }
        #expect(trips.map(\.momentIDs) == (isTrip ? [["w1", "w2"]] : []))
    }

    @Test func aSingleAwayPhotoIsADayTrip() {
        let moments = Self.homeMoments(excluding: 21...23) + [Self.moment("w", day: 22, hour: 23, at: .wollongong)]
        #expect(Self.eras(moments, now: Self.handMadeNow).allSatisfy { $0.kind == .home })
    }

    // MARK: - Photos without a location

    @Test func unlocatedPhotoOnATripJoinsIt() {
        let moments = Self.homeMoments(excluding: 21...25) + [
            Self.moment("m1", day: 22, hour: 18, at: .melbourne),
            Self.moment("u", day: 23, hour: 11, at: nil),
            Self.moment("m2", day: 23, hour: 19, at: .melbourne),
            Self.moment("m3", day: 24, hour: 10, at: .melbourne)
        ]
        let trips = Self.eras(moments, now: Self.handMadeNow).filter { $0.kind == .trip }
        #expect(trips.map(\.momentIDs) == [["m1", "u", "m2", "m3"]])
    }

    @Test func unlocatedPhotoFarFromATripCountsAsHome() throws {
        let moments = Self.homeMoments(excluding: 21...25) + [
            Self.moment("m1", day: 22, hour: 18, at: .melbourne),
            Self.moment("m2", day: 23, hour: 10, at: .melbourne),
            // 26 hours after the trip's last photo.
            Self.moment("u", day: 24, hour: 12, at: nil)
        ]
        let drafts = Self.eras(moments, now: Self.handMadeNow)
        let trip = try #require(drafts.first { $0.kind == .trip })
        let season = try #require(drafts.first { $0.kind == .home })
        #expect(trip.momentIDs == ["m1", "m2"])
        #expect(season.momentIDs.contains("u"))
    }

    @Test func libraryWithoutLocationsHasNoTrips() throws {
        let scenario = Scenario()
            .unlocated()
            .live(at: .sydney, days: 30)
            .trip(to: .melbourne, nights: 2)
            .live(at: .sydney, days: 30)
        let drafts = Self.eras(scenario)
        let era = try #require(drafts.first)
        #expect(Self.shape(drafts) == ["home \(scenario.moments.count)"])
        #expect(era.centre == nil)
    }

    @Test func libraryWithoutLocationsStillSplitsAtGaps() {
        let scenario = Scenario()
            .unlocated()
            .live(at: .sydney, days: 30)
            .gap(days: 60)
            .live(at: .sydney, days: 30)
        #expect(Self.eras(scenario).map(\.startReason) == [.firstMoment, .longGap])
    }

    // MARK: - Gaps

    @Test func gapOfSeveralMonthsSplitsTheEra() throws {
        let first = Scenario().live(at: .sydney, days: 40)
        let scenario = first.gap(days: 120).live(at: .sydney, days: 40)
        let drafts = Self.eras(scenario)

        #expect(drafts.map(\.kind) == [.home, .home])
        #expect(drafts.map(\.startReason) == [.firstMoment, .longGap])
        #expect(drafts[0].momentIDs == first.moments.map(\.id))
        #expect(drafts[0].end == first.moments.last?.end)
        #expect(drafts[1].isCurrent)
    }

    @Test(arguments: [(19, 1), (22, 2)])
    func gapsSplitFromThreeWeeks(gapDays: Int, eraCount: Int) {
        let scenario = Scenario()
            .live(at: .sydney, days: 30, photosPerWeek: 7)
            .gap(days: gapDays)
            .live(at: .sydney, days: 30, photosPerWeek: 7)
        #expect(Self.eras(scenario).count == eraCount)
    }

    @Test func tripAfterALongGapStandsAlone() {
        // Home, months of nothing, a trip, months of nothing, home again.
        let scenario = Scenario()
            .live(at: .sydney, days: 40)
            .gap(days: 60)
            .trip(to: .hobart, nights: 3)
            .gap(days: 60)
            .live(at: .sydney, days: 40)
        let drafts = Self.eras(scenario)
        #expect(drafts.map(\.kind) == [.home, .trip, .home])
        #expect(drafts[2].startReason == .longGap)
    }

    // MARK: - Moving home

    @Test func exchangeSemesterMovesHomeAndBack() {
        let scenario = Scenario()
            .live(at: .sydney, days: 60)
            .live(at: .melbourne, days: 60)
            .trip(to: .sydney, nights: 2)
            .live(at: .melbourne, days: 60)
            .live(at: .sydney, days: 60)
        let drafts = Self.eras(scenario)

        #expect(drafts.map(\.kind) == [.home, .home, .trip, .home])
        #expect(drafts.map { Self.name($0.centre) } == ["Sydney", "Melbourne", "Sydney", "Sydney"])
        #expect(drafts.map(\.startReason) == [.firstMoment, .homeChange, .trip, .homeChange])
        // The weekend back in Sydney sits inside the Melbourne era's dates.
        #expect(drafts[2].start > drafts[1].start)
        #expect(drafts[2].end! < drafts[3].start)
    }

    @Test func shortStayElsewhereIsATrip() {
        let scenario = Scenario()
            .live(at: .sydney, days: 60)
            .live(at: .melbourne, days: 20, photosPerWeek: 7)
            .live(at: .sydney, days: 30)
        let drafts = Self.eras(scenario)
        #expect(Self.shape(drafts) == ["home \(scenario.moments.count - 20)", "trip 20"])
    }

    // MARK: - Now

    @Test func tripInProgressIsCurrent() {
        let scenario = Scenario()
            .live(at: .sydney, days: 30)
            .trip(to: .melbourne, nights: 2)
        let drafts = Self.eras(scenario)
        #expect(drafts.map(\.kind) == [.home, .trip])
        #expect(drafts.map(\.isCurrent) == [true, true])

        let twoDaysLater = scenario.now.addingTimeInterval(2 * 24 * 60 * 60)
        let later = Self.eras(scenario, now: twoDaysLater)
        #expect(later.map(\.isCurrent) == [true, false])
    }

    @Test func homeEraEndsAfterAMonthWithoutPhotos() {
        let scenario = Scenario().live(at: .sydney, days: 30)
        let soon = Self.eras(scenario, now: scenario.now.addingTimeInterval(10 * 24 * 60 * 60))
        let muchLater = Self.eras(scenario, now: scenario.now.addingTimeInterval(30 * 24 * 60 * 60))
        #expect(soon.first?.isCurrent == true)
        #expect(muchLater.first?.end == scenario.moments.last?.end)
    }

    @Test func photosFromTheFutureAreIgnored() {
        let scenario = Scenario().live(at: .sydney, days: 30, photosPerWeek: 7)
        let now = Self.time(day: 10, hour: 12)
        let drafts = Self.eras(scenario, now: now)
        let expected = scenario.moments.filter { $0.start <= now.addingTimeInterval(24 * 60 * 60) }.map(\.id)
        #expect(drafts.flatMap(\.momentIDs) == expected)
    }

    // MARK: - Every moment once, always the same

    private static let busyLife = Scenario()
        .live(at: .sydney, days: 50)
        .trip(to: .melbourne, nights: 2)
        .dayTrip(to: .wollongong)
        .live(at: .sydney, days: 30)
        .gap(days: 40)
        .unlocated()
        .live(at: .sydney, days: 20)
        .located()
        .live(at: .melbourne, days: 60)
        .trip(to: .hobart, nights: 4)
        .live(at: .melbourne, days: 30)

    @Test func everyMomentIsInExactlyOneEra() {
        let ids = Self.eras(Self.busyLife).flatMap(\.momentIDs)
        #expect(ids.count == Self.busyLife.moments.count)
        #expect(Set(ids) == Set(Self.busyLife.moments.map(\.id)))
    }

    @Test func erasAreOldestFirstWithMomentsInOrder() {
        let drafts = Self.eras(Self.busyLife)
        #expect(drafts.map(\.start) == drafts.map(\.start).sorted())
        let order = Dictionary(uniqueKeysWithValues: Self.busyLife.moments.enumerated().map { ($1.id, $0) })
        for draft in drafts {
            let positions = draft.momentIDs.map { order[$0]! }
            #expect(positions == positions.sorted())
            #expect(draft.id == draft.momentIDs.first)
        }
    }

    @Test func inputOrderDoesntMatter() {
        let scenario = Self.busyLife
        let home = HomeInference.infer(scenario.moments, calendar: scenario.calendar)
        let forward = EraSegmenter.segment(scenario.moments, home: home, now: scenario.now, calendar: scenario.calendar)
        let reversed = EraSegmenter.segment(scenario.moments.reversed(), home: home, now: scenario.now, calendar: scenario.calendar)
        #expect(forward == reversed)
    }

    @Test func tenYearsIsQuick() {
        var scenario = Scenario()
        for round in 0..<40 {
            scenario = scenario
                .live(at: .sydney, days: 80, photosPerWeek: 7)
                .trip(to: round.isMultiple(of: 2) ? .melbourne : .hobart, nights: 3)
        }
        let home = HomeInference.infer(scenario.moments, calendar: scenario.calendar)
        var drafts: [EraDraft] = []
        let elapsed = ContinuousClock().measure {
            drafts = EraSegmenter.segment(scenario.moments, home: home, now: scenario.now, calendar: scenario.calendar)
        }
        #expect(drafts.filter { $0.kind == .trip }.count == 40)
        // Generous, because tests run as an unoptimised Debug build.
        #expect(elapsed < .milliseconds(500))
    }
}
