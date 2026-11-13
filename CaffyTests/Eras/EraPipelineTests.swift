import Foundation
import Testing
@testable import Caffy

/// Tests for the library-additions stage inside `EraPipeline`.
struct EraPipelineTests {
    /// Home in Sydney with a weekend in Melbourne inside it, now past. Songs
    /// are added at noon just before the trip leaves, on its middle day, and
    /// the day after it.
    private static let tripWithAdditions = Scenario()
        .listen(to: "Tame Impala", genre: "Psychedelic")
        .live(at: .sydney, days: 30)
        .addToLibrary(["Packing Song"], by: "Courtney Barnett", genre: "Indie rock", plays: 5)
        .trip(to: .melbourne, nights: 2)
        // The trip filled three days; its middle day is two before the cursor.
        .addToLibrary(["Road Song", "Highway Song"], by: "Courtney Barnett", genre: "Indie rock", plays: 8, hour: 18, daysBack: 2)
        .addToLibrary(["Home Again Song"], by: "Courtney Barnett", genre: "Indie rock", plays: 5)
        .live(at: .sydney, days: 40)

    @Test func aNestedTripGetsOnlyTheSongsAddedDuringIt() async throws {
        let result = await PipelineHarness.run(Self.tripWithAdditions)
        let trip = try #require(result.eras.first { $0.draft.kind == .trip })
        #expect(trip.draft.end != nil)
        #expect(trip.addedSongs.map(\.song.title) == ["Road Song", "Highway Song"])
        #expect(trip.addedSongs.allSatisfy { $0.evidence == .libraryAdded })

        let playlist = result.playlist(for: trip)
        let added = playlist.filter { $0.evidence == .libraryAdded }.map(\.song.title)
        #expect(added == ["Road Song", "Highway Song"])
        // Songs played near the trip's moments still come first.
        #expect(playlist.first?.evidence == .nearPlay)

        // The home era around it gets the songs from just before and after.
        let homeAdded = Set(result.eras.filter { $0.draft.kind == .home }.flatMap(\.addedSongs).map(\.song.title))
        #expect(homeAdded == ["Packing Song", "Home Again Song"])
    }

    @Test func withoutALibraryErasHaveNoAdditions() async {
        let scenario = Self.tripWithAdditions
        let pipeline = EraPipeline(namer: SamplePlaceNamer(), sampler: PipelineHarness.sampler(for: scenario.moments))
        let result = await pipeline.run(moments: scenario.moments, plays: scenario.plays, now: scenario.now, calendar: scenario.calendar)
        #expect(result.eras.allSatisfy { $0.addedSongs.isEmpty })
    }

    @Test func momentsBeforeAnyListeningAreNotMatched() async throws {
        // Two months of photos, but listening only starts in the second.
        let scenario = Scenario()
            .silence()
            .live(at: .sydney, days: 30)
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 30)
        let result = await PipelineHarness.run(scenario)
        let firstPlay = try #require(scenario.plays.first).interval.start
        let firstDay = scenario.calendar.startOfDay(for: firstPlay)
        for moment in scenario.moments {
            if moment.start < firstDay {
                #expect(result.matches[moment.id] == nil)
            } else {
                #expect(result.matches[moment.id] != nil)
            }
        }
    }
}
