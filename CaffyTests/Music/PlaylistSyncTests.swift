import Foundation
import Testing
@testable import Caffy

/// `PlaylistSync` decides what to write to the library, and writes only that.
struct PlaylistSyncTests {
    private let publisher = FakePlaylistPublisher()
    private var sync: PlaylistSync { PlaylistSync(publisher: publisher) }
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let later = Date(timeIntervalSinceReferenceDate: 800_100_000)

    private func publish(_ ids: [String], name: String = "Spring", link: PlaylistLink?, at date: Date? = nil) async throws -> PlaylistPublishOutcome {
        try await sync.publish(name: name, description: nil, songIDs: ids, link: link, now: date ?? now)
    }

    @Test func createsAPlaylistWhenThereIsNoLink() async throws {
        let outcome = try await publish(["1", "2"], link: nil)

        guard case .created(let link) = outcome else { Issue.record("Expected created, got \(outcome)"); return }
        #expect(link.name == "Spring")
        #expect(link.songIDs == ["1", "2"])
        #expect(link.url != nil)
        #expect(link.publishedAt == now)
        #expect(await publisher.writes == [.create(name: "Spring", catalogIDs: ["1", "2"])])
    }

    @Test func makesNoPlaylistWithoutSongs() async throws {
        let outcome = try await publish([], link: nil)

        #expect(outcome == .nothingToPublish)
        #expect(await publisher.calls.isEmpty)
    }

    @Test func writesNothingWhenNothingChanged() async throws {
        let link = try #require(try await publish(["1", "2"], link: nil).link)

        let outcome = try await publish(["1", "2"], link: link, at: later)

        #expect(outcome == .unchanged(link))
        #expect(await publisher.writes.count == 1)
    }

    @Test func replacesTracksWhenSongsChange() async throws {
        let link = try #require(try await publish(["1", "2"], link: nil).link)

        let outcome = try await publish(["2", "3", "1"], link: link, at: later)

        guard case .updated(let updated, let renamed, let replaced) = outcome else { Issue.record("Expected updated, got \(outcome)"); return }
        #expect(!renamed && replaced)
        #expect(updated.songIDs == ["2", "3", "1"])
        #expect(updated.playlistID == link.playlistID)
        #expect(updated.publishedAt == later)
        #expect(await publisher.writes.last == .replaceTracks(id: link.playlistID, catalogIDs: ["2", "3", "1"]))
    }

    @Test func aNewOrderAloneCountsAsAChange() async throws {
        let link = try #require(try await publish(["1", "2"], link: nil).link)

        let outcome = try await publish(["2", "1"], link: link)

        #expect(outcome.link?.songIDs == ["2", "1"])
    }

    @Test func renamesWithoutTouchingTracks() async throws {
        let link = try #require(try await publish(["1"], link: nil).link)

        let outcome = try await publish(["1"], name: "Spring at home", link: link)

        guard case .updated(let updated, let renamed, let replaced) = outcome else { Issue.record("Expected updated, got \(outcome)"); return }
        #expect(renamed && !replaced)
        #expect(updated.name == "Spring at home")
        #expect(await publisher.writes.last == .rename(id: link.playlistID, name: "Spring at home"))
    }

    @Test func renamesAndReplacesTogether() async throws {
        let link = try #require(try await publish(["1"], link: nil).link)

        let outcome = try await publish(["1", "2"], name: "Spring at home", link: link)

        guard case .updated(_, let renamed, let replaced) = outcome else { Issue.record("Expected updated, got \(outcome)"); return }
        #expect(renamed && replaced)
        #expect(await publisher.writes.count == 3)
    }

    @Test func aDeletedPlaylistIsReportedNotMadeAgain() async throws {
        let link = try #require(try await publish(["1"], link: nil).link)
        await publisher.delete(link.playlistID)

        let outcome = try await publish(["1", "2"], link: link)

        #expect(outcome == .missing(link))
        #expect(outcome.link == nil)
        #expect(await publisher.writes.count == 1)
    }

    @Test func aLinkedPlaylistCanBeEmptied() async throws {
        let link = try #require(try await publish(["1"], link: nil).link)

        let outcome = try await publish([], link: link)

        #expect(outcome.link?.songIDs == [])
        #expect(await publisher.writes.last == .replaceTracks(id: link.playlistID, catalogIDs: []))
    }
}
