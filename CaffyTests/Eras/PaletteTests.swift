import Foundation
import Testing
@testable import Caffy

/// Tests for the colour maths, `ColorQuantizer` and `PaletteBuilder`.
struct PaletteTests {
    // MARK: - Fixtures

    private static let orange: UInt32 = 0xE07A2E
    private static let teal: UInt32 = 0x1F8A80
    private static let blue: UInt32 = 0x2F5BC8
    private static let green: UInt32 = 0x4F8A3A

    private static func swatches(_ hex: UInt32) -> [Swatch] {
        ColorQuantizer.swatches(in: FixtureImages.solid(hex))
    }

    private static func photo(_ hex: UInt32, weight: Double = 1) -> PaletteBuilder.PhotoSample {
        PaletteBuilder.PhotoSample(swatches: swatches(hex), weight: weight)
    }

    private static func oklab(_ hex: UInt32) -> OKLab { RGBColor(hex: hex).oklab }

    /// The angle between two hues, in radians, from 0 to π.
    private static func hueGap(_ a: OKLab, _ b: OKLab) -> Double {
        let gap = abs(a.hue - b.hue).truncatingRemainder(dividingBy: 2 * .pi)
        return min(gap, 2 * .pi - gap)
    }

    private static func contrast(_ palette: EraPalette) -> Double {
        RGBColor(hex: palette.paperHex).contrastRatio(with: RGBColor(hex: palette.inkHex))
    }

    // MARK: - Colour maths

    @Test func knownOKLabValues() {
        let red = Self.oklab(0xFF0000)
        #expect(abs(red.lightness - 0.62796) < 1e-4)
        #expect(abs(red.a - 0.22486) < 1e-4)
        #expect(abs(red.b - 0.12585) < 1e-4)

        let white = Self.oklab(0xFFFFFF)
        #expect(abs(white.lightness - 1) < 1e-4)
        #expect(white.chroma < 1e-4)
    }

    @Test(arguments: [0x000000, 0xFFFFFF, 0xA8492A, 0x5A5B2E, 0xE9B44C, 0x1F8A80, 0x808080] as [UInt32])
    func hexSurvivesTheRoundTrip(hex: UInt32) {
        #expect(Self.oklab(hex).rgb?.hex == hex)
    }

    @Test func contrastRatios() {
        let black = RGBColor(hex: 0x000000)
        let white = RGBColor(hex: 0xFFFFFF)
        #expect(abs(black.contrastRatio(with: white) - 21) < 1e-9)
        #expect(white.contrastRatio(with: white) == 1)
        #expect(black.contrastRatio(with: white) == white.contrastRatio(with: black))
    }

    @Test func outOfRangeColoursAreBroughtOnScreen() throws {
        // Far more colourful than any screen can show.
        let impossible = OKLab(lightness: 0.6, chroma: 0.5, hue: 2)
        #expect(impossible.rgb == nil)
        let shown = impossible.displayable.oklab
        #expect(abs(shown.lightness - 0.6) < 0.01)
        #expect(Self.hueGap(shown, impossible) < 0.02)
        #expect(shown.chroma < 0.5)
    }

    // MARK: - Presets

    @Test func presetsKeepTheirDesignedColours() {
        #expect(EraPalette.presets.map(\.paperHex) == [0xA8492A, 0x5A5B2E, 0xE9B44C, 0x5B2E2A])
        #expect(EraPalette.marigold.inkHex == 0x2E1C12)
        #expect(EraPalette.marigold.tapeHex == 0xFFF7EA)
    }

    @Test func presetsAreReadable() {
        for preset in EraPalette.presets {
            #expect(Self.contrast(preset) >= 4.5)
        }
    }

    // MARK: - Quantizer

    @Test func solidImageIsOneSwatch() throws {
        let found = Self.swatches(Self.orange)
        let swatch = try #require(found.first)
        #expect(found.count == 1)
        #expect(swatch.weight == 1)
        #expect(swatch.color.distance(to: Self.oklab(Self.orange)) < 1e-9)
    }

    @Test func twoColoursSplitTheWeight() {
        let found = ColorQuantizer.swatches(in: FixtureImages.stripes([(Self.orange, 48), (Self.blue, 16)]))
        #expect(found.map(\.weight) == [0.75, 0.25])
        #expect(found[0].color.distance(to: Self.oklab(Self.orange)) < 1e-9)
    }

