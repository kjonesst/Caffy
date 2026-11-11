import CoreLocation
import Foundation
import MapKit

/// Names places with Apple's reverse geocoding (`MKReverseGeocodingRequest`).
///
/// This sends the coordinate to Apple, never to a Caffy server. The pipeline
/// only asks about home and trip destinations (a handful of places), and
/// `CachedPlaceNamer` makes sure each is asked about once.
///
/// Apple limits how often an app may geocode, so lookups are spaced at least
/// `minimumInterval` apart. A rate-limited or offline lookup reports
/// `.failed`, so it isn't cached and the next sync tries again.
nonisolated struct MapKitPlaceLookup: PlaceLookup {
    var minimumInterval: Duration = .seconds(1)

    /// Shared by every lookup in the app, so the spacing holds across syncs.
    private static let throttle = RequestThrottle()

    func lookUp(_ coordinate: Coordinate) async -> PlaceLookupResult {
        await Self.throttle.wait(minimumInterval)
        return await Self.lookUpOnMain(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// MapKit delivers its results on the main actor, and its objects can't
    /// leave it, so the whole lookup happens there and only the plain result
    /// comes back.
    @MainActor
    private static func lookUpOnMain(latitude: Double, longitude: Double) async -> PlaceLookupResult {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: latitude, longitude: longitude)) else {
            return .failed
        }
        // Titles are written in English for now, so names match them.
        request.preferredLocale = Locale(identifier: "en")
        do {
            let items = try await request.mapItems
            // Out at sea MapKit succeeds with an empty city name, so a blank
            // name counts as no town at all.
            func city(_ representations: MKAddressRepresentations) -> String? {
                let name = representations.cityName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return name.isEmpty ? nil : name
            }
            guard let representations = items.lazy.compactMap(\.addressRepresentations).first(where: { city($0) != nil }),
                  let name = city(representations)
            else { return .notFound }
            return .found(PlaceName(locality: name, region: representations.regionName))
        } catch {
            return .failed
        }
    }

    /// The cache-backed namer the app uses.
    static func cachedNamer(cacheFile: URL? = PlaceNameCache.standardFileURL) -> CachedPlaceNamer<MapKitPlaceLookup> {
        CachedPlaceNamer(lookup: MapKitPlaceLookup(), cache: PlaceNameCache(fileURL: cacheFile))
    }
}

/// Spaces calls out so they happen at most once per interval, in the order
/// they arrive.
private actor RequestThrottle {
    private var next: ContinuousClock.Instant?

    func wait(_ interval: Duration) async {
        let clock = ContinuousClock()
        let slot = max(clock.now, next ?? clock.now)
        // Claim the slot before sleeping, so a call arriving meanwhile queues
        // after this one instead of sharing its slot.
        next = slot + interval
        try? await clock.sleep(until: slot)
    }
}
