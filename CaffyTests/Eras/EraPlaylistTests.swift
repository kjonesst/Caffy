import Foundation
import Testing
@testable import Caffy

/// Tests for `EraPlaylist`, which orders an era's songs by where they came from.
struct EraPlaylistTests {
    private static func song(_ id: String, _ evidence: SongEvidence, _ score: Double) -> EraSong {
        EraSong(song: Song(id: id, title: id, artist: "Artist"), evidence: evidence, score: score)
    }

    private static func ids(_ songs: [EraSong]) -> [String] { songs.map(\.song.id) }

    @Test func nearPlaysThenAdditionsThenLoosePlays() {
        let playlist = EraPlaylist.build(
            momentSongs: [
                [Self.song("a", .nearPlay, 1), Self.song("b", .nearPlay, 2)],
                [Self.song("c", .loosePlay, 5)]
            ],
            added: [Self.song("d", .libraryAdded, 2), Self.song("e", .libraryAdded, 3)],
            includeLoose: true
        )
        #expect(Self.ids(playlist) == ["b", "a", "e", "d", "c"])
        #expect(playlist.map(\.evidence) == [.nearPlay, .nearPlay, .libraryAdded, .libraryAdded, .loosePlay])
    }

    @Test func nearPlaysAddUpOverMoments() {
        let playlist = EraPlaylist.build(
            momentSongs: [[Self.song("a", .nearPlay, 1)], [Self.song("b", .nearPlay, 1.5)], [Self.song("a", .nearPlay, 1)]],
            added: []
        )
        #expect(Self.ids(playlist) == ["a", "b"])
        #expect(playlist.first?.score == 2)
    }

    @Test func duplicatesKeepTheirStrongestEvidence() {
        let playlist = EraPlaylist.build(
            momentSongs: [[Self.song("a", .loosePlay, 9)], [Self.song("a", .nearPlay, 1)], [Self.song("b", .loosePlay, 9)]],
            added: [Self.song("a", .libraryAdded, 5), Self.song("b", .libraryAdded, 1)],
            includeLoose: true
        )
        #expect(Self.ids(playlist) == ["a", "b"])
        #expect(playlist.map(\.evidence) == [.nearPlay, .libraryAdded])
    }

    @Test func loosePlaysOnlyWhenTurnedOn() {
        let moments = [[Self.song("a", .nearPlay, 1)], [Self.song("loose", .loosePlay, 3)]]
        #expect(Self.ids(EraPlaylist.build(momentSongs: moments, added: [])) == ["a"])
        #expect(Self.ids(EraPlaylist.build(momentSongs: moments, added: [], includeLoose: true)) == ["a", "loose"])
        #expect(!EraBuildConfig.standard.includeLoosePlaysInEraPlaylist)
    }

    @Test func tiesAreBrokenTheSameWayEveryTime() {
        let moments = [[Self.song("b", .nearPlay, 1), Self.song("a", .nearPlay, 1)]]
        let added = [Self.song("y", .libraryAdded, 1), Self.song("x", .libraryAdded, 1)]
        // The song seen first wins a tie.
        #expect(Self.ids(EraPlaylist.build(momentSongs: moments, added: added)) == ["b", "a", "y", "x"])
    }
}
