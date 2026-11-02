import Foundation

/// Where Caffy gets music information from.
///
/// A `protocol` describes what a type can do without saying how. The rest of the
/// app only talks to `MusicProvider`, so `MockMusicProvider` (now) can later be
/// swapped for an `AppleMusicProvider` (MusicKit) without changing any views.
protocol MusicProvider {
    /// Songs the user was listening to around the given time.
    ///
    /// `async` because a real implementation will call MusicKit; `throws` because
    /// that call can fail (no permission, no network, and so on).
    func songs(playedAround date: Date) async throws -> [Song]
}
