import Foundation
import SwiftData
import Testing
@testable import Caffy

/// Tests for `SampleData`: the generated year of sample eras the app shows
/// before PhotoKit and MusicKit are connected.
@MainActor
struct SampleDataTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(
            for: Era.self, Moment.self, Place.self, CaffyPlaylist.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private static let calendar = Scenario().calendar
    /// Mid-afternoon on 11 November 2026, Sydney time.
    private static let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 15))!

    private func eras() throws -> [Era] {
        try context.fetch(FetchDescriptor<Era>(sortBy: [SortDescriptor(\.startDate)]))
    }

    @Test func libraryEndsToday() throws {
        let library = SampleData.library(endingOn: Self.now, calendar: Self.calendar)
        #expect(library.cursor == Self.calendar.startOfDay(for: Self.now))
        let last = try #require(library.moments.last)
        #expect(last.end < Self.now)
        #expect(library.moments.allSatisfy { $0.id.hasPrefix("sample-") && $0.coverID.hasPrefix("sample-") })
    }

    @Test func sampleYearTellsItsStory() async throws {
        try await SampleData.insert(into: context, now: Self.now, calendar: Self.calendar)
        let saved = try eras()

        #expect(saved.map(\.kind) == [.home, .trip, .home, .home, .trip, .home, .trip])
        #expect(saved[1].title == "Four days in Hobart")
        #expect(saved[2].summary == "Chillout takes over from Classic rock.")
        #expect(saved[3].title == "New in Melbourne")
        #expect(saved[4].title.hasSuffix("in Sydney"))
        #expect(saved[5].title == "Back in Sydney")
        #expect(saved[6].title.hasSuffix("in Melbourne"))
        #expect(saved.allSatisfy { $0.eraID != nil && $0.playlist != nil })
    }

    @Test func newestHomeEraIsCurrentAndOldOnesAreFrozen() async throws {
        try await SampleData.insert(into: context, now: Self.now, calendar: Self.calendar)
        let homes = try eras().filter { $0.kind == .home }
        #expect(homes.last?.isCurrent == true)
        #expect(homes.dropLast().allSatisfy { $0.isFrozen })
    }

    @Test func neighbouringErasLookDifferent() async throws {
        try await SampleData.insert(into: context, now: Self.now, calendar: Self.calendar)
        let papers = try eras().map { RGBColor(hex: $0.palette.paperHex).oklab }
        for (previous, next) in zip(papers, papers.dropFirst()) {
            #expect(previous.distance(to: next) * 100 >= 12)
        }
    }

    @Test func songsHaveRealTitles() async throws {
        try await SampleData.insert(into: context, now: Self.now, calendar: Self.calendar)
        let songs = try eras().flatMap(\.songs)
        #expect(!songs.isEmpty)
        #expect(songs.allSatisfy { !$0.title.contains(" Track ") })
    }

    @Test func insertingIfNeededOnlyHappensOnce() async throws {
        try await SampleData.insertIfNeeded(into: context, now: Self.now, calendar: Self.calendar)
        let first = try eras().map(\.persistentModelID)
        try await SampleData.insertIfNeeded(into: context, now: Self.now.addingTimeInterval(86_400), calendar: Self.calendar)
        #expect(try eras().map(\.persistentModelID) == first)
    }

    @Test func oldHandWrittenSampleErasAreReplaced() async throws {
        let old = Era(title: "The Long Way Round", whenLabel: "2026", summary: "", startDate: Self.now, palette: .rust)
        context.insert(old)
        try context.save()

        try await SampleData.insertIfNeeded(into: context, now: Self.now, calendar: Self.calendar)
        let saved = try eras()
        #expect(saved.count == 7)
        #expect(saved.allSatisfy { $0.eraID != nil })
    }

    @Test func sameDaySameSampleEras() async throws {
        try await SampleData.insert(into: context, now: Self.now, calendar: Self.calendar)
        let first = try eras().map { [$0.title, $0.summary, $0.whenLabel, String($0.palette.paperHex)] }

        let other = try ModelContainer(
            for: Era.self, Moment.self, Place.self, CaffyPlaylist.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        try await SampleData.insert(into: other.mainContext, now: Self.now.addingTimeInterval(60), calendar: Self.calendar)
        let second = try other.mainContext.fetch(FetchDescriptor<Era>(sortBy: [SortDescriptor(\.startDate)]))
            .map { [$0.title, $0.summary, $0.whenLabel, String($0.palette.paperHex)] }
        #expect(first == second)
    }
}