    @Test func transparentPixelsAreIgnored() {
        let mostlyClear = ColorQuantizer.swatches(in: FixtureImages.stripes([(nil, 48), (Self.blue, 16)]))
        let allClear = ColorQuantizer.swatches(in: FixtureImages.stripes([(nil, 64)]))
        #expect(mostlyClear.map(\.weight) == [1])
        #expect(allClear.isEmpty)
    }

    @Test func nearbyShadesShareASwatch() {
        let found = ColorQuantizer.swatches(in: FixtureImages.stripes([(0xE07A2E, 32), (0xE27C30, 32)]))
        #expect(found.count == 1)
    }

    // MARK: - Choosing paper

    @Test func vividColourBecomesThePaper() {
        let palette = PaletteBuilder.palette(photos: [Self.photo(Self.orange)], fallbackKey: "era")
        let paper = RGBColor(hex: palette.paperHex).oklab
        #expect(Self.hueGap(paper, Self.oklab(Self.orange)) < 0.15)
        #expect(Self.contrast(palette) >= 4.5)
        // Light paper takes dark ink and cream tape, like the marigold preset.
        #expect(palette.inkHex == EraPalette.darkInkHex)
        #expect(palette.tapeHex == EraPalette.creamTape.hex)
    }

    @Test func commonAndVividBeatsRareOrDull() {
        // A beige wall covers most of the photo, but the orange is far more vivid.
        let photo = PaletteBuilder.PhotoSample(
            swatches: ColorQuantizer.swatches(in: FixtureImages.stripes([(0xC8B8A0, 48), (Self.orange, 16)])),
            weight: 1
        )
        let paper = RGBColor(hex: PaletteBuilder.palette(photos: [photo], fallbackKey: "era").paperHex).oklab
        #expect(Self.hueGap(paper, Self.oklab(Self.orange)) < 0.15)
    }

    @Test func paleColoursAreDeepenedAndDarkOnesLightened() {
        let pale = PaletteBuilder.palette(photos: [Self.photo(0xF0D060)], fallbackKey: "era")
        let dark = PaletteBuilder.palette(photos: [Self.photo(0x101830)], fallbackKey: "era")
        #expect(RGBColor(hex: pale.paperHex).oklab.lightness <= 0.76)
        #expect(RGBColor(hex: dark.paperHex).oklab.lightness >= 0.34)
        #expect(dark.inkHex == EraPalette.lightInkHex)
        #expect(dark.tapeHex == EraPalette.amberTape.hex)
    }

    @Test func greyPhotosFallBackToAPreset() {
        let palette = PaletteBuilder.palette(photos: [Self.photo(0x777777), Self.photo(0xEEEEEE)], fallbackKey: "m0042")
        #expect(palette == PaletteBuilder.fallback(key: "m0042"))
        #expect(EraPalette.presets.contains(palette))
    }

    @Test func noPhotosFallBackToAPreset() {
        #expect(EraPalette.presets.contains(PaletteBuilder.palette(photos: [], fallbackKey: "m0001")))
    }

    @Test func biggerMomentsCountMore() {
        let palette = PaletteBuilder.palette(
            photos: [Self.photo(Self.orange, weight: 1), Self.photo(Self.blue, weight: 5)],
            fallbackKey: "era"
        )
        #expect(Self.hueGap(RGBColor(hex: palette.paperHex).oklab, Self.oklab(Self.blue)) < 0.15)
    }

    // MARK: - Neighbours

    @Test func paletteDiffersFromThePreviousEra() {
        let photo = PaletteBuilder.PhotoSample(
            swatches: ColorQuantizer.swatches(in: FixtureImages.stripes([(Self.orange, 44), (Self.teal, 20)])),
            weight: 1
        )
        let alone = PaletteBuilder.palette(photos: [photo], fallbackKey: "era")
        let next = PaletteBuilder.palette(photos: [photo], avoiding: [alone], fallbackKey: "era")

        #expect(Self.hueGap(RGBColor(hex: alone.paperHex).oklab, Self.oklab(Self.orange)) < 0.15)
        #expect(Self.hueGap(RGBColor(hex: next.paperHex).oklab, Self.oklab(Self.teal)) < 0.15)
        let gap = RGBColor(hex: alone.paperHex).oklab.distance(to: RGBColor(hex: next.paperHex).oklab) * 100
        #expect(gap >= 12)
    }

    @Test func fallbackSkipsAPresetMatchingTheNeighbour() {
        let first = PaletteBuilder.fallback(key: "m0042")
        let next = PaletteBuilder.palette(photos: [], avoiding: [first], fallbackKey: "m0042")
        #expect(next != first)
        #expect(EraPalette.presets.contains(next))
    }

