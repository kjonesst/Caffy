import Foundation
import SwiftData

/// The playlist Caffy creates and keeps up to date for an era.
///
/// Later this will be mirrored into the user's Apple Music library. For now it
/// only lives inside Caffy.
@Model
final class CaffyPlaylist {
    var name: String
    var lastUpdated: Date

    /// The era this playlist is built from. The other side of `Era.playlist`.
    var era: Era?

    init(name: String, lastUpdated: Date) {
        self.name = name
        self.lastUpdated = lastUpdated
    }

    var songs: [Song] { era?.songs.map(\.song) ?? [] }
}
