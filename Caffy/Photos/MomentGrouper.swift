import Foundation

/// When a run of photos stops being one moment.
nonisolated struct MomentGroupingConfig: Sendable {
    /// A longer gap than this between two photos in a row starts a new moment.
    var maxTimeGap: TimeInterval = 2 * 60 * 60
    /// A photo further than this, in metres, from the moment's last photo with
    /// a location starts a new moment.
    var maxDistance: Double = 1_000

    static let standard = MomentGroupingConfig()
}

/// A run of photos taken close together in time and place.
///
/// This is a plain value, not the SwiftData `Moment` model: grouping runs off
/// the main actor and in unit tests, where model objects can't go. `LibrarySync`
/// copies each one into a `Moment` when saving.
nonisolated struct PhotoMoment: Hashable, Sendable, Identifiable {
    /// The first photo's identifier. It stays the same when later photos join
    /// the moment, which keeps the moment recognisable between syncs.
    let id: String
    let start: Date
    let end: Date
    /// Every photo in the moment, oldest first.
    let photoIDs: [String]
    /// The photo that stands for the whole moment in collages.
    let coverID: String
    let coverAspectRatio: Double
    /// One real photo location that sits near the middle of the moment's
    /// located photos. `nil` when none of them has a location.
    let coordinate: Coordinate?
}

/// Splits a photo library into moments.
///
/// A pure function: the same photos always give the same moments, nothing is
/// read from or written to the outside world, so it's simple to test.
nonisolated enum MomentGrouper {
    /// Groups photos into moments, oldest moment first.
    ///
    /// Photos are walked in time order. A photo starts a new moment when the
    /// gap since the previous photo is longer than `maxTimeGap`, or when it and
    /// the moment's most recent located photo are more than `maxDistance`
    /// apart. Photos without a location are grouped by time only.
    ///
    /// Each photo is compared with the one before it, not with the start of
    /// the moment, so a slow day-long walk with regular photos stays one moment.
    static func group(_ items: [PhotoItem], config: MomentGroupingConfig = .standard) -> [PhotoMoment] {
        // Sort by date, using the input position to break ties so the result
        // never depends on the sorting algorithm.
        let sorted = items.enumerated()
            .sorted { ($0.element.creationDate, $0.offset) < ($1.element.creationDate, $1.offset) }
            .map(\.element)

        var moments: [PhotoMoment] = []
        var current: [PhotoItem] = []
        var lastLocated: Coordinate?

        for item in sorted {
            if let previous = current.last, startsNewMoment(item, after: previous, lastLocated: lastLocated, config: config) {
                moments.append(makeMoment(from: current))
                current = []
                lastLocated = nil
            }
            current.append(item)
            if let coordinate = item.coordinate {
                lastLocated = coordinate
            }
        }
        if !current.isEmpty {
            moments.append(makeMoment(from: current))
        }
        return moments
    }

    private static func startsNewMoment(
        _ item: PhotoItem,
        after previous: PhotoItem,
        lastLocated: Coordinate?,
        config: MomentGroupingConfig
    ) -> Bool {
        if item.creationDate.timeIntervalSince(previous.creationDate) > config.maxTimeGap {
            return true
        }
        if let here = item.coordinate, let there = lastLocated {
            return here.distance(to: there) > config.maxDistance
        }
        return false
    }

    /// Builds a moment from photos that are already in time order.
    private static func makeMoment(from photos: [PhotoItem]) -> PhotoMoment {
        // The middle photo makes a better cover than the first, which is often
        // a quick test shot.
        let cover = photos[photos.count / 2]
        return PhotoMoment(
            id: photos[0].id,
            start: photos[0].creationDate,
            end: photos[photos.count - 1].creationDate,
            photoIDs: photos.map(\.id),
            coverID: cover.id,
            coverAspectRatio: cover.aspectRatio,
            coordinate: representativeCoordinate(of: photos.compactMap(\.coordinate))
        )
    }

    /// The located photo closest to the average of all located photos, so the
    /// moment's place is always somewhere a photo was actually taken.
    static func representativeCoordinate(of coordinates: [Coordinate]) -> Coordinate? {
        guard !coordinates.isEmpty else { return nil }
        // A plain average of latitudes and longitudes is fine for points a
        // kilometre or so apart. (It would go wrong across the 180° line.)
        let count = Double(coordinates.count)
        let centre = Coordinate(
            latitude: coordinates.map(\.latitude).reduce(0, +) / count,
            longitude: coordinates.map(\.longitude).reduce(0, +) / count
        )
        return coordinates.min { $0.distance(to: centre) < $1.distance(to: centre) }
    }
}
