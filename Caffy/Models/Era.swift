import Foundation
import SwiftData

/// A stretch of the user's life, told through its photos and its music.
///
/// Eras are Caffy's main unit: Home shows one card per era, Library places each
/// one on the genre river, and each era owns one self-updating playlist.
@Model
final class Era {
    var title: String

    /// The short handwritten label on the card, such as "2026" or "way back".
    var whenLabel: String

    /// One line on how the user's listening changed in this era.
    var summary: String

    var startDate: Date

    /// `nil` for the era the user is living through now.
    var endDate: Date?

    var palette: EraPalette

    /// The photos and songs in this era. Deleting an era deletes its moments.
    @Relationship(deleteRule: .cascade, inverse: \Moment.era)
    var moments: [Moment] = []

    /// The self-updating playlist Caffy keeps for this era.
    @Relationship(deleteRule: .cascade, inverse: \CaffyPlaylist.era)
    var playlist: CaffyPlaylist?

    init(
        title: String,
        whenLabel: String,
        summary: String,
        startDate: Date,
        endDate: Date? = nil,
        palette: EraPalette
    ) {
        self.title = title
        self.whenLabel = whenLabel
        self.summary = summary
        self.startDate = startDate
        self.endDate = endDate
        self.palette = palette
    }

    var isCurrent: Bool { endDate == nil }

    /// SwiftData doesn't keep to-many relationships in any order, so sort here.
    var momentsNewestFirst: [Moment] {
        moments.sorted { $0.date > $1.date }
    }

    /// Every song from this era's moments, newest moment first, without repeats.
    ///
    /// This is computed rather than stored, so the music "updates itself"
    /// whenever a new moment joins the era.
    var songs: [Song] {
        Self.songs(in: momentsNewestFirst)
    }

    /// The songs from already-sorted moments, without repeats. Views that also
    /// need the sorted moments call this, so the moments are sorted only once.
    static func songs(in momentsNewestFirst: [Moment]) -> [Song] {
        var seenIDs = Set<String>()
        // `insert` returns `inserted == false` for IDs already in the set,
        // which filters out repeats while keeping the original order.
        return momentsNewestFirst
            .flatMap(\.songs)
            .filter { seenIDs.insert($0.id).inserted }
    }
}
