import Foundation
import SwiftData

/// Fills the database with example eras, moments, and playlists so the app
/// has something to show before PhotoKit and MusicKit are connected.
///
/// Nothing here is written by hand: a made-up year of photos and listening
/// (`library(endingOn:calendar:)`) goes through the real era pipeline and
/// `EraStore`, exactly as a real library will. The year always ends today,
/// so the newest era is the current one.
enum SampleData {
    /// How many days the sample library covers, ending today.
    static let libraryDays = 358

    /// Put in front of every sample moment and photo id, so they're never
    /// mistaken for real PhotoKit identifiers.
    nonisolated static let idPrefix = "sample-"

    /// A year in the life, ending on `now`'s day:
    ///
    /// 1. Sydney with classic rock (after a bulk import into the library),
    ///    and four nights in Hobart, with two folk songs added just before.
    /// 2. Chillout takes over.
    /// 3. A move to Melbourne with drum & bass, an album added whole, and a
    ///    weekend back in Sydney.
    /// 4. Back in Sydney with trance, a day trip to Wollongong and a
    ///    weekend in Melbourne, up to today.
    ///
    /// The same `now` day and calendar always give the same library.
    static func library(endingOn now: Date, calendar: Calendar) -> Scenario {
        let start = calendar.date(byAdding: .day, value: -libraryDays, to: calendar.startOfDay(for: now))!
        return Scenario(startingOn: start, calendar: calendar, seed: 2026, idPrefix: idPrefix)
            .bulkImport(60)
            .listen(to: "Fleetwood Mac", genre: "Classic rock", perDay: 6, titles: ["The Chain", "Dreams", "Landslide"])
            .alsoListen(to: "Chicane", genre: "Trance", perDay: 2, titles: ["Don't Give Up (feat. Bryan Adams)", "Saltwater", "Offshore"])
            .live(at: .sydney, days: 70, photosPerWeek: 4)
            .addToLibrary(["Big Jet Plane", "Yellow Brick Road"], by: "Angus & Julia Stone", genre: "Folk", plays: 9)
            .trip(to: .hobart, nights: 3)
            .listen(to: "Love Remain", genre: "Chillout", perDay: 4, titles: ["Be With Me"])
            .alsoListen(to: "After Wes", genre: "Chillout", perDay: 3, titles: ["I Feel Alone, and It's Cold Outside"])
            .alsoListen(to: "Hemstock & Jennings", genre: "Chillout", perDay: 2, titles: ["Mirage (Extended Chill Mix)"])
            .live(at: .sydney, days: 75, photosPerWeek: 4)
            .listen(to: "Etherwood", genre: "Drum & bass", perDay: 6, titles: ["Begin By Letting Go"])
            .alsoListen(to: "Love Remain", genre: "Chillout", perDay: 3, titles: ["Be With Me"])
            .live(at: .melbourne, days: 30, photosPerWeek: 4)
            .addToLibrary(
                ["Fall at Your Feet", "Weather With You", "Four Seasons in One Day", "It's Only Natural"],
                by: "Crowded House", genre: "Pop rock", plays: 7, album: "Woodface"
            )
            .live(at: .melbourne, days: 50, photosPerWeek: 4)
            .trip(to: .sydney, nights: 2)
            .live(at: .melbourne, days: 20, photosPerWeek: 4)
            .listen(to: "Above & Beyond", genre: "Trance", perDay: 5, titles: ["Counting Down the Days (feat. Gemma Hayes)", "Sun & Moon"])
            .alsoListen(to: "BT", genre: "Trance", perDay: 3, titles: ["Flaming June", "Dreaming"])
            .alsoListen(to: "Schiller & Tricia McTeague", genre: "Progressive", perDay: 1, titles: ["Miracle"])
            .live(at: .sydney, days: 70, photosPerWeek: 4)
            .dayTrip(to: .wollongong)
            .live(at: .sydney, days: 20, photosPerWeek: 4)
            .trip(to: .melbourne, nights: 2)
            .live(at: .sydney, days: 12, photosPerWeek: 4)
    }

    /// Generates sample eras only when the database has none from the
    /// pipeline yet (it may still hold older hand-written sample eras, which
    /// this replaces), so it runs on first launch and never duplicates.
    static func insertIfNeeded(into context: ModelContext, now: Date = .now, calendar: Calendar = .current) async throws {
        let pipelineEras = try context.fetchCount(FetchDescriptor<Era>(predicate: #Predicate { $0.eraID != nil }))
        guard pipelineEras == 0 else { return }
        try await insert(into: context, now: now, calendar: calendar)
    }

    /// Generates and saves the sample eras unconditionally. Used by previews.
    static func insert(into context: ModelContext, now: Date = .now, calendar: Calendar = .current) async throws {
        let library = library(endingOn: now, calendar: calendar)
        let pipeline = EraPipeline(namer: SamplePlaceNamer(), sampler: sampler(for: library.moments))
        let result = await pipeline.run(
            moments: library.moments, plays: library.plays, library: library.library, now: now, calendar: calendar
        )
        try EraStore(context: context).save(result, moments: library.moments, now: now)
    }

    /// Each sample city's photos have a main tone and a smaller accent, like
    /// real photos with more than one colour in them. The accent gives the
    /// palette builder a second choice when the main tone matches the era
    /// before.
    static let cityColours: [(place: SamplePlace, main: UInt32, accent: UInt32)] = [
        (.sydney, 0xB5532F, 0x2F6F8F),
        (.melbourne, 0x6B6E2E, 0x8A3B2E),
        (.hobart, 0x2F6F6A, 0xC9A24A),
        (.wollongong, 0xE2A53C, 0x2F5B8F)
    ]

    static func sampler(for moments: [PhotoMoment]) -> SampleColorSampler {
        var images: [String: RGBAImage] = [:]
        for moment in moments {
            guard let coordinate = moment.coordinate,
                  let city = cityColours.first(where: { $0.place.coordinate.distance(to: coordinate) < 25_000 })
            else { continue }
            images[moment.coverID] = SampleImages.stripes([(city.main, 44), (city.accent, 20)])
        }
        return SampleColorSampler(images: images)
    }

    /// A few songs for previews of song lists.
    static let previewSongs = [
        Song(id: "fx-bt-1", title: "Flaming June", artist: "BT", genre: "Trance"),
        Song(id: "fx-above---beyond-1", title: "Counting Down the Days (feat. Gemma Hayes)", artist: "Above & Beyond", genre: "Trance"),
        Song(id: "fx-love-remain-1", title: "Be With Me", artist: "Love Remain", genre: "Chillout"),
        Song(id: "fx-etherwood-1", title: "Begin By Letting Go", artist: "Etherwood", genre: "Drum & bass")
    ]
}
