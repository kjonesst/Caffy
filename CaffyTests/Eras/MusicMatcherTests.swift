import Foundation
import Testing
@testable import Caffy

/// Tests for `MusicMatcher`, which attaches the songs played around each
/// moment's time to that moment.
struct MusicMatcherTests {
    // MARK: - Fixtures

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Scenario.sydneyTime
        return calendar
    }()

    /// 12:00 on Monday 2 February 2026, Sydney time. Every fixture time is
    /// given in minutes from here.
    private static let noon = calendar.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: 12))!

    private static func at(_ minutes: Double) -> Date {
        noon.addingTimeInterval(minutes * 60)
    }

    private static func moment(_ id: String = "m", at minutes: Double = 0, lasting length: Double = 0) -> PhotoMoment {
        PhotoMoment(
            id: id,
            start: at(minutes),
            end: at(minutes + length),
            photoIDs: [id],
            coverID: id,
            coverAspectRatio: 1,
            coordinate: nil
        )
    }

    private static func play(_ songID: String, at minutes: Double, lasting length: Double = 4, estimated: Bool = false) -> ListeningEvent {
        ListeningEvent(
            song: Song(id: songID, title: "Song \(songID)", artist: "Artist \(songID)"),
            interval: DateInterval(start: at(minutes), duration: length * 60),
            isEstimated: estimated
        )
    }

    private static func match(
        _ moments: [PhotoMoment],
        _ plays: [ListeningEvent],
        config: EraBuildConfig = .standard
    ) -> [MatchedMoment] {
        MusicMatcher.match(moments, with: plays, calendar: calendar, config: config)
    }

    /// The songs matched to a single moment.
    private static func songs(for moment: PhotoMoment, _ plays: [ListeningEvent], config: EraBuildConfig = .standard) -> [SongMatch] {
        match([moment], plays, config: config).first?.songs ?? []
    }

    private static let noFallback: EraBuildConfig = {
        var config = EraBuildConfig()
        config.dayFallbackMatching = false
        return config
    }()

    /// The decayed weight summed from `near` to `far` minutes outside the
    /// window, worked out independently of the matcher.
    private static func decayedMinutes(from near: Double, to far: Double, halfLife: Double = 30) -> Double {
        halfLife / log(2.0) * (pow(2, -near / halfLife) - pow(2, -far / halfLife))
    }

    private static func close(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 1e-9
    }

    // MARK: - Basics

    @Test func noMomentsGiveNoMatches() {
        #expect(Self.match([], [Self.play("a", at: 0)]).isEmpty)
    }

    @Test func momentWithNoPlaysHasNoSongs() throws {
        let matched = Self.match([Self.moment()], [])
        let only = try #require(matched.first)
        #expect(matched.count == 1)
        #expect(only.songs.isEmpty)
        #expect(only.moment == Self.moment())
    }

    @Test func playDuringTheMomentCountsFully() throws {
        let songs = Self.songs(for: Self.moment(lasting: 10), [Self.play("a", at: 2)])
        let song = try #require(songs.first)
        #expect(songs.count == 1)
        #expect(song.song.id == "a")
        #expect(Self.close(song.score, 1))
        #expect(song.playCount == 1)
        #expect(!song.isLoose)
    }

    // MARK: - The window

    @Test func playsAnywhereInsideTheWindowCountFully() {
        let moment = Self.moment(lasting: 10)
        // From 45 minutes before the first photo to 30 minutes after the last.
        let before = Self.songs(for: moment, [Self.play("a", at: -45)])
        let after = Self.songs(for: moment, [Self.play("a", at: 36)])
        #expect(Self.close(before.first?.score ?? 0, 1))
        #expect(Self.close(after.first?.score ?? 0, 1))
    }

    @Test func weightHalvesEveryHalfLifeOutsideTheWindow() {
        let window = DateInterval(start: Self.at(-45), end: Self.at(30))
        func weight(at minutes: Double) -> Double {
            MusicMatcher.weight(of: DateInterval(start: Self.at(minutes), duration: 0), around: window, config: .standard)
        }
        #expect(Self.close(weight(at: 0), 1))
        #expect(Self.close(weight(at: -75), 0.5))
        #expect(Self.close(weight(at: -105), 0.25))
        #expect(Self.close(weight(at: 60), 0.5))
    }

    @Test func playsBeyondTheCutoffDontCount() {
        let moment = Self.moment()
        // The window starts at −45; the cutoff is two hours beyond that.
        let justInside = Self.songs(for: moment, [Self.play("a", at: -45 - 119, lasting: 0)], config: Self.noFallback)
        let justOutside = Self.songs(for: moment, [Self.play("a", at: -45 - 121, lasting: 0)], config: Self.noFallback)
        #expect(justInside.count == 1)
        #expect(Self.close(justInside.first?.score ?? 0, pow(2, -119.0 / 30)))
        #expect(justOutside.isEmpty)
    }

    @Test func playOverTheWindowEdgeCountsPartly() throws {
        // Two minutes outside the window and two inside.
        let song = try #require(Self.songs(for: Self.moment(), [Self.play("a", at: -47)]).first)
        let expected = (2 + Self.decayedMinutes(from: 0, to: 2)) / 4
        #expect(Self.close(song.score, expected))
        #expect(song.score < 1 && song.score > 0.95)
    }

    // MARK: - Estimated plays

    @Test func estimatedPlayCoveringOnlyTheWindowCountsFully() {
        let song = Self.songs(for: Self.moment(), [Self.play("a", at: -45, lasting: 75, estimated: true)]).first
        #expect(Self.close(song?.score ?? 0, 1))
    }

    @Test func estimatedPlayCountsByHowMuchOfItIsNearTheMoment() throws {
        // A 150-minute estimate: 75 minutes in the window, 75 after it.
        let song = try #require(Self.songs(for: Self.moment(), [Self.play("a", at: -45, lasting: 150, estimated: true)]).first)
        let expected = (75 + Self.decayedMinutes(from: 0, to: 75)) / 150
        #expect(Self.close(song.score, expected))
    }

    @Test func vaguerEstimatesCountLess() throws {
        let moment = Self.moment()
        let exact = try #require(Self.songs(for: moment, [Self.play("a", at: 0)]).first)
        let vague = try #require(Self.songs(for: moment, [Self.play("a", at: -120, lasting: 240, estimated: true)]).first)
        let vaguer = try #require(Self.songs(for: moment, [Self.play("a", at: -360, lasting: 720, estimated: true)]).first)
        #expect(exact.score > vague.score)
        #expect(vague.score > vaguer.score)
    }

    @Test func longPlayStartingFarEarlierIsFound() throws {
        // A ten-hour estimate starting nine hours before the moment.
        let song = try #require(Self.songs(for: Self.moment(), [Self.play("a", at: -540, lasting: 600, estimated: true)], config: Self.noFallback).first)
        #expect(!song.isLoose)
        #expect(song.score > 0)
    }

    // MARK: - Ranking

    @Test func repeatedSongAddsUpAndRanksFirst() throws {
        let songs = Self.songs(for: Self.moment(), [
            Self.play("b", at: -10),
            Self.play("a", at: -20),
            Self.play("a", at: 5)
        ])
        #expect(songs.map(\.song.id) == ["a", "b"])
        let first = try #require(songs.first)
        #expect(Self.close(first.score, 2))
        #expect(first.playCount == 2)
    }

    @Test func tiesAreBrokenBySongID() {
        let songs = Self.songs(for: Self.moment(), [
            Self.play("c", at: 0),
            Self.play("a", at: 5),
            Self.play("b", at: 10)
        ])
        #expect(songs.map(\.song.id) == ["a", "b", "c"])
    }

    @Test func closerPlaysRankHigher() {
        let songs = Self.songs(for: Self.moment(), [
            Self.play("far", at: -100, lasting: 0),
            Self.play("near", at: -10, lasting: 0)
        ])
        #expect(songs.map(\.song.id) == ["near", "far"])
    }

    @Test func songsAreCappedPerMoment() {
        var config = EraBuildConfig()
        config.maxSongsPerMoment = 2
        let songs = Self.songs(for: Self.moment(), [
            Self.play("a", at: 0),
            Self.play("b", at: 5),
            Self.play("b", at: 10),
            Self.play("c", at: 15)
        ], config: config)
        #expect(songs.map(\.song.id) == ["b", "a"])
    }

    @Test func duplicatePlaysCountOnce() throws {
        let play = Self.play("a", at: 0)
        let song = try #require(Self.songs(for: Self.moment(), [play, play]).first)
        #expect(song.playCount == 1)
        #expect(Self.close(song.score, 1))
    }

    // MARK: - Same-day fallback

    @Test func quietMomentFallsBackToThatDaysSongs() throws {
        // A moment at 20:00, a play at 01:00 that day, and one at 23:00 the
        // day before.
        let songs = Self.songs(for: Self.moment(at: 8 * 60), [
            Self.play("yesterday", at: -13 * 60),
            Self.play("early", at: -11 * 60)
        ])
        let song = try #require(songs.first)
        #expect(songs.map(\.song.id) == ["early"])
        #expect(song.isLoose)
        #expect(song.score == 1)
    }

    @Test func fallbackCanBeTurnedOff() {
        let songs = Self.songs(for: Self.moment(at: 8 * 60), [Self.play("early", at: -11 * 60)], config: Self.noFallback)
        #expect(songs.isEmpty)
    }

    @Test func fallbackOnlyWhenNothingIsNearby() {
        let songs = Self.songs(for: Self.moment(at: 8 * 60), [
            Self.play("early", at: -11 * 60),
            Self.play("near", at: 8 * 60)
        ])
        #expect(songs.map(\.song.id) == ["near"])
        #expect(songs.allSatisfy { !$0.isLoose })
    }

    @Test func fallbackUsesTheLocalDay() {
        // A moment at 00:30: the play at 19:50 the evening before is on a
        // different day, and too far away for the window to reach.
        let earlyMoment = Self.moment(at: 12.5 * 60)
        let lateLastNight = Self.play("late", at: 12.5 * 60 - 4 * 60 - 40)
        #expect(Self.songs(for: earlyMoment, [lateLastNight]).isEmpty)
    }

    // MARK: - Ordering and determinism

    @Test func momentsComeBackOldestFirstWhateverTheInputOrder() {
        let moments = [Self.moment("c", at: 300), Self.moment("a", at: 0), Self.moment("b", at: 120)]
        let plays = [Self.play("x", at: 0), Self.play("y", at: 120), Self.play("z", at: 300), Self.play("x", at: 310)]

        let forward = Self.match(moments, plays)
        let shuffled = Self.match(moments.reversed(), plays.reversed())
        #expect(forward.map(\.id) == ["a", "b", "c"])
        #expect(forward == shuffled)
    }

    @Test func aPlayCanBelongToNeighbouringMoments() {
        // Moments an hour apart share the play between them.
        let matched = Self.match(
            [Self.moment("a", at: 0), Self.moment("b", at: 60)],
            [Self.play("shared", at: 25)]
        )
        #expect(matched.map { $0.songs.map(\.song.id) } == [["shared"], ["shared"]])
    }

    // MARK: - Scenarios

    @Test func tripMomentsGetTheTripsSoundtrack() throws {
        let beforeTrip = Scenario()
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 14)
        let afterTrip = beforeTrip
            .listen(to: "Fred again..", genre: "Electronic")
            .trip(to: .melbourne, nights: 2)
        let scenario = afterTrip
            .listen(to: "Tame Impala", genre: "Psychedelic")
            .live(at: .sydney, days: 7)

        let matched = MusicMatcher.match(scenario.moments, with: scenario.plays, calendar: scenario.calendar)
        let homeBefore = matched.prefix(beforeTrip.moments.count)
        let trip = matched[beforeTrip.moments.count..<afterTrip.moments.count]
        let homeAfter = matched.suffix(from: afterTrip.moments.count)

        #expect(matched.allSatisfy { !$0.songs.isEmpty })
        #expect(trip.allSatisfy { $0.songs.allSatisfy { $0.song.artist == "Fred again.." } })
        #expect(homeBefore.allSatisfy { $0.songs.allSatisfy { $0.song.artist == "Tame Impala" } })
        #expect(homeAfter.allSatisfy { $0.songs.allSatisfy { $0.song.artist == "Tame Impala" } })
    }

    @Test func silentStretchHasNoSongs() {
        let scenario = Scenario()
            .live(at: .sydney, days: 14)
        let matched = MusicMatcher.match(scenario.moments, with: scenario.plays, calendar: scenario.calendar)
        #expect(!matched.isEmpty)
        #expect(matched.allSatisfy { $0.songs.isEmpty })
    }

    // MARK: - Performance

    @Test func matchesAThousandMomentsQuickly() {
        // About 250 days: a moment every 6 hours and a play every 7.5 minutes.
        let moments = (0..<1_000).map { Self.moment("m\($0)", at: Double($0) * 360, lasting: 10) }
        let plays = (0..<50_000).map { Self.play("s\($0 % 400)", at: Double($0) * 7.5) }

        var matched: [MatchedMoment] = []
        let elapsed = ContinuousClock().measure {
            matched = Self.match(moments, plays)
        }
        #expect(matched.count == 1_000)
        #expect(matched.allSatisfy { !$0.songs.isEmpty })
        // About 0.2 s on its own in a Debug build. Tests run in parallel and
        // can be several times slower, so this only catches real regressions.
        #expect(elapsed < .seconds(2))
    }
}
