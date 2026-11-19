import Foundation
import SwiftData
import Testing
@testable import Caffy

/// `PlaylistLedger` keeps each era's Apple Music playlist link, and gets it
/// back after the derived store is rebuilt.
@MainActor
struct PlaylistLedgerTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private var ledger: PlaylistLedger { PlaylistLedger(context: context) }

    private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let link = PlaylistLink(
        playlistID: "p.1", url: URL(string: "https://music.example/p.1"), name: "Spring at home",
        songIDs: ["1", "2"], publishedAt: start
    )

    init() throws {
        container = try CaffyStore.makeContainer(inMemory: true)
    }

    @discardableResult
    private func insertEra(_ eraID: String) -> Era {
        let era = Era(title: "Spring at home", whenLabel: "2026", summary: "", startDate: Self.start, palette: .rust)
        era.eraID = eraID
        era.playlist = CaffyPlaylist(name: "Spring at home", lastUpdated: Self.start)
        context.insert(era)
        return era
    }

    private func records() throws -> [PublishedPlaylistRecord] {
        try context.fetch(FetchDescriptor<PublishedPlaylistRecord>())
    }

    @Test func savingLinksTheErasPlaylistAndKeepsARecord() throws {
        let era = insertEra("e1")

        try ledger.save(Self.link, forEraID: "e1")

        #expect(era.playlist?.link == Self.link)
        #expect(era.playlist?.appleMusicURL == Self.link.url)
        #expect(try records().map(\.link) == [Self.link])
        #expect(try ledger.link(forEraID: "e1") == Self.link)
    }

    @Test func savingAgainUpdatesTheOneRecord() throws {
        insertEra("e1")
        try ledger.save(Self.link, forEraID: "e1")
        var newer = Self.link
        newer.songIDs = ["2", "3"]

        try ledger.save(newer, forEraID: "e1")

        #expect(try records().map(\.link) == [newer])
    }

    @Test func otherErasKeepTheirOwnLinks() throws {
        let first = insertEra("e1")
        let second = insertEra("e2")

        try ledger.save(Self.link, forEraID: "e1")

        #expect(first.playlist?.appleMusicID == "p.1")
        #expect(second.playlist?.appleMusicID == nil)
        #expect(try ledger.link(forEraID: "e2") == nil)
    }

    @Test func aRebuiltEraGetsItsLinkBack() throws {
        let era = insertEra("e1")
        try ledger.save(Self.link, forEraID: "e1")

        // Clearing the derived store: the era and its playlist go, the record stays.
        context.delete(era)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<CaffyPlaylist>()).isEmpty)
        let rebuilt = insertEra("e1")
        try context.save()
        #expect(rebuilt.playlist?.appleMusicID == nil)

        #expect(try ledger.relinkPlaylists() == 1)
        #expect(rebuilt.playlist?.link == Self.link)
        #expect(try ledger.relinkPlaylists() == 0)
    }

    @Test func relinkingWithoutRecordsChangesNothing() throws {
        let era = insertEra("e1")
        try context.save()

        #expect(try ledger.relinkPlaylists() == 0)
        #expect(era.playlist?.appleMusicID == nil)
    }

    /// The record joins the listening history store, which already exists
    /// on devices. Opening that store with the new model must keep its data.
    @Test func anExistingHistoryStoreOpensWithTheNewModel() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ledger-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let before: [any PersistentModel.Type] = [LibrarySongState.self, RecordedPlay.self, ListeningCheck.self]
        do {
            let old = try ModelContainer(for: Schema(before), configurations: ModelConfiguration(schema: Schema(before), url: url))
            old.mainContext.insert(ListeningCheck(at: Self.start, songCount: 3, newExactPlays: 1, newEstimatedPlays: 0))
            try old.mainContext.save()
        }

        let now = Schema(ListeningHistoryStore.models)
        let updated = try ModelContainer(for: now, configurations: ModelConfiguration(schema: now, url: url))
        let context = updated.mainContext
        #expect(try context.fetch(FetchDescriptor<ListeningCheck>()).map(\.songCount) == [3])
        context.insert(PublishedPlaylistRecord(eraID: "e1", link: Self.link))
        try context.save()
        #expect(try context.fetch(FetchDescriptor<PublishedPlaylistRecord>()).count == 1)
    }
}
