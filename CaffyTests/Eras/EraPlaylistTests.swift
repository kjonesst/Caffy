import Foundation
import Testing
@testable import Caffy

/// Tests for `EraPlaylist`, which orders an era's songs by where they came from.
struct EraPlaylistTests {
    private static func song(_ id: String, _ evidence: SongEvidence, _ score: Double) -> EraSong {
        EraSong(song: Song(id: id, title: id, artist: "Artist"), evidence: evidence, score: score)
    }

    private static func ids(_ songs: [EraSong]) -> [String] { songs.map(\.song.id) }

    /// A near play, observed or seeded-only.
    private static func near(_ id: String, _ score: Double = 1, observed: Bool?, title: String? = nil) -> EraSong {
        EraSong(song: Song(id: id, title: title ?? id, artist: "Artist"), evidence: .nearPlay, score: score, hasObservedPlay: observed)
    }

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

    @Test func thereIsNoCap() {
        let moments = (0..<155).map { [Self.song("near\($0)", .nearPlay, 1 + Double($0) / 1_000)] }
        let added = (0..<40).map { Self.song("added\($0)", .libraryAdded, 1) }
        let playlist = EraPlaylist.build(momentSongs: moments, added: added)
        #expect(playlist.count == 195)
        #expect(playlist.prefix(155).allSatisfy { $0.evidence == .nearPlay })
        #expect(playlist.suffix(40).allSatisfy { $0.evidence == .libraryAdded })
    }

    @Test func everySongOfABusyMomentIsKept() {
        let busy = (0..<12).map { Self.song("s\($0)", .nearPlay, Double(12 - $0)) }
        #expect(busy.count > EraBuildConfig.standard.maxSongsPerMoment)
        #expect(Self.ids(EraPlaylist.build(momentSongs: [busy], added: [])) == busy.map(\.song.id))
    }

    @Test func tiesAreBrokenTheSameWayEveryTime() {
        let moments = [[Self.song("b", .nearPlay, 1), Self.song("a", .nearPlay, 1)]]
        let added = [Self.song("y", .libraryAdded, 1), Self.song("x", .libraryAdded, 1)]
        // Near songs tie on title; additions on the song seen first.
        #expect(Self.ids(EraPlaylist.build(momentSongs: moments, added: added)) == ["a", "b", "y", "x"])
    }

    // MARK: - Evidence order

    @Test func songsNearMoreMomentsComeFirst() {
        let moments = [
            [Self.near("strong", 5, observed: true), Self.near("twice", 0.5, observed: false)],
            [Self.near("twice", 0.5, observed: false)]
        ]
        #expect(Self.ids(EraPlaylist.build(momentSongs: moments, added: [])) == ["twice", "strong"])
    }

    @Test func observedSongsComeBeforeSeededOnlyOnes() {
        let moments = [[Self.near("seeded", 5, observed: false), Self.near("observed", 1, observed: true)]]
        #expect(Self.ids(EraPlaylist.build(momentSongs: moments, added: [])) == ["observed", "seeded"])
    }

    @Test func thenScoreThenTitleThenID() {
        let moments = [[
            Self.near("c", 1, observed: true, title: "Same"),
            Self.near("b", 1, observed: true, title: "Same"),
            Self.near("z", 1, observed: true, title: "Alpha"),
            Self.near("high", 2, observed: true, title: "Zulu")
        ]]
        #expect(Self.ids(EraPlaylist.build(momentSongs: moments, added: [])) == ["high", "z", "b", "c"])
    }

    @Test func oneObservedPlayAnywhereMakesASongObserved() {
        let moments = [[Self.near("a", 1, observed: false)], [Self.near("a", 1, observed: true)], [Self.near("b", 1, observed: false)]]
        let evidence = EraPlaylist.nearEvidence(momentSongs: moments)
        #expect(evidence["a"] == EraPlaylist.NearEvidence(moments: 2, hasObservedOrUnknown: true))
        #expect(evidence["b"]?.isSeededOnly == true)
        #expect(evidence["a"]?.isSeededOnly == false)
    }

    @Test func unknownEvidenceIsNeverSeededOnly() {
        // Moments saved before plays were told apart.
        let moments = [[Self.near("old", 1, observed: nil), Self.near("observed", 2, observed: true)]]
        #expect(EraPlaylist.nearEvidence(momentSongs: moments)["old"]?.isSeededOnly == false)
        let playlist = EraPlaylist.build(momentSongs: moments, added: [], seededNeedCorroboration: true, corroborated: [])
        #expect(Self.ids(playlist) == ["observed", "old"])
    }

    // MARK: - Corroboration flag

    private static let flagMoments = [[
        Self.near("observed", 3, observed: true),
        Self.near("lonely", 2, observed: false),
        Self.near("newThen", 1, observed: false),
        Self.near("playedInEra", 1, observed: false, title: "p")
    ]]

    @Test func flagOffKeepsSeededOnlySongs() {
        #expect(!EraBuildConfig.standard.seededPlaysNeedCorroboration)
        let playlist = EraPlaylist.build(momentSongs: Self.flagMoments, added: [], corroborated: ["newThen"])
        #expect(Self.ids(playlist) == ["observed", "lonely", "newThen", "playedInEra"])
    }

    @Test func flagOnDropsOnlyUncorroboratedSeededOnlySongs() {
        let playlist = EraPlaylist.build(
            momentSongs: Self.flagMoments, added: [],
            seededNeedCorroboration: true, corroborated: ["newThen", "playedInEra"]
        )
        #expect(Self.ids(playlist) == ["observed", "newThen", "playedInEra"])
    }

    @Test func flagOnWithoutCorroborationFactsDropsNothing() {
        let playlist = EraPlaylist.build(momentSongs: Self.flagMoments, added: [], seededNeedCorroboration: true, corroborated: nil)
        #expect(playlist.count == 4)
    }

    @Test func corroboratedByDateAddedOrAnObservedPlayInTheEra() {
        let day: TimeInterval = 24 * 60 * 60
        let start = Date(timeIntervalSinceReferenceDate: 100 * day)
        let end = start.addingTimeInterval(30 * day)
        let draft = EraDraft(id: "era", kind: .home, momentIDs: ["m"], start: start, end: end, centre: nil, startReason: .firstMoment)
        let ids = ["lonely", "newThen", "playedInEra", "addedLongAgo", "observedAfter"]
        let matches = ["m": ids.map { Self.near($0, observed: false) }]
        func song(_ id: String) -> Song { Song(id: id, title: id, artist: "Artist") }
        func snapshot(_ id: String, added: Date) -> LibrarySongSnapshot {
            LibrarySongSnapshot(persistentID: 1, catalogID: id, title: id, artist: "Artist", dateAdded: added)
        }
        let library = [
            // In the lead-in, so it was new then.
            snapshot("newThen", added: start.addingTimeInterval(-day)),
            snapshot("addedLongAgo", added: start.addingTimeInterval(-60 * day))
        ]
        let plays = [
            ListeningEvent(song: song("playedInEra"), interval: DateInterval(start: start.addingTimeInterval(5 * day), duration: 0)),
            ListeningEvent(song: song("observedAfter"), interval: DateInterval(start: end.addingTimeInterval(day), duration: 0)),
            ListeningEvent(song: song("lonely"), interval: DateInterval(start: start.addingTimeInterval(day), duration: 0), isSeeded: true)
        ]
        let corroborated = EraPipeline.corroboratedSongIDs(
            for: [draft], matches: matches, plays: plays, library: library, now: end, config: .standard
        )
        #expect(corroborated["era"] == ["newThen", "playedInEra"])
    }
}
