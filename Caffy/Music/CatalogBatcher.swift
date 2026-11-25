import Foundation

/// Fetches catalog items by id in batches, and narrows down failures.
///
/// On a device, a catalog request for 100 song ids failed with
/// `DecodingError` ("Unexpected end of file": an empty or cut-off response).
/// So a batch that fails to decode is split in half and each half retried,
/// down to single ids. If the batch was too big, the halves succeed. If one
/// id breaks the response, it ends up failing alone and is reported, and
/// every other id is still fetched. Any other error (offline, no access)
/// is thrown straight away, since splitting can't fix it.
///
/// Plain values and a request closure, so it's tested without MusicKit.
nonisolated enum CatalogBatcher {
    struct Fetch<Item: Sendable>: Sendable {
        var items: [String: Item] = [:]
        /// How many ids each request that failed to decode asked for.
        var failedRequestSizes: [Int] = []
        /// Ids whose response failed to decode even when asked for alone.
        var undecodableIDs: [String] = []
        /// The first decoding error, to report.
        var firstError: String?
        /// How many requests were made in all.
        var requests = 0
    }

    /// Fetches `ids` (repeats once each) in batches of `batchSize`.
    static func fetch<Item: Sendable>(
        _ ids: [String],
        batchSize: Int,
        request: @Sendable ([String]) async throws -> [String: Item]
    ) async throws -> Fetch<Item> {
        var result = Fetch<Item>()
        let unique = MusicKitCatalog.uniqued(ids)
        let size = max(batchSize, 1)
        for start in stride(from: 0, to: unique.count, by: size) {
            try await fetch(Array(unique[start..<min(start + size, unique.count)]), into: &result, request: request)
        }
        return result
    }

    private static func fetch<Item: Sendable>(
        _ batch: [String],
        into result: inout Fetch<Item>,
        request: @Sendable ([String]) async throws -> [String: Item]
    ) async throws {
        result.requests += 1
        do {
            result.items.merge(try await request(batch)) { _, new in new }
        } catch let error as DecodingError {
            result.failedRequestSizes.append(batch.count)
            if result.firstError == nil { result.firstError = String(describing: error) }
            guard batch.count > 1 else {
                result.undecodableIDs.append(contentsOf: batch)
                return
            }
            let middle = batch.count / 2
            try await fetch(Array(batch[..<middle]), into: &result, request: request)
            try await fetch(Array(batch[middle...]), into: &result, request: request)
        }
    }

    /// `[100, 50, 50]` as "100 ×1, 50 ×2", largest first.
    static func summarise(_ sizes: [Int]) -> String {
        Dictionary(grouping: sizes, by: { $0 })
            .sorted { $0.key > $1.key }
            .map { "\($0.key) ×\($0.value.count)" }
            .joined(separator: ", ")
    }
}
