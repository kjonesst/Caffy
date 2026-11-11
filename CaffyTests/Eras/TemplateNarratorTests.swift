import Foundation
import Testing
@testable import Caffy

/// Tests for `TemplateNarrator`, which writes era titles, summaries and
/// when-labels from templates.
struct TemplateNarratorTests {
    // MARK: - Fixtures

    private static let calendar = Scenario().calendar

    /// A local time in Sydney. 2 February 2026 is a Monday.
    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static let narrator = TemplateNarrator(calendar: calendar, now: date(2026, 6, 1))

    private static func plays(_ artist: String, genre: String? = nil, count: Int) -> [ListeningEvent] {
        (0..<count).map { index in
            ListeningEvent(
                song: Song(id: "\(artist)-\(index % 3)", title: "Track", artist: artist, genre: genre),
                interval: DateInterval(start: date(2026, 1, 1).addingTimeInterval(Double(index) * 600), duration: 200)
            )
        }
    }

    private static func facts(
        _ kind: EraKind = .home,
        id: String = "m0001",
        from start: Date,
        to lastPhoto: Date,
        isCurrent: Bool = false,
        places: [String] = [],
        latitude: Double? = -33.87,
        homeChange: EraFacts.HomeChange? = nil,
        listening: [ListeningEvent] = [],
        previous: [ListeningEvent]? = nil
    ) -> EraFacts {
        EraFacts(
            id: id,
            kind: kind,
            start: start,
            end: isCurrent ? nil : lastPhoto,
            lastPhoto: lastPhoto,
            momentCount: 10,
            homeChange: homeChange,
            placeNames: places,
            latitude: latitude,
            listening: ListeningProfile(listening),
            previousListening: previous.map { ListeningProfile($0) }
        )
    }

    private static func tripTitle(from start: Date, to end: Date, places: [String] = ["Melbourne"]) -> String {
        narrator.title(for: facts(.trip, from: start, to: end, places: places))
    }

    // MARK: - Trip titles

    @Test func oneNight() {
        #expect(Self.tripTitle(from: Self.date(2026, 2, 3, hour: 18), to: Self.date(2026, 2, 4, hour: 10), places: ["Hobart"]) == "A night in Hobart")
    }

    @Test func fridayToSundayIsAWeekend() {
        #expect(Self.tripTitle(from: Self.date(2026, 2, 6, hour: 18), to: Self.date(2026, 2, 8)) == "A weekend in Melbourne")
    }

    @Test func twoNightsMidweekAreThreeDays() {
        #expect(Self.tripTitle(from: Self.date(2026, 2, 9, hour: 18), to: Self.date(2026, 2, 11)) == "Three days in Melbourne")
    }

    @Test(arguments: [
        (4, "Five days in Melbourne"),
        (7, "A week in Melbourne"),
        (10, "Eleven days in Melbourne"),
        (14, "Two weeks in Melbourne"),
        (20, "Three weeks in Melbourne"),
        (34, "Five weeks in Melbourne")
    ])
    func longerTrips(nights: Int, title: String) {
        // Starting on a Monday, so no short trip here counts as a weekend.
        let start = Self.date(2026, 2, 9, hour: 18)
        let end = Self.calendar.date(byAdding: .day, value: nights, to: Self.date(2026, 2, 9, hour: 10))!
        #expect(Self.tripTitle(from: start, to: end) == title)
    }

    @Test func nightsCountPastFourAM() {
        let late = Self.facts(.trip, from: Self.date(2026, 2, 9, hour: 20), to: Self.date(2026, 2, 10, hour: 3))
        let morning = Self.facts(.trip, from: Self.date(2026, 2, 9, hour: 20), to: Self.date(2026, 2, 10, hour: 5))
        #expect(Self.narrator.nights(of: late) == 0)
        #expect(Self.narrator.nights(of: morning) == 1)
    }

    @Test func tripWithoutAPlaceNameIsAway() {
        #expect(Self.tripTitle(from: Self.date(2026, 2, 6, hour: 18), to: Self.date(2026, 2, 8), places: []) == "A weekend away")
    }

    @Test(arguments: [
        (["Melbourne", "Hobart"], "Melbourne & Hobart"),
        (["Melbourne", "Hobart", "Launceston"], "Melbourne, Hobart & Launceston"),
        (["Melbourne", "Hobart", "Launceston", "Bruny Island"], "Melbourne, Hobart & more")
    ])
    func multiCityTripsAreNamedByTheirPlaces(places: [String], title: String) {
        #expect(Self.tripTitle(from: Self.date(2026, 2, 9, hour: 18), to: Self.date(2026, 2, 14), places: places) == title)
    }

