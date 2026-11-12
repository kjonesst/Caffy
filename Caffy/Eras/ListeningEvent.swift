import Foundation

/// One time the user listened to a song.
///
/// Apple Music doesn't give exact play times, so a real history is pieced
/// together from snapshots and some plays are only known to fall somewhere in
/// a window. `interval` covers the play itself when the time is known, and the
/// whole window when it's an estimate (`isEstimated`).
nonisolated struct ListeningEvent: Hashable, Sendable {
    let song: Song
    let interval: DateInterval
    var isEstimated: Bool = false
    /// `false` for an estimated play whose window is too long to say which
    /// moment it belongs to (longer than `EraBuildConfig.maxEstimatedPlayWindow`).
    /// It still counts towards listening totals, but `MusicMatcher` skips it.
    var isMatchable: Bool = true
}

/// Where Caffy gets the user's listening history from.
///
/// The era pipeline only talks to this protocol, so a fixture or mock source
/// (tests, sample data) and the real ones (`RecordedListeningSource`,
/// `MediaPlayerListeningSource`) are interchangeable.
///
/// `nonisolated` and `Sendable` let the pipeline call it off the main actor.
nonisolated protocol ListeningSource: Sendable {
    /// Every play whose interval overlaps `interval`, in any order.
    ///
    /// `async throws` because a real implementation reads MusicKit and can
    /// fail (no permission, no subscription, and so on).
    func plays(in interval: DateInterval) async throws -> [ListeningEvent]
}
