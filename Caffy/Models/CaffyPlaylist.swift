import Foundation
import SwiftData

/// A playlist Caffy creates and keeps up to date for a place.
///
/// Later this will be mirrored into the user's Apple Music library. For now it
/// only lives inside Caffy.
@Model
final class CaffyPlaylist {
    var name: String
    var lastUpdated: Date

    /// The place this playlist is built from. The other side of `Place.playlist`.
    var place: Place?

    init(name: String, lastUpdated: Date) {
        self.name = name
        self.lastUpdated = lastUpdated
    }

    /// The playlist's songs: every song from the place's moments, newest moment
    /// first, with duplicates removed.
    ///
    /// This is computed rather than stored, so the playlist "updates itself"
    /// whenever a new moment is added to its place.
    var songs: [Song] {
        guard let place else { return [] }
        var seenIDs = Set<String>()
        // `insert` returns `inserted == false` for IDs already in the set,
        // which filters out repeats while keeping the original order.
        return place.momentsNewestFirst
            .flatMap(\.songs)
            .filter { seenIDs.insert($0.id).inserted }
    }
}
