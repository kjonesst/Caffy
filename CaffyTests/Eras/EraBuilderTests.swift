import Foundation
import Testing
@testable import Caffy

/// Tests for `EraBuilder` and `EraPipeline` with frozen eras: finished eras
/// must never change once frozen.
struct EraBuilderTests {
    // MARK: - Fixtures

    private static let day: TimeInterval = 24 * 60 * 60

    /// Two home eras split by a change in music. By the end, the first ended
    /// about eight weeks ago, so it's frozen.
    private static let musicShift = Scenario()
        .listen(to: "Tame Impala", genre: "Psychedelic")
        .live(at: .sydney, days: 63)
        .listen(to: "Fred again..", genre: "Electronic")
        .live(at: .sydney, days: 56)

    private static func draft(_ id: String, _ kind: EraKind = .home, start: Double, end: Double?) -> EraDraft {
        let base = Scenario().start
        return EraDraft(
            id: id, kind: kind, momentIDs: [id],
            start: base.addingTimeInterval(start * day),
            end: end.map { base.addingTimeInterval($0 * day) },
            centre: nil, startReason: .firstMoment
        )
    }

    private static func moment(_ id: String, at date: Date, in place: FixturePlace) -> PhotoMoment {
        PhotoMoment(id: id, start: date, end: date, photoIDs: [id], coverID: id, coverAspectRatio: 1, coordinate: place.coordinate)
    }

    // MARK: - Which eras freeze

    @Test func finishedErasFreezeTwoWeeksAfterTheyEnd() async throws {
        let result = await PipelineHarness.run(Self.musicShift)
        #expect(result.eras.map(\.isFrozen) == [true, false])

        // Ten days after the first era ends, it isn't frozen yet.
        let firstEnd = try #require(result.eras[0].draft.end)
        let early = await PipelineHarness.run(Self.musicShift, now: firstEnd.addingTimeInterval(10 * Self.day))
        #expect(early.eras.allSatisfy { !$0.isFrozen })
    }

    @Test func erasFreezeOldestFirst() {
        let drafts = [
            Self.draft("season", start: 0, end: nil),
            Self.draft("trip", .trip, start: 10, end: 12),
        ]
        let now = Scenario().start.addingTimeInterval(100 * Self.day)
        // The trip ended long ago, but the season around it is still going.
        #expect(EraBuilder.frozenIDs(of: drafts, alreadyFrozen: [], now: now, config: .standard).isEmpty)

        let finished = [
            Self.draft("first", start: 0, end: 50),
            Self.draft("trip", .trip, start: 20, end: 22),
            Self.draft("second", start: 51, end: 90),
            Self.draft("third", start: 91, end: nil),
        ]
        #expect(EraBuilder.frozenIDs(of: finished, alreadyFrozen: [], now: now, config: .standard) == ["first", "trip"])
    }

    // MARK: - Frozen eras don't change

    /// Two results with the same eras, words, colours and songs. Start
    /// reasons can differ: the first open era after frozen ones is cut on its
    /// own, so a music change before it reads as `.firstMoment`.
    private static func sameExceptReasons(_ a: EraPipelineResult, _ b: EraPipelineResult) -> Bool {
        func strip(_ era: BuiltEra) -> BuiltEra {
            let d = era.draft
            return BuiltEra(
                draft: EraDraft(id: d.id, kind: d.kind, momentIDs: d.momentIDs, start: d.start, end: d.end, centre: d.centre, startReason: .firstMoment),
                content: era.content, palette: era.palette, isFrozen: era.isFrozen
            )
        }
        return a.eras.map(strip) == b.eras.map(strip) && a.songs == b.songs
    }

    @Test func rerunningWithFrozenErasChangesNothing() async {
        let first = await PipelineHarness.run(Self.musicShift)
        let second = await PipelineHarness.run(Self.musicShift, frozen: PipelineHarness.frozen(first))
        #expect(Self.sameExceptReasons(first, second))
        #expect(second.eras[1].draft.startReason == .firstMoment)
    }

    @Test func frozenErasSurviveNewPhotosAndNewRules() async throws {
        let first = await PipelineHarness.run(Self.musicShift)
        let frozen = try #require(first.eras.first)

        // A month later, with much shorter eras configured. Without freezing,
        // the first era (about nine weeks) would be re-cut.
        var stricter = EraBuildConfig()
        stricter.maxEraLength = 40 * Self.day
        stricter.minEraLength = 15 * Self.day
        let later = Self.musicShift.live(at: .sydney, days: 30)
        let second = await PipelineHarness.run(later, frozen: PipelineHarness.frozen(first), config: stricter)

        #expect(second.eras.first == frozen)
        let unfrozen = await PipelineHarness.run(later, config: stricter)
        #expect(unfrozen.eras.first != frozen)
    }

    @Test func currentEraKeepsGrowing() async {
        let first = await PipelineHarness.run(Self.musicShift)
        let later = Self.musicShift.live(at: .sydney, days: 10)
        let second = await PipelineHarness.run(later, frozen: PipelineHarness.frozen(first))

        #expect(second.eras.count == 2)
        #expect(second.eras[1].draft.id == first.eras[1].draft.id)
        #expect(second.eras[1].draft.momentIDs.count > first.eras[1].draft.momentIDs.count)
        #expect(second.eras[1].draft.isCurrent)
    }

