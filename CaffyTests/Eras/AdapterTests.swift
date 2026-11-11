import CoreGraphics
import Foundation
import Testing
@testable import Caffy

/// Tests for the parts of the real adapters that don't need the network or
/// the photo library: the place-name cache and thumbnail scaling.
struct AdapterTests {
    // MARK: - Place-name cache

    /// A lookup that answers from a script and counts what it's asked.
    private actor ScriptedLookup: PlaceLookup {
        let answers: [String: PlaceLookupResult]
        private(set) var asked: [String] = []

        init(_ answers: [String: PlaceLookupResult]) {
            self.answers = answers
        }

        func lookUp(_ coordinate: Coordinate) async -> PlaceLookupResult {
            let key = PlaceNameCache.key(for: coordinate)
            asked.append(key)
            return answers[key] ?? .failed
        }
    }

    private static let sydney = SamplePlace.sydney.coordinate
    private static let sea = Coordinate(latitude: -40, longitude: 160)
    private static let sydneyName = PlaceName(locality: "Sydney", region: "New South Wales")

    private static func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "PlaceNames-\(UUID().uuidString).json")
    }

    @Test func nearbyCoordinatesShareAKey() {
        let a = Coordinate(latitude: -33.8688, longitude: 151.2093)
        let b = Coordinate(latitude: -33.8712, longitude: 151.2071)
        let far = SamplePlace.sydney.offset(north: 3_000, east: 0)
        #expect(PlaceNameCache.key(for: a) == "-33.87,151.21")
        #expect(PlaceNameCache.key(for: a) == PlaceNameCache.key(for: b))
        #expect(PlaceNameCache.key(for: a) != PlaceNameCache.key(for: far))
    }

    @Test func eachPlaceIsLookedUpOnce() async {
        let lookup = ScriptedLookup([PlaceNameCache.key(for: Self.sydney): .found(Self.sydneyName)])
        let namer = CachedPlaceNamer(lookup: lookup, cache: PlaceNameCache(fileURL: nil))

        #expect(await namer.name(for: Self.sydney) == Self.sydneyName)
        #expect(await namer.name(for: Self.sydney) == Self.sydneyName)
        #expect(await lookup.asked.count == 1)
    }

    @Test func nothingThereIsRememberedButFailuresAreRetried() async {
        let offline = Coordinate(latitude: -37.81, longitude: 144.96)
        let lookup = ScriptedLookup([PlaceNameCache.key(for: Self.sea): .notFound])
        let namer = CachedPlaceNamer(lookup: lookup, cache: PlaceNameCache(fileURL: nil))

        #expect(await namer.name(for: Self.sea) == nil)
        #expect(await namer.name(for: Self.sea) == nil)
        #expect(await namer.name(for: offline) == nil)
        #expect(await namer.name(for: offline) == nil)
        // The sea was asked about once; the failed lookup twice.
        #expect(await lookup.asked == [
            PlaceNameCache.key(for: Self.sea), PlaceNameCache.key(for: offline), PlaceNameCache.key(for: offline)
        ])
    }

    @Test func cacheSurvivesBetweenLaunches() async throws {
        let file = Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let first = ScriptedLookup([
            PlaceNameCache.key(for: Self.sydney): .found(Self.sydneyName),
            PlaceNameCache.key(for: Self.sea): .notFound
        ])
        let firstNamer = CachedPlaceNamer(lookup: first, cache: PlaceNameCache(fileURL: file))
        _ = await firstNamer.name(for: Self.sydney)
        _ = await firstNamer.name(for: Self.sea)

        // A new cache reading the same file, with a lookup that knows nothing.
        let second = ScriptedLookup([:])
        let secondNamer = CachedPlaceNamer(lookup: second, cache: PlaceNameCache(fileURL: file))
        #expect(await secondNamer.name(for: Self.sydney) == Self.sydneyName)
        #expect(await secondNamer.name(for: Self.sea) == nil)
        #expect(await second.asked.isEmpty)
    }

    @Test func unreadableCacheFileStartsEmpty() async throws {
        let file = Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not json".utf8).write(to: file)

        let lookup = ScriptedLookup([PlaceNameCache.key(for: Self.sydney): .found(Self.sydneyName)])
        let namer = CachedPlaceNamer(lookup: lookup, cache: PlaceNameCache(fileURL: file))
        #expect(await namer.name(for: Self.sydney) == Self.sydneyName)
        #expect(await lookup.asked.count == 1)
    }

    // MARK: - Thumbnails

    /// A Core Graphics image from one hex colour per column band.
    private static func image(width: Int, height: Int, alpha: UInt8 = 255, colour: (_ x: Int, _ y: Int) -> UInt32) -> CGImage {
        var bytes: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let hex = colour(x, y)
                // Premultiplied, as Core Graphics stores it.
                func channel(_ shift: UInt32) -> UInt8 { UInt8(Int((hex >> shift) & 0xFF) * Int(alpha) / 255) }
                bytes += [channel(16), channel(8), channel(0), alpha]
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )!
    }

    @Test func solidPhotoKeepsItsColour() throws {
        let image = try #require(RGBAImage(Self.image(width: 64, height: 64) { _, _ in 0x4F8A3A }, side: 32))
        #expect(image.width == 32 && image.height == 32)
        #expect(image.bytes.count == 32 * 32 * 4)
        #expect(Array(image.bytes.prefix(4)) == [0x4F, 0x8A, 0x3A, 255])
        #expect(ColorQuantizer.swatches(in: image).count == 1)
    }

    @Test func halvesStayHalves() throws {
        let image = try #require(RGBAImage(Self.image(width: 64, height: 64) { x, _ in x < 32 ? 0xE07A2E : 0x2F5BC8 }, side: 32))
        let weights = ColorQuantizer.swatches(in: image).map(\.weight)
        // Blending at the edge can add a sliver of in-between colour.
        #expect(weights.prefix(2).allSatisfy { abs($0 - 0.5) < 0.05 })
    }

    @Test func widePhotoIsCroppedToItsMiddle() throws {
        // Orange outer quarters, blue middle half: filling a square keeps the middle.
        let wide = Self.image(width: 128, height: 64) { x, _ in (32..<96).contains(x) ? 0x2F5BC8 : 0xE07A2E }
        let image = try #require(RGBAImage(wide, side: 32))
        let swatches = ColorQuantizer.swatches(in: image)
        #expect(swatches.first.map { $0.weight > 0.9 } == true)
        #expect(swatches.first?.color.distance(to: RGBColor(hex: 0x2F5BC8).oklab) ?? 1 < 0.02)
    }

    @Test func translucentPixelsKeepTheirColour() throws {
        let image = try #require(RGBAImage(Self.image(width: 32, height: 32, alpha: 128) { _, _ in 0xE07A2E }, side: 32))
        let pixel = Array(image.bytes.prefix(4))
        #expect(abs(Int(pixel[0]) - 0xE0) <= 2 && abs(Int(pixel[1]) - 0x7A) <= 2 && abs(Int(pixel[2]) - 0x2E) <= 2)
        #expect(pixel[3] == 128)
    }
}
