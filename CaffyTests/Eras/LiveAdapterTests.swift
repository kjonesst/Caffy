import Foundation
import MediaPlayer
import Photos
import Testing
@testable import Caffy

/// Checks the real adapters against Apple's services and the device's photo
/// library. They need the network and photo access, so they only run when
/// asked:
///
///     TEST_RUNNER_CAFFY_LIVE_ADAPTERS=1 xcodebuild test … \
///         -only-testing:CaffyTests/LiveAdapterTests -parallel-testing-enabled NO
///
/// Grant photo access to the simulator first with
/// `xcrun simctl privacy <device> grant photos com.kjonesst.caffytest1`.
/// Each test writes what it found to `tmp/live-adapters.txt` in the app's
/// container, for a person to look over.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CAFFY_LIVE_ADAPTERS"] == "1"))
struct LiveAdapterTests {
    private static let report = FileManager.default.temporaryDirectory.appending(path: "live-adapters.txt")

    private static func note(_ line: String) {
        let existing = (try? String(contentsOf: report, encoding: .utf8)) ?? ""
        try? (existing + line + "\n").write(to: report, atomically: true, encoding: .utf8)
    }

    @Test(arguments: [
        (SamplePlace.sydney, "Sydney"),
        (SamplePlace.melbourne, "Melbourne"),
        (SamplePlace.hobart, "Hobart")
    ])
    func mapKitNamesCities(place: SamplePlace, expected: String) async {
        let result = await MapKitPlaceLookup().lookUp(place.coordinate)
        Self.note("MapKit \(place.name): \(result)")
        guard case .found(let name) = result else {
            Issue.record("No name for \(place.name): \(result)")
            return
        }
        #expect(name.locality == expected)
    }

    @Test func mapKitFindsNoTownAtSea() async {
        let result = await MapKitPlaceLookup().lookUp(Coordinate(latitude: -40, longitude: 160))
        Self.note("MapKit Tasman Sea: \(result)")
        #expect(result != .failed)
        if case .found(let name) = result {
            Issue.record("Expected no town in the Tasman Sea, got \(name.locality)")
        }
    }

    @Test func photoKitThumbnailsGiveReadablePalettes() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        Self.note("Photos access: \(status.rawValue)")
        try #require(status == .authorized || status == .limited, "Grant photo access to the simulator first")

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        Self.note("Photos in library: \(assets.count)")
        try #require(assets.count > 0, "The simulator's photo library is empty")

        let sampler = PhotoKitColorSampler()
        var samples: [PaletteBuilder.PhotoSample] = []
        for index in 0..<min(assets.count, 12) {
            let asset = assets.object(at: index)
            let image = await sampler.pixels(ofPhoto: asset.localIdentifier)
            let swatches = image.map(ColorQuantizer.swatches(in:)) ?? []
            let top = swatches.first.map { String(format: "L %.2f C %.2f, %.0f%%", $0.color.lightness, $0.color.chroma, $0.weight * 100) } ?? "none"
            let location = asset.location.map { String(format: "%.3f, %.3f", $0.coordinate.latitude, $0.coordinate.longitude) } ?? "no location"
            Self.note("Photo \(index): \(image.map { "\($0.width)×\($0.height)" } ?? "unreadable"), top colour \(top), \(location)")
            #expect(image?.width == 32 && image?.height == 32)
            samples.append(PaletteBuilder.PhotoSample(swatches: swatches, weight: 1))
        }

        let palette = PaletteBuilder.palette(photos: samples, fallbackKey: "live")
        let contrast = RGBColor(hex: palette.paperHex).contrastRatio(with: RGBColor(hex: palette.inkHex))
        Self.note(String(format: "Palette: paper %06X, ink %06X, tape %06X, contrast %.1f, preset %@",
                         palette.paperHex, palette.inkHex, palette.tapeHex, contrast,
                         EraPalette.presets.contains(palette) ? "yes" : "no"))
        #expect(contrast >= 4.5)
    }

    @Test func photoLocationsGetNames() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        try #require(status == .authorized || status == .limited, "Grant photo access to the simulator first")
        let assets = PHAsset.fetchAssets(with: .image, options: nil)
        var located: [Coordinate] = []
        assets.enumerateObjects { asset, _, _ in
            if let location = asset.location {
                located.append(Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
            }
        }
        Self.note("Located photos: \(located.count) of \(assets.count)")
        try #require(!located.isEmpty, "No photo in the library has a location")

        let namer = MapKitPlaceLookup.cachedNamer(cacheFile: nil)
        var named = 0
        for coordinate in located.prefix(5) {
            let name = await namer.name(for: coordinate)
            Self.note(String(format: "%.3f, %.3f → %@", coordinate.latitude, coordinate.longitude, name?.locality ?? "no name"))
            if name != nil { named += 1 }
        }
        #expect(named > 0)
    }

    /// The real music library through MediaPlayer. Run on an iPhone with
    /// Apple Music access granted: the simulator has no music library.
    @Test func mediaPlayerReadsLibrary() async throws {
        #if targetEnvironment(simulator)
        Self.note("MediaPlayer: skipped in the simulator")
        #else
        let status = MPMediaLibrary.authorizationStatus()
        Self.note("Media library access: \(status.rawValue)")
        try #require(status == .authorized, "Grant Apple Music access on the device first")

        let songs = try #require(await MediaPlayerLibraryReader().songs())
        let now = Date.now
        var ages: [ListeningCoverage.Age: Int] = [:]
        for date in songs.compactMap(\.lastPlayedDate) {
            ages[ListeningCoverage.Age.of(date, now: now), default: 0] += 1
        }
        Self.note("Library songs: \(songs.count), with a last-played date: \(songs.count { $0.lastPlayedDate != nil })")
        Self.note("Without a catalog id (empty or \"0\"): \(songs.count { $0.catalogID == nil })")
        Self.note("Last played: " + ListeningCoverage.Age.allCases.map { "\($0.label) \(ages[$0] ?? 0)" }.joined(separator: ", "))
        #expect(!songs.isEmpty)
        #endif
    }
}
