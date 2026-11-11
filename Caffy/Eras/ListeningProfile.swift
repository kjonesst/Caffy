import Foundation

/// What someone listened to over a stretch of time: plays per artist, genre
/// and song.
///
/// Used to spot a change in music between two stretches, and later to title
/// an era ("On repeat: Tame Impala").
nonisolated struct ListeningProfile: Equatable, Sendable {
    private(set) var playCount = 0
    private(set) var artistPlays: [String: Int] = [:]
    private(set) var genrePlays: [String: Int] = [:]
    /// Keyed by song id.
    private(set) var songPlays: [String: Int] = [:]

    /// A profile from counts that were already added up.
    init(playCount: Int, artistPlays: [String: Int], genrePlays: [String: Int], songPlays: [String: Int] = [:]) {
        self.playCount = playCount
        self.artistPlays = artistPlays
        self.genrePlays = genrePlays
        self.songPlays = songPlays
    }

    init<Plays: Sequence>(_ plays: Plays) where Plays.Element == ListeningEvent {
        for play in plays {
            playCount += 1
            artistPlays[play.song.artist, default: 0] += 1
            songPlays[play.song.id, default: 0] += 1
            if let genre = play.song.genre {
                genrePlays[genre, default: 0] += 1
            }
        }
    }

    /// How different two stretches of listening are, from 0 (the same mix)
    /// to 1 (nothing in common).
    ///
    /// The average of the cosine distance between artist mixes and between
    /// genre mixes, so a new artist in a familiar genre counts as half a
    /// change. Genres are skipped when either side has none. Empty listening
    /// on either side counts as no change.
    func distance(to other: ListeningProfile) -> Double {
        guard playCount > 0, other.playCount > 0 else { return 0 }
        let artists = Self.cosineDistance(artistPlays, other.artistPlays)
        guard !genrePlays.isEmpty, !other.genrePlays.isEmpty else { return artists }
        return (artists + Self.cosineDistance(genrePlays, other.genrePlays)) / 2
    }

    /// The most-played artists, most plays first, then by name.
    func topArtists(_ limit: Int) -> [(artist: String, plays: Int)] {
        artistPlays
            .sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            .prefix(limit)
            .map { (artist: $0.key, plays: $0.value) }
    }

    /// 1 − cos θ between two count vectors, clamped to 0...1.
    private static func cosineDistance(_ a: [String: Int], _ b: [String: Int]) -> Double {
        // The sums are whole numbers, so they come out exactly the same
        // whatever order the dictionaries are walked in.
        var dot = 0
        var squaresA = 0
        var squaresB = 0
        for (key, count) in a {
            squaresA += count * count
            if let other = b[key] { dot += count * other }
        }
        for count in b.values {
            squaresB += count * count
        }
        guard squaresA > 0, squaresB > 0 else { return 0 }
        let cosine = Double(dot) / (Double(squaresA) * Double(squaresB)).squareRoot()
        return min(1, max(0, 1 - cosine))
    }
}
