import Foundation
import SwiftData

/// A stretch of the user's life, told through its photos and its music.
///
/// Eras are Caffy's main unit: Home shows one card per era, Library places each
/// one on the genre river, and each era owns one self-updating playlist.
///
/// Fields added after the first release are optional or have a default, so
/// an existing database gains them on its own when the app updates.
@Model
final class Era {
    /// The id of the `EraDraft` this was saved from, so the next sync can find
    /// it again. `nil` for sample data.
    var eraID: String?

    /// `EraKind`'s raw value. Saved as text rather than the enum, so adding
    /// kinds later never stops an existing database from opening. Use `kind`.
    var kindRaw: String = "home"

    /// Frozen eras are never re-cut, renamed or recoloured again.
    var isFrozen: Bool = false

    /// `EraBoundaryReason`'s raw value: why the era starts where it does.
    var startReasonRaw: String?

    /// The middle of the era's place: home, or a trip's main destination.
    var centreLatitude: Double?
    var centreLongitude: Double?

    var title: String

    /// The short handwritten label on the card, such as "2026" or "way back".
    var whenLabel: String

    /// One line on how the user's listening changed in this era.
    var summary: String

    var startDate: Date

    /// `nil` for the era the user is living through now.
    var endDate: Date?

    /// The card's colours, as saved.
    ///
    /// Saved as a new, optional `colors` attribute because `palette` used to
    /// be saved as an enum. SwiftData saves a struct as one column per field,
    /// and an existing database can only gain those columns on its own if
    /// they may be empty; otherwise it fails to open. Use `palette`.
    private var colors: EraPalette?

    /// The card's colours. Eras saved before palettes became colours show rust.
    var palette: EraPalette {
        get { colors ?? .rust }
        set { colors = newValue }
    }

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
        self.colors = palette
    }

    var isCurrent: Bool { endDate == nil }

    var kind: EraKind {
        get { EraKind(rawValue: kindRaw) ?? .home }
        set { kindRaw = newValue.rawValue }
    }

    /// SwiftData doesn't keep to-many relationships in any order, so sort here.
    /// Moments a sync has just deleted are left out (see `isLive`).
    var momentsNewestFirst: [Moment] {
        moments.filter(\.isLive).sorted { $0.date > $1.date }
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

extension Era {
    /// Copies an era worked out by the pipeline, except its moments and
    /// playlist. Only what changed is set (see `assign`).
    func update(from built: BuiltEra) {
        let draft = built.draft
        assign(draft.id, to: \.eraID)
        assign(draft.kind.rawValue, to: \.kindRaw)
        assign(built.isFrozen, to: \.isFrozen)
        assign(draft.startReason.rawValue, to: \.startReasonRaw)
        assign(draft.centre?.latitude, to: \.centreLatitude)
        assign(draft.centre?.longitude, to: \.centreLongitude)
        assign(built.content.title, to: \.title)
        assign(built.content.whenLabel, to: \.whenLabel)
        assign(built.content.summary, to: \.summary)
        assign(draft.start, to: \.startDate)
        assign(draft.end, to: \.endDate)
        assign(built.palette, to: \.colors)
    }

    /// This era as the pipeline needs it once frozen, or `nil` for an era the
    /// pipeline didn't make (sample data).
    var frozen: FrozenEra? {
        guard let eraID else { return nil }
        let centre = both(centreLatitude, centreLongitude).map { Coordinate(latitude: $0, longitude: $1) }
        // Oldest first with the id breaking ties, the pipeline's own order.
        let momentIDs = moments
            .compactMap { moment in moment.momentID.map { (date: moment.date, id: $0) } }
            .sorted { ($0.date, $0.id) < ($1.date, $1.id) }
            .map(\.id)
        let draft = EraDraft(
            id: eraID,
            kind: kind,
            momentIDs: momentIDs,
            start: startDate,
            end: endDate,
            centre: centre,
            startReason: startReasonRaw.flatMap(EraBoundaryReason.init(rawValue:)) ?? .firstMoment
        )
        return FrozenEra(
            draft: draft,
            content: EraContent(title: title, summary: summary, whenLabel: whenLabel),
            palette: palette
        )
    }
}

/// Both values, or `nil` if either is missing.
private func both<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