    // MARK: - Home titles

    @Test func singleDayEra() {
        let facts = Self.facts(from: Self.date(2026, 3, 14, hour: 10), to: Self.date(2026, 3, 14, hour: 16), places: ["Sydney"])
        #expect(Self.narrator.title(for: facts) == "One day in March")
    }

    @Test func currentEraIsNeverJustOneDay() {
        let facts = Self.facts(from: Self.date(2026, 3, 14, hour: 10), to: Self.date(2026, 3, 14, hour: 16), isCurrent: true)
        #expect(Self.narrator.title(for: facts) != "One day in March")
    }

    @Test func movingSomewhereNew() {
        let facts = Self.facts(from: Self.date(2026, 3, 1), to: Self.date(2026, 5, 1), places: ["Melbourne"], homeChange: .newHome)
        #expect(Self.narrator.title(for: facts) == "New in Melbourne")
    }

    @Test func movingBack() {
        let facts = Self.facts(from: Self.date(2026, 7, 1), to: Self.date(2026, 9, 1), places: ["Sydney"], homeChange: .backHome)
        #expect(Self.narrator.title(for: facts) == "Back in Sydney")
    }

    @Test func dominantArtistTitlesTheEra() {
        let facts = Self.facts(
            from: Self.date(2026, 3, 1), to: Self.date(2026, 5, 1),
            listening: Self.plays("Tame Impala", count: 30) + Self.plays("Fred again..", count: 20)
        )
        #expect(Self.narrator.title(for: facts) == "On repeat: Tame Impala")
    }

    @Test func noDominantArtistMeansASeasonTitle() {
        let evenMix = ["A", "B", "C", "D", "E"].flatMap { Self.plays($0, count: 10) }
        let tooLittle = Self.plays("Tame Impala", count: 5)
        for listening in [evenMix, tooLittle] {
            let facts = Self.facts(from: Self.date(2026, 1, 5), to: Self.date(2026, 2, 20), listening: listening)
            #expect(Self.narrator.title(for: facts).contains("Summer"))
        }
    }

    @Test func seasonsFlipSouthOfTheEquator() {
        let southern = Self.facts(from: Self.date(2026, 1, 5), to: Self.date(2026, 2, 20), latitude: -33.87)
        let northern = Self.facts(from: Self.date(2026, 1, 5), to: Self.date(2026, 2, 20), latitude: 51.5)
        let unknown = Self.facts(from: Self.date(2026, 1, 5), to: Self.date(2026, 2, 20), latitude: nil)
        #expect(Self.narrator.title(for: southern).contains("Summer"))
        #expect(Self.narrator.title(for: northern).contains("Winter"))
        #expect(Self.narrator.title(for: unknown).contains("Winter"))
    }

    @Test func seasonWordingIsChosenByEraIDAndNeverChanges() {
        let titles = (1...40).map { number in
            Self.narrator.title(for: Self.facts(
                id: "m\(number)", from: Self.date(2026, 4, 1), to: Self.date(2026, 5, 20), places: ["Sydney"]
            ))
        }
        #expect(Set(titles) == ["Autumn at home", "Autumn, 2026", "Autumn in Sydney"])

        let again = Self.narrator.title(for: Self.facts(id: "m7", from: Self.date(2026, 4, 1), to: Self.date(2026, 5, 20), places: ["Sydney"]))
        #expect(again == titles[6])
    }

    // MARK: - Summaries

    @Test func quietEras() {
        let home = Self.facts(from: Self.date(2026, 3, 1), to: Self.date(2026, 5, 1), listening: Self.plays("A", count: 3))
        let trip = Self.facts(.trip, from: Self.date(2026, 3, 1), to: Self.date(2026, 3, 3))
        #expect(Self.narrator.summary(for: home) == "A quiet one for music.")
        #expect(Self.narrator.summary(for: trip) == "No music on this one.")
    }

    @Test func tripSoundtrack() {
        let one = Self.facts(.trip, from: Self.date(2026, 3, 1), to: Self.date(2026, 3, 3), listening: Self.plays("Fred again..", count: 20))
        let two = Self.facts(.trip, from: Self.date(2026, 3, 1), to: Self.date(2026, 3, 3),
                             listening: Self.plays("Fred again..", count: 20) + Self.plays("Bicep", count: 12))
        #expect(Self.narrator.summary(for: one) == "The soundtrack: Fred again...")
        #expect(Self.narrator.summary(for: two) == "The soundtrack: Fred again.. and Bicep.")
    }

