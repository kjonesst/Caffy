import Foundation

/// Whether an era is a stretch of everyday life or a trip away from it.
nonisolated enum EraKind: String, Codable, Sendable {
    /// Life at home, about a season long. Trips can sit inside its dates.
    case home
    /// An overnight trip away from home.
    case trip
}

/// Why an era starts where it does. Kept for tests and a future debug view,
/// so every boundary can be explained.
nonisolated enum EraBoundaryReason: String, Sendable {
    /// The first photos in the library, or the first after the frozen eras.
    case firstMoment
    /// No photos for at least `EraBuildConfig.longGap`.
    case longGap
    /// The user started living somewhere else.
    case homeChange
    /// An overnight trip away from home.
    case trip
    /// The music changed noticeably.
    case musicChange
    /// The previous era reached `EraBuildConfig.maxEraLength`.
    case maxLength
}

/// An era as the pipeline works it out, before it has colours, a title or a
/// place in the database.
///
/// This is a plain value, not the SwiftData `Era` model, so the pipeline can
/// run off the main actor and in unit tests.
nonisolated struct EraDraft: Hashable, Sendable, Identifiable {
    /// The id of the era's first moment when the era was first created. It
    /// stays the same while the era grows, so its playlist can be kept.
    let id: String
    let kind: EraKind
    /// The moments in this era, oldest first.
    let momentIDs: [String]
    let start: Date
    /// `nil` for the era the user is living through now.
    let end: Date?
    /// The middle of the era's place: home for a home era, the destination for
    /// a trip. `nil` when none of its photos has a location.
    let centre: Coordinate?
    let startReason: EraBoundaryReason

    var isCurrent: Bool { end == nil }
}
