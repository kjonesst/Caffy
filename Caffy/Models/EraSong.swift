import Foundation

/// Where one of an era's songs came from. The order of the cases is their
/// strength: a song found more than one way keeps the strongest.
nonisolated enum SongEvidence: String, Codable, Sendable, CaseIterable, Comparable {
    /// Played near one of the era's moments.
    case nearPlay
    /// Added to the library during the era (see `LibraryAdditions`).
    case libraryAdded
    /// Played on the same day as one of the era's moments, but not near it.
    case loosePlay

    /// How strong this evidence is. Lower is stronger.
    var rank: Int {
        switch self {
        case .nearPlay: 0
        case .libraryAdded: 1
        case .loosePlay: 2
        }
    }

    /// Stronger evidence sorts first.
    static func < (lhs: SongEvidence, rhs: SongEvidence) -> Bool { lhs.rank < rhs.rank }
}

/// One song in an era's playlist, with where it came from and how strongly.
nonisolated struct EraSong: Codable, Hashable, Sendable, Identifiable {
    var song: Song
    var evidence: SongEvidence
    /// For plays, the matcher's weight (summed over the era's moments in a
    /// playlist). For library additions, `LibraryAdditions.score`.
    var score: Double

    var id: String { song.id }
}
