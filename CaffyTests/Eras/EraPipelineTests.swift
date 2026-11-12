import Foundation
import Testing
@testable import Caffy

/// Tests for the library-additions stage inside `EraPipeline`.
struct EraPipelineTests {
    /// Home in Sydney, a song added just before a weekend in Melbourne, then
    /// home again, so the trip is in the past.
    private static let tripWithAdditions = Scenario()
        .listen(to: "Tame Impala", genre: "Psychedelic")
        .live(at: .sydney, days: 30)
        .addToLibrary(["Road Song", "Highway Song"], by: "Courtney Barnett", genre: "Indie rock", plays: 8)
        .trip(to: .melbourne, nights: 2)
        .live(at: .sydney, days: 40)

    @Test func aPastTripGetsTheSongsAddedForIt() async throws {
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

        // The home era around it doesn't get them too.
        #expect(result.eras.filter { $0.draft.kind == .home }.allSatisfy { $0.addedSongs.isEmpty })
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