    @Test func newGenreTakesOverAndAnotherArrives() {
        let facts = Self.facts(
            from: Self.date(2026, 3, 1), to: Self.date(2026, 5, 1),
            listening: Self.plays("Love Remain", genre: "chillout", count: 20) + Self.plays("Etherwood", genre: "drum & bass", count: 10),
            previous: Self.plays("Above & Beyond", genre: "trance", count: 30)
        )
        #expect(Self.narrator.summary(for: facts) == "Chillout takes over, and drum & bass arrives.")
    }

    @Test func newGenreTakesOver() {
        let facts = Self.facts(
            from: Self.date(2026, 3, 1), to: Self.date(2026, 5, 1),
            listening: Self.plays("Fred again..", genre: "Electronic", count: 20) + Self.plays("Tame Impala", genre: "Psychedelic", count: 10),
            previous: Self.plays("Tame Impala", genre: "Psychedelic", count: 20) + Self.plays("Fred again..", genre: "Electronic", count: 10)
        )
        #expect(Self.narrator.summary(for: facts) == "Electronic takes over from Psychedelic.")
    }

    @Test func genreArrivesAlongsideTheSameFavourite() {
        let facts = Self.facts(
            from: Self.date(2026, 3, 1), to: Self.date(2026, 5, 1),
            listening: Self.plays("Tame Impala", genre: "Psychedelic", count: 20) + Self.plays("Kamasi Washington", genre: "Jazz", count: 10),
            previous: Self.plays("Tame Impala", genre: "Psychedelic", count: 30)
        )
        #expect(Self.narrator.summary(for: facts) == "Jazz arrives alongside Psychedelic.")
    }

    @Test func steadyGenresFallBackToArtists() {
        let previous = Self.plays("Tame Impala", genre: "Psychedelic", count: 30)
        let mostlyOne = Self.facts(
            from: Self.date(2026, 3, 1), to: Self.date(2026, 5, 1),
            listening: Self.plays("Tame Impala", genre: "Psychedelic", count: 30) + Self.plays("Pond", genre: "Psychedelic", count: 10),
            previous: previous
        )
        let mixed = Self.facts(
            from: Self.date(2026, 3, 1), to: Self.date(2026, 5, 1),
            listening: Self.plays("Pond", genre: "Psychedelic", count: 10)
                + Self.plays("Tame Impala", genre: "Psychedelic", count: 8)
                + Self.plays("MGMT", genre: "Psychedelic", count: 7),
            previous: previous
        )
        #expect(Self.narrator.summary(for: mostlyOne) == "Hardly anything but Tame Impala.")
        #expect(Self.narrator.summary(for: mixed) == "Mostly Pond and Tame Impala.")
    }

    @Test func firstEraDescribesItsArtists() {
        let facts = Self.facts(
            from: Self.date(2026, 3, 1), to: Self.date(2026, 5, 1),
            listening: Self.plays("Pond", genre: "Psychedelic", count: 10)
                + Self.plays("MGMT", genre: "Psychedelic", count: 10)
                + Self.plays("Air", genre: "Electronic", count: 5)
        )
        // Equal plays are ordered by name.
        #expect(Self.narrator.summary(for: facts) == "Mostly MGMT and Pond.")
    }

    // MARK: - When-labels

    @Test func whenLabels() {
        let withinAYear = Self.facts(from: Self.date(2026, 3, 1), to: Self.date(2026, 5, 1))
        let acrossNewYear = Self.facts(from: Self.date(2025, 11, 20), to: Self.date(2026, 2, 1))
        let stillGoing = Self.facts(from: Self.date(2025, 12, 20), to: Self.date(2026, 1, 10), isCurrent: true)
        let trip = Self.facts(.trip, from: Self.date(2026, 2, 6, hour: 18), to: Self.date(2026, 2, 8))

        #expect(Self.narrator.whenLabel(for: withinAYear) == "2026")
        #expect(Self.narrator.whenLabel(for: acrossNewYear) == "2025–26")
        // Still going in June 2026 (the narrator's `now`).
        #expect(Self.narrator.whenLabel(for: stillGoing) == "2025–26")
        #expect(Self.narrator.whenLabel(for: trip) == "Feb 2026")
    }

    @Test func contentPutsItAllTogether() {
        let facts = Self.facts(.trip, from: Self.date(2026, 2, 6, hour: 18), to: Self.date(2026, 2, 8),
                               places: ["Melbourne"], listening: Self.plays("Fred again..", count: 20))
        #expect(Self.narrator.content(for: facts) == EraContent(
            title: "A weekend in Melbourne",
            summary: "The soundtrack: Fred again...",
            whenLabel: "Feb 2026"
        ))
    }
}
