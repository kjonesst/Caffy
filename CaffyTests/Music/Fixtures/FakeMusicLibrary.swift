import Foundation
@testable import Caffy

/// A music library whose songs a test can change between reads, or that
/// Caffy may not read at all (`nil`).
actor FakeMusicLibrary: MusicLibraryReader {
    private var current: [LibrarySongSnapshot]?

    init(_ songs: [LibrarySongSnapshot]?) {
        current = songs
    }

    func set(_ songs: [LibrarySongSnapshot]?) {
        current = songs
    }

    func songs() async -> [LibrarySongSnapshot]? {
        current
    }
}

/// Times for listening tests: hours and days from a fixed start.
enum ListeningTime {
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let hour: TimeInterval = 60 * 60
    static let day: TimeInterval = 24 * hour

    static func hours(_ count: Double) -> Date { start.addingTimeInterval(count * hour) }
    static func days(_ count: Double) -> Date { start.addingTimeInterval(count * day) }
}

extension LibrarySongSnapshot {
    /// A song with only the fields listening tests care about.
    static func fixture(
        _ persistentID: UInt64,
        catalogID: String? = nil,
        lastPlayed: Date? = nil,
        count: Int = 0
    ) -> LibrarySongSnapshot {
        LibrarySongSnapshot(
            persistentID: persistentID,
            catalogID: catalogID,
            title: "Song \(persistentID)",
            artist: "Artist \(persistentID)",
            genre: "Pop",
            duration: 200,
            lastPlayedDate: lastPlayed,
            playCount: count
        )
    }
}
