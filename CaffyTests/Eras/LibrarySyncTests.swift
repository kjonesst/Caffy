import Foundation
import SwiftData
import Testing
@testable import Caffy

/// Tests for `LibrarySync`, which keeps saved eras in step with the photo
/// library. The library is faked; the database is in memory.
@MainActor
struct LibrarySyncTests {
    // MARK: - Fixtures

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try Self.makeContainer()
    }

    private static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Era.self, Moment.self, Place.self, CaffyPlaylist.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// A photo library: always the same photos, or no access at all.
    private struct FixedLibrary: PhotoLibraryReader {
        let items: [PhotoItem]?
        func photos() async -> [PhotoItem]? { items }
    }

    /// A photo library that counts reads and takes a moment to answer.
    private actor SlowLibrary: PhotoLibraryReader {
        let items: [PhotoItem]
        private(set) var reads = 0
        init(_ items: [PhotoItem]) { self.items = items }

        func photos() async -> [PhotoItem]? {
            reads += 1
            try? await Task.sleep(for: .milliseconds(50))
            return items
        }
    }

    /// Sydney, a weekend in Melbourne, Sydney again.
    private static let library = Scenario()
        .live(at: .sydney, days: 40)
        .trip(to: .melbourne, nights: 2)
        .live(at: .sydney, days: 30)

    /// Every photo in a scenario, as PhotoKit would report it.
    private static func photos(_ scenario: Scenario) -> [PhotoItem] {
        scenario.moments.flatMap { moment in
            moment.photoIDs.enumerated().map { index, id in
                PhotoItem(
                    id: id,
                    creationDate: moment.start.addingTimeInterval(Double(index) * 5 * 60),
                    coordinate: moment.coordinate,
                    aspectRatio: moment.coverAspectRatio
                )
            }
        }
    }

    private func makeSync(_ reader: any PhotoLibraryReader, in context: ModelContext? = nil, now: Date? = nil) -> LibrarySync {
        let now = now ?? Self.library.now
        return LibrarySync(
            context: context ?? self.context,
            reader: reader,
            listening: MockListeningSource(events: []),
            pipeline: EraPipeline(namer: SamplePlaceNamer(), sampler: SampleColorSampler(colors: [:])),
            calendar: Self.library.calendar,
            now: { now }
        )
    }

    private func eras(in context: ModelContext? = nil) throws -> [Era] {
        try (context ?? self.context).fetch(FetchDescriptor<Era>(sortBy: [SortDescriptor(\.startDate)]))
    }

    // MARK: - Access

    @Test func withoutAccessNothingChanges() async throws {
        try await SampleData.insert(into: context, now: Self.library.now, calendar: Self.library.calendar)
        let before = try eras().map(\.persistentModelID)

        let outcome = await makeSync(FixedLibrary(items: nil)).sync()
        #expect(outcome == .noAccess)
        #expect(try eras().map(\.persistentModelID) == before)
    }

    // MARK: - Syncing

    @Test func firstSyncReplacesTheSampleEras() async throws {
        try await SampleData.insert(into: context, now: Self.library.now, calendar: Self.library.calendar)

        let outcome = await makeSync(FixedLibrary(items: Self.photos(Self.library))).sync()
        guard case .synced(let eraCount, let momentCount) = outcome else {
            Issue.record("Expected a sync, got \(outcome)")
            return
        }
        let saved = try eras()
        #expect(saved.count == eraCount)
        #expect(saved.map(\.kind) == [.home, .trip])
        #expect(saved.allSatisfy { !($0.eraID ?? "sample-").hasPrefix("sample-") })
        let moments = try context.fetch(FetchDescriptor<Moment>())
        #expect(moments.count == momentCount)
        #expect(moments.allSatisfy { !($0.momentID ?? "sample-").hasPrefix("sample-") })
    }

    @Test func sampleErasLeaveNoTrace() async throws {
        // The frozen sample eras must not change how the real library is cut.
        try await SampleData.insert(into: context, now: Self.library.now, calendar: Self.library.calendar)
        await makeSync(FixedLibrary(items: Self.photos(Self.library))).sync()

        let clean = try Self.makeContainer()
        await makeSync(FixedLibrary(items: Self.photos(Self.library)), in: clean.mainContext).sync()

        func describe(_ eras: [Era]) -> [String] {
            eras.map { "\($0.eraID ?? "") \($0.title) \($0.moments.count) \($0.isFrozen)" }
        }
        #expect(describe(try eras()) == describe(try eras(in: clean.mainContext)))
    }

    @Test func syncingAgainKeepsTheSameEras() async throws {
        let sync = makeSync(FixedLibrary(items: Self.photos(Self.library)))
        await sync.sync()
        let first = try eras().map(\.persistentModelID)
        await sync.sync()
        #expect(try eras().map(\.persistentModelID) == first)
    }

    @Test func newPhotosJoinTheCurrentEra() async throws {
        await makeSync(FixedLibrary(items: Self.photos(Self.library))).sync()
        let current = try #require(try eras().first { $0.isCurrent })
        let count = current.moments.count

        let grown = Self.library.live(at: .sydney, days: 7)
        await makeSync(FixedLibrary(items: Self.photos(grown)), now: grown.now).sync()
        #expect(current.moments.count > count)
        #expect(try eras().filter(\.isCurrent).map(\.persistentModelID) == [current.persistentModelID])
    }

    @Test func emptyLibraryMeansNoEras() async throws {
        try await SampleData.insert(into: context, now: Self.library.now, calendar: Self.library.calendar)
        let outcome = await makeSync(FixedLibrary(items: [])).sync()
        #expect(outcome == .synced(eras: 0, moments: 0))
        #expect(try eras().isEmpty)
    }

    @Test func syncAskedForDuringASyncRunsAgain() async throws {
        let library = SlowLibrary(Self.photos(Self.library))
        let sync = makeSync(library)

        async let first = sync.sync()
        async let second = sync.sync()
        let outcomes = await [first, second]

        #expect(outcomes.contains(.queued))
        #expect(outcomes.contains { if case .synced = $0 { true } else { false } })
        // The running sync went round once more for the queued one.
        #expect(await library.reads == 2)
    }

    // MARK: - Frozen eras with no photos

    @Test func frozenErasWithNoPhotosDontHoldABoundary() {
        let scenario = Self.library
        let recent = scenario.now.addingTimeInterval(-20 * 24 * 60 * 60)
        // A frozen era from somewhere else (sample data), ending recently.
        let elsewhere = EraDraft(
            id: "sample-m0001", kind: .home, momentIDs: ["sample-m0001"],
            start: recent.addingTimeInterval(-60 * 24 * 60 * 60), end: recent,
            centre: nil, startReason: .firstMoment
        )
        let withStranger = EraBuilder.build(moments: scenario.moments, plays: [], frozen: [elsewhere], now: scenario.now, calendar: scenario.calendar)
        let alone = EraBuilder.build(moments: scenario.moments, plays: [], now: scenario.now, calendar: scenario.calendar)
        #expect(withStranger.drafts == alone.drafts)
    }
}
