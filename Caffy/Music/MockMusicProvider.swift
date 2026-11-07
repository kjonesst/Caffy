import Foundation

/// A fake `MusicProvider` that returns songs from a small built-in catalog.
///
/// It's deterministic — the same date always gives the same songs — which makes
/// sample data and previews predictable.
struct MockMusicProvider: MusicProvider {
    /// The sample songs for each year. Anything older uses `earliestSongs`.
    static let songsByYear: [Int: [Song]] = [
        2026: [
            Song(id: "mock-flaming-june", title: "Flaming June", artist: "BT", genre: "Trance"),
            Song(id: "mock-long-way", title: "Long Way from Home (feat. RBBTS)", artist: "Above & Beyond & Spencer Brown", genre: "Progressive"),
            Song(id: "mock-counting", title: "Counting Down the Days (feat. Gemma Hayes)", artist: "Above & Beyond", genre: "Trance")
        ],
        2025: [
            Song(id: "mock-letting-go", title: "Begin By Letting Go", artist: "Etherwood", genre: "Drum & bass"),
            Song(id: "mock-be-with-me", title: "Be With Me", artist: "Love Remain", genre: "Chillout"),
            Song(id: "mock-alone", title: "I Feel Alone, and It's Cold Outside", artist: "After Wes", genre: "Chillout"),
            Song(id: "mock-mirage", title: "Mirage (Extended Chill Mix)", artist: "Hemstock & Jennings", genre: "Chillout")
        ],
        2024: [
            Song(id: "mock-dont-give-up", title: "Don't Give Up (feat. Bryan Adams)", artist: "Chicane", genre: "Trance"),
            Song(id: "mock-miracle", title: "Miracle", artist: "Schiller & Tricia McTeague", genre: "Progressive")
        ]
    ]

    static let earliestSongs = [
        Song(id: "mock-the-chain", title: "The Chain", artist: "Fleetwood Mac", genre: "Classic rock")
    ]

    func songs(playedAround date: Date) async throws -> [Song] {
        let year = Calendar.current.component(.year, from: date)
        return Self.songsByYear[year] ?? Self.earliestSongs
    }
}