    // MARK: - Photos imported late

    @Test func latePhotoJoinsTheFrozenEraItBelongsTo() async throws {
        let first = await PipelineHarness.run(Self.musicShift)
        let frozen = try #require(first.eras.first)
        let middle = frozen.draft.start.addingTimeInterval(30 * Self.day + 3 * 60 * 60)
        let late = Self.moment("late", at: middle, in: .sydney)

        let second = await PipelineHarness.run(Self.musicShift, moments: Self.musicShift.moments + [late], frozen: PipelineHarness.frozen(first))
        let updated = try #require(second.eras.first)

        #expect(updated.draft.momentIDs.contains("late"))
        #expect(updated.draft.momentIDs.count == frozen.draft.momentIDs.count + 1)
        #expect(updated.content == frozen.content)
        #expect(updated.palette == frozen.palette)
        #expect(updated.isFrozen)
        // Still in time order.
        let order = (Self.musicShift.moments + [late]).sorted { $0.start < $1.start }.map(\.id)
        #expect(updated.draft.momentIDs == order.filter { updated.draft.momentIDs.contains($0) })
    }

    @Test func latePhotoOnAFrozenTripJoinsTheTrip() async throws {
        let scenario = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 25)
            .trip(to: .melbourne, nights: 2)
            .live(at: .sydney, days: 38)
            .listen(to: "Fred again..", genre: "Electronic")
            .live(at: .sydney, days: 60)
        let first = await PipelineHarness.run(scenario)
        #expect(first.kinds == [.home, .trip, .home])
        #expect(first.eras.map(\.isFrozen) == [true, true, false])

        let trip = first.eras[1].draft
        let late = Self.moment("late", at: trip.start.addingTimeInterval(12 * 60 * 60), in: .melbourne)
        let second = await PipelineHarness.run(scenario, moments: scenario.moments + [late], frozen: PipelineHarness.frozen(first))
        #expect(second.eras[1].draft.momentIDs.contains("late"))
        #expect(!second.eras[0].draft.momentIDs.contains("late"))
    }

    @Test func latePhotoOutsideEveryFrozenEraGetsItsOwn() async throws {
        let first = await PipelineHarness.run(Self.musicShift)
        // Two months before the library began.
        let early = Self.moment("early", at: Self.musicShift.start.addingTimeInterval(-60 * Self.day), in: .sydney)
        let second = await PipelineHarness.run(Self.musicShift, moments: [early] + Self.musicShift.moments, frozen: PipelineHarness.frozen(first))

        #expect(second.eras.count == 3)
        #expect(second.eras[0].draft.momentIDs == ["early"])
        #expect(second.eras[1] == first.eras[0])
    }

    // MARK: - Photos removed

    @Test func deletedPhotosLeaveTheirFrozenEra() async throws {
        let first = await PipelineHarness.run(Self.musicShift)
        let frozen = try #require(first.eras.first)
        let removed = frozen.draft.momentIDs[3]
        let remaining = Self.musicShift.moments.filter { $0.id != removed }

        let second = await PipelineHarness.run(Self.musicShift, moments: remaining, frozen: PipelineHarness.frozen(first))
        #expect(second.eras[0].draft.momentIDs == frozen.draft.momentIDs.filter { $0 != removed })
        #expect(second.eras[0].content == frozen.content)
    }

    @Test func frozenEraWithNoPhotosLeftDisappears() async throws {
        let first = await PipelineHarness.run(Self.musicShift)
        let frozenIDs = Set(try #require(first.eras.first).draft.momentIDs)
        let remaining = Self.musicShift.moments.filter { !frozenIDs.contains($0.id) }

        let second = await PipelineHarness.run(Self.musicShift, moments: remaining, frozen: PipelineHarness.frozen(first))
        #expect(second.eras.map(\.draft.id) == [first.eras[1].draft.id])
    }

    // MARK: - The first era after frozen ones

    @Test func moveAfterFrozenErasIsStillNew() async {
        let scenario = Scenario()
            .live(at: .sydney, days: 60)
            .live(at: .melbourne, days: 80)
        let first = await PipelineHarness.run(scenario)
        #expect(first.eras.map(\.isFrozen) == [true, false])

        let second = await PipelineHarness.run(scenario, frozen: PipelineHarness.frozen(first))
        #expect(second == first)
        #expect(second.titles[1] == "New in Melbourne")
        #expect(second.eras[1].draft.startReason == .homeChange)
    }

    @Test func firstEraAfterFrozenOnesAvoidsTheirColour() async throws {
        // All photos the same green, so only neighbour-avoidance can make
        // the second era's colour different.
        let first = await PipelineHarness.run(Self.musicShift)
        let second = await PipelineHarness.run(Self.musicShift, frozen: PipelineHarness.frozen(first))
        let gap = RGBColor(hex: second.eras[0].palette.paperHex).oklab
            .distance(to: RGBColor(hex: second.eras[1].palette.paperHex).oklab) * 100
        #expect(gap >= 12)
    }
}