    // MARK: - Album art

    @Test func albumArtHelpsWhenPhotosAreDull() {
        let palette = PaletteBuilder.palette(photos: [Self.photo(0x808080)], albumArt: [Self.swatches(Self.blue)], fallbackKey: "era")
        #expect(Self.hueGap(RGBColor(hex: palette.paperHex).oklab, Self.oklab(Self.blue)) < 0.15)
    }

    @Test func photosOutweighAlbumArt() {
        let palette = PaletteBuilder.palette(photos: [Self.photo(Self.teal)], albumArt: [Self.swatches(Self.blue)], fallbackKey: "era")
        #expect(Self.hueGap(RGBColor(hex: palette.paperHex).oklab, Self.oklab(Self.teal)) < 0.15)
    }

    // MARK: - Guardrails hold for any colour

    @Test func everyPaletteIsReadable() {
        var random = SplitMix64(seed: 7)
        for _ in 0..<200 {
            let hex = UInt32(random.int(in: 0...0xFFFFFF))
            let second = UInt32(random.int(in: 0...0xFFFFFF))
            let photo = PaletteBuilder.PhotoSample(
                swatches: ColorQuantizer.swatches(in: FixtureImages.stripes([(hex, 40), (second, 24)])),
                weight: 1
            )
            let palette = PaletteBuilder.palette(photos: [photo], fallbackKey: "m\(hex)")
            #expect(Self.contrast(palette) >= 4.5, "Paper \(String(palette.paperHex, radix: 16)) from \(String(hex, radix: 16))")
            // Cream ink goes with amber tape, brown ink with cream tape.
            #expect((palette.inkHex == EraPalette.darkInkHex) == (palette.tapeHex == EraPalette.creamTape.hex))
        }
    }

    // MARK: - Sampling eras

    @Test func sampleIndices() {
        #expect(PaletteBuilder.sampleIndices(count: 5, limit: 12) == [0, 1, 2, 3, 4])
        let spread = PaletteBuilder.sampleIndices(count: 100, limit: 12)
        #expect(spread.count == 12)
        #expect(spread.first == 0 && spread.last == 99)
        #expect(spread == spread.sorted() && Set(spread).count == 12)
        #expect(PaletteBuilder.sampleIndices(count: 0, limit: 12).isEmpty)
    }

    /// Green photos at home in Sydney, blue ones in Melbourne.
    private static func weekendColours(_ scenario: Scenario) -> FixtureColorSampler {
        var colors: [String: UInt32] = [:]
        for moment in scenario.moments {
            let inMelbourne = moment.coordinate.map { $0.distance(to: FixturePlace.melbourne.coordinate) < 25_000 } ?? false
            colors[moment.coverID] = inMelbourne ? Self.blue : Self.green
        }
        return FixtureColorSampler(colors: colors)
    }

    @Test func erasTakeTheirColoursFromTheirOwnPhotos() async throws {
        let scenario = Scenario()
            .live(at: .sydney, days: 25)
            .trip(to: .melbourne, nights: 2)
            .live(at: .sydney, days: 21)
        let home = HomeInference.infer(scenario.moments, calendar: scenario.calendar)
        let drafts = EraSegmenter.segment(scenario.moments, home: home, now: scenario.now, calendar: scenario.calendar)
        let palettes = await PaletteBuilder.palettes(for: drafts, moments: scenario.moments, sampler: Self.weekendColours(scenario))

        let season = try #require(palettes[drafts[0].id])
        let trip = try #require(palettes[drafts[1].id])
        #expect(Self.hueGap(RGBColor(hex: season.paperHex).oklab, Self.oklab(Self.green)) < 0.15)
        #expect(Self.hueGap(RGBColor(hex: trip.paperHex).oklab, Self.oklab(Self.blue)) < 0.15)

        let again = await PaletteBuilder.palettes(for: drafts, moments: scenario.moments, sampler: Self.weekendColours(scenario))
        #expect(again == palettes)
    }

    @Test func unreadablePhotosGiveAPreset() async {
        let scenario = Scenario().live(at: .sydney, days: 30)
        let home = HomeInference.infer(scenario.moments, calendar: scenario.calendar)
        let drafts = EraSegmenter.segment(scenario.moments, home: home, now: scenario.now, calendar: scenario.calendar)
        let palettes = await PaletteBuilder.palettes(for: drafts, moments: scenario.moments, sampler: FixtureColorSampler(colors: [:]))
        #expect(palettes.values.allSatisfy { EraPalette.presets.contains($0) })
    }
}
