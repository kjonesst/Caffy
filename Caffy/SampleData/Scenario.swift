import Foundation

/// Builds a made-up stretch of someone's life (photo moments and song plays)
/// one step at a time: the app's sample data, and the era pipeline's test
/// fixtures.
///
/// Each step returns a new scenario, so steps chain:
///
///     let weekend = Scenario()
///         .listen(to: "Tame Impala", genre: "Psychedelic")
///         .live(at: .sydney, days: 21)
///         .trip(to: .melbourne, nights: 2)
///         .live(at: .sydney, days: 21)
///
/// Everything is deterministic: the same steps and seed always give the same
/// moments and plays. Days are calendar days in `calendar`'s time zone
/// (Sydney by default), so daylight saving is handled like on a real phone.
nonisolated struct Scenario: Sendable {
    /// One artist the user is listening to, and how much.
    struct Habit: Sendable {
        let artist: String
        let genre: String
        let perDay: Int
        /// The artist's song titles. Empty gives three generic tracks.
        var titles: [String] = []

        var trackCount: Int { titles.isEmpty ? 3 : titles.count }

        func title(of track: Int) -> String {
            titles.isEmpty ? "\(artist) Track \(track)" : titles[track - 1]
        }
    }

    let calendar: Calendar
    /// Midnight at the start of the scenario.
    let start: Date
    /// Midnight at the start of the next day to fill in. Also a good `now`.
    private(set) var cursor: Date
    /// Every moment so far, oldest first.
    private(set) var moments: [PhotoMoment] = []
    /// Every play so far, oldest first.
    private(set) var plays: [ListeningEvent] = []
    /// The music library: every song added so far, oldest first.
    private(set) var library: [LibrarySongSnapshot] = []

    private var rng: SplitMix64
    private var habits: [Habit] = []
    private var photosHaveLocation = true
    /// Put in front of every moment and photo id.
    private let idPrefix: String

    static let sydneyTime = TimeZone(identifier: "Australia/Sydney")!

    init(year: Int = 2026, month: Int = 2, day: Int = 2, timeZone: TimeZone = sydneyTime, seed: UInt64 = 1) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.init(startingOn: calendar.date(from: DateComponents(year: year, month: month, day: day))!, calendar: calendar, seed: seed)
    }

    /// A scenario starting at midnight on `date`'s day in `calendar`.
    /// `idPrefix` goes in front of every moment and photo id, so sample
    /// photos can never be mistaken for real PhotoKit ones.
    init(startingOn date: Date, calendar: Calendar, seed: UInt64 = 1, idPrefix: String = "") {
        self.calendar = calendar
        start = calendar.startOfDay(for: date)
        cursor = start
        rng = SplitMix64(seed: seed)
        self.idPrefix = idPrefix
    }

    /// The time to run the pipeline at: the end of the last filled-in day.
    var now: Date { cursor }

    var listeningSource: MockListeningSource { MockListeningSource(events: plays) }

    // MARK: - Steps

    /// Everyday life at `place`. Photos are spread evenly: 3 a week means a
    /// moment on every second or third day; more than 7 means several a day.
    func live(at place: SamplePlace, days: Int, photosPerWeek: Int = 3) -> Scenario {
        var next = self
        for index in 0..<days {
            let count = (index + 1) * photosPerWeek / 7 - index * photosPerWeek / 7
            next.fillDay(at: place, moments: count, hours: 8...22)
        }
        return next
    }

    /// An overnight trip to `place`: leaves in the afternoon of the current
    /// day and comes back in the morning `nights` days later.
    func trip(to place: SamplePlace, nights: Int, photosPerDay: Int = 3) -> Scenario {
        precondition(nights >= 1, "A trip has at least one night; use dayTrip for none")
        var next = self
        for night in 0...nights {
            let hours = switch night {
            case 0: 13...22
            case nights: 8...12
            default: 8...22
            }
            next.fillDay(at: place, moments: photosPerDay, hours: hours)
        }
        return next
    }

    /// A day out at `place`, back home the same evening.
    func dayTrip(to place: SamplePlace, photos: Int = 3) -> Scenario {
        var next = self
        next.fillDay(at: place, moments: photos, hours: 10...17)
        return next
    }

    /// Days with no photos. Listening carries on unless `silence()` came first.
    func gap(days: Int) -> Scenario {
        var next = self
        for _ in 0..<days {
            next.fillDay(at: nil, moments: 0, hours: 8...22)
        }
        return next
    }

    /// Adds songs to the music library around noon on the current day (just
    /// before a trip that starts today), each later played `plays` times.
    /// `album` puts them all on one album: a whole album added at once.
    func addToLibrary(_ titles: [String], by artist: String, genre: String, plays: Int = 6, album: String? = nil) -> Scenario {
        var next = self
        let albumID = album.map { _ in UInt64(900_000 + library.count) }
        for (index, title) in titles.enumerated() {
            next.addSong(title: title, artist: artist, genre: genre, plays: max(0, plays - index), album: album, albumID: albumID, minute: index)
        }
        return next
    }

    /// A bulk import on the current day (joining Apple Music, say): `count`
    /// songs added at once, most of them hardly played.
    func bulkImport(_ count: Int, by artist: String = "Various Artists", genre: String = "Pop") -> Scenario {
        var next = self
        for index in 0..<count {
            next.addSong(title: "Imported Song \(index + 1)", artist: artist, genre: genre, plays: index % 4, album: nil, albumID: nil, minute: index)
        }
        return next
    }

    /// From now on, the user listens to this artist only.
    func listen(to artist: String, genre: String, perDay: Int = 8, titles: [String] = []) -> Scenario {
        var next = self
        next.habits = [Habit(artist: artist, genre: genre, perDay: perDay, titles: titles)]
        return next
    }

    /// From now on, the user also listens to this artist.
    func alsoListen(to artist: String, genre: String, perDay: Int = 4, titles: [String] = []) -> Scenario {
        var next = self
        next.habits.append(Habit(artist: artist, genre: genre, perDay: perDay, titles: titles))
        return next
    }

    /// From now on, no listening at all.
    func silence() -> Scenario {
        var next = self
        next.habits = []
        return next
    }

    /// From now on, photos have no location (screenshots, location turned off).
    func unlocated() -> Scenario {
        var next = self
        next.photosHaveLocation = false
        return next
    }

    /// From now on, photos have a location again.
    func located() -> Scenario {
        var next = self
        next.photosHaveLocation = true
        return next
    }

    // MARK: - Lookups

    /// The fixture song id for an artist's `track`th song (1, 2 or 3).
    static func songID(artist: String, track: Int) -> String {
        let slug = artist.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return "fx-\(String(slug))-\(track)"
    }

    /// The local calendar day (midnight) a date falls on.
    func day(of date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    // MARK: - Filling in a day

    private mutating func fillDay(at place: SamplePlace?, moments count: Int, hours: ClosedRange<Int>) {
        if let place, count > 0 {
            addMoments(count, at: place, hours: hours)
        }
        addPlays()
        cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
    }

    /// Adds `count` moments on the current day. The hours are split into equal
    /// slots and each moment lands somewhere in its own slot, so moments on
    /// the same day never overlap.
    private mutating func addMoments(_ count: Int, at place: SamplePlace, hours: ClosedRange<Int>) {
        let first = time(hour: hours.lowerBound)
        let last = time(hour: hours.upperBound)
        let slot = last.timeIntervalSince(first) / Double(count)

        for index in 0..<count {
            // Keep the moment's last photo inside its slot.
            let photoCount = rng.int(in: 1...3)
            let photoSpacing: TimeInterval = 5 * 60
            let latestStart = max(0, slot - Double(photoCount - 1) * photoSpacing - 60)
            let momentStart = first
                .addingTimeInterval(Double(index) * slot)
                .addingTimeInterval(rng.double(in: 0...latestStart))
                .rounded(toSeconds: 1)

            let id = idPrefix + String(format: "m%04d", moments.count + 1)
            let photoIDs = (1...photoCount).map { "\(id)-p\($0)" }
            let coordinate = photosHaveLocation
                ? place.offset(
                    north: rng.double(in: -SamplePlace.spread...SamplePlace.spread),
                    east: rng.double(in: -SamplePlace.spread...SamplePlace.spread)
                )
                : nil

            moments.append(PhotoMoment(
                id: id,
                start: momentStart,
                end: momentStart.addingTimeInterval(Double(photoCount - 1) * photoSpacing),
                photoIDs: photoIDs,
                coverID: photoIDs[photoCount / 2],
                coverAspectRatio: rng.pick([0.75, 1, 1.5]),
                coordinate: coordinate
            ))
        }
    }

    private mutating func addSong(title: String, artist: String, genre: String, plays: Int, album: String?, albumID: UInt64?, minute: Int) {
        let id = UInt64(100_000 + library.count + 1)
        library.append(LibrarySongSnapshot(
            persistentID: id,
            catalogID: nil,
            title: title,
            artist: artist,
            genre: genre,
            duration: 240,
            playCount: plays,
            dateAdded: time(hour: 12).addingTimeInterval(Double(minute) * 60),
            albumID: albumID,
            albumTitle: album
        ))
    }

    /// Adds each habit's plays for the current day, spread between 07:00 and
    /// 23:00 the same way as moments, then keeps `plays` in time order.
    private mutating func addPlays() {
        guard !habits.isEmpty else { return }
        let first = time(hour: 7)
        let last = time(hour: 23)
        var today: [ListeningEvent] = []

        for habit in habits where habit.perDay > 0 {
            let slot = last.timeIntervalSince(first) / Double(habit.perDay)
            for index in 0..<habit.perDay {
                let track = rng.int(in: 1...habit.trackCount)
                let length = rng.double(in: 180...300).rounded()
                let playStart = first
                    .addingTimeInterval(Double(index) * slot)
                    .addingTimeInterval(rng.double(in: 0...max(0, slot - length)))
                    .rounded(toSeconds: 1)
                let song = Song(
                    id: Self.songID(artist: habit.artist, track: track),
                    title: habit.title(of: track),
                    artist: habit.artist,
                    genre: habit.genre
                )
                today.append(ListeningEvent(song: song, interval: DateInterval(start: playStart, duration: length)))
            }
        }
        today.sort { ($0.interval.start, $0.song.id) < ($1.interval.start, $1.song.id) }
        plays.append(contentsOf: today)
    }

    /// `hour` o'clock on the current day, in the scenario's time zone.
    private func time(hour: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: cursor)!
    }
}

nonisolated private extension Date {
    /// Drops fractions of a second, so fixture dates print and compare cleanly.
    func rounded(toSeconds seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate / seconds).rounded(.down) * seconds)
    }
}
