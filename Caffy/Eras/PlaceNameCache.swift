import Foundation

/// What one place lookup found.
nonisolated enum PlaceLookupResult: Equatable, Sendable {
    case found(PlaceName)
    /// The lookup worked, but there's no town there (open sea, wilderness).
    /// Remembered, so the place isn't looked up again.
    case notFound
    /// The lookup didn't work (offline, rate-limited). Not remembered, so
    /// the next sync tries again.
    case failed
}

/// Looks up one place, without any caching. `MapKitPlaceLookup` is the real one.
nonisolated protocol PlaceLookup: Sendable {
    func lookUp(_ coordinate: Coordinate) async -> PlaceLookupResult
}

/// Remembers place names between syncs, so each place is looked up once.
///
/// Places are keyed by coordinates rounded to two decimal places (about
/// 1 km), which is plenty for naming a town. The cache is a small JSON file:
/// it can be thrown away at any time and rebuilt by looking places up again.
/// An actor, because the pipeline runs off the main actor.
actor PlaceNameCache {
    /// One remembered lookup. `name` is `nil` when there was nothing there.
    nonisolated struct Entry: Codable, Equatable, Sendable {
        let name: PlaceName?
    }

    /// Where the cache is saved, or `nil` to keep it in memory only.
    private let fileURL: URL?
    /// Loaded from the file on first use.
    private var entries: [String: Entry]?

    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    /// The app's cache file, in Application Support.
    nonisolated static var standardFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "PlaceNames.json")
    }

    /// The cache key for a coordinate, such as "-33.87,151.21".
    nonisolated static func key(for coordinate: Coordinate) -> String {
        String(format: "%.2f,%.2f", coordinate.latitude, coordinate.longitude)
    }

    func entry(for coordinate: Coordinate) -> Entry? {
        loadedEntries()[Self.key(for: coordinate)]
    }

    func store(_ name: PlaceName?, for coordinate: Coordinate) {
        var all = loadedEntries()
        all[Self.key(for: coordinate)] = Entry(name: name)
        entries = all
        save(all)
    }

    private func loadedEntries() -> [String: Entry] {
        if let entries { return entries }
        let loaded = fileURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) }
            ?? [:]
        entries = loaded
        return loaded
    }

    /// Saving can fail (disk full); the cache then just lives in memory.
    private func save(_ all: [String: Entry]) {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(all) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// A `PlaceNamer` that asks `lookup` only about places it hasn't seen before.
nonisolated struct CachedPlaceNamer<Lookup: PlaceLookup>: PlaceNamer {
    let lookup: Lookup
    let cache: PlaceNameCache

    func name(for coordinate: Coordinate) async -> PlaceName? {
        if let remembered = await cache.entry(for: coordinate) {
            return remembered.name
        }
        switch await lookup.lookUp(coordinate) {
        case .found(let name):
            await cache.store(name, for: coordinate)
            return name
        case .notFound:
            await cache.store(nil, for: coordinate)
            return nil
        case .failed:
            return nil
        }
    }
}
