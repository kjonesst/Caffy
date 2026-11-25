import Foundation
import Testing
@testable import Caffy

/// `CatalogBatcher` fetches in batches and narrows down responses that
/// fail to decode, without MusicKit.
struct CatalogBatcherTests {
    /// Records each request. Fails to decode when a request is bigger than
    /// `maxSize`, or holds one of `badIDs`; throws `URLError` if `offline`.
    private actor Catalog {
        let maxSize: Int
        let badIDs: Set<String>
        let offline: Bool
        private(set) var requests: [[String]] = []

        init(maxSize: Int = .max, badIDs: Set<String> = [], offline: Bool = false) {
            self.maxSize = maxSize
            self.badIDs = badIDs
            self.offline = offline
        }

        func fetch(_ ids: [String]) throws -> [String: String] {
            requests.append(ids)
            if offline { throw URLError(.notConnectedToInternet) }
            if ids.count > maxSize || !badIDs.isDisjoint(with: ids) {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unexpected end of file"))
            }
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, "song \($0)") })
        }
    }

    private static func ids(_ count: Int) -> [String] { (1...count).map(String.init) }

    @Test func fetchesInBatches() async throws {
        let catalog = Catalog()

        let result = try await CatalogBatcher.fetch(Self.ids(250), batchSize: 100) { try await catalog.fetch($0) }

        #expect(result.items.count == 250)
        #expect(await catalog.requests.map(\.count) == [100, 100, 50])
        #expect(result.failedRequestSizes.isEmpty)
        #expect(result.requests == 3)
    }

    @Test func repeatsAreFetchedOnce() async throws {
        let catalog = Catalog()

        let result = try await CatalogBatcher.fetch(["1", "2", "1", "3", "2"], batchSize: 100) { try await catalog.fetch($0) }

        #expect(await catalog.requests == [["1", "2", "3"]])
        #expect(result.items.count == 3)
    }

    @Test func tooBigABatchIsSplitUntilItWorks() async throws {
        let catalog = Catalog(maxSize: 30)

        let result = try await CatalogBatcher.fetch(Self.ids(100), batchSize: 100) { try await catalog.fetch($0) }

        #expect(result.items.count == 100)
        #expect(result.undecodableIDs.isEmpty)
        #expect(result.failedRequestSizes == [100, 50, 50])
        #expect(result.firstError?.contains("Unexpected end of file") == true)
        #expect(CatalogBatcher.summarise(result.failedRequestSizes) == "100 ×1, 50 ×2")
    }

    @Test func oneBadIDIsFoundAndTheRestStillFetched() async throws {
        let catalog = Catalog(badIDs: ["37"])

        let result = try await CatalogBatcher.fetch(Self.ids(100), batchSize: 100) { try await catalog.fetch($0) }

        #expect(result.undecodableIDs == ["37"])
        #expect(result.items.count == 99)
        #expect(result.items["37"] == nil)
    }

    @Test func otherErrorsAreThrownWithoutSplitting() async throws {
        let catalog = Catalog(offline: true)

        await #expect(throws: URLError.self) {
            try await CatalogBatcher.fetch(Self.ids(100), batchSize: 100) { try await catalog.fetch($0) }
        }
        #expect(await catalog.requests.count == 1)
    }

    @Test func nothingToFetchMakesNoRequest() async throws {
        let catalog = Catalog()

        let result = try await CatalogBatcher.fetch([], batchSize: 100) { try await catalog.fetch($0) }

        #expect(result.requests == 0)
        #expect(await catalog.requests.isEmpty)
    }
}
