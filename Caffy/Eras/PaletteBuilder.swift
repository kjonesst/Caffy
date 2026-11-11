import Foundation

/// Works out an era's colours from its photos (and, optionally, album art).
///
/// A pure function: the same swatches always give the same palette.
///
/// 1. Swatches from every sampled photo are weighted by the photo's moment
///    size, album art by `albumArtWeight`, and similar colours are merged.
/// 2. Near-white, near-black and grey colours are dropped, and the rest are
///    ranked by `weight × chroma`, so a colour that is both common and vivid
///    wins over the beige of a wall.
/// 3. The winner is pulled into the "printed paper" range
///    (`paperLightness`, `paperChroma`), keeping its hue.
/// 4. Ink is cream or dark brown, whichever reads better. If neither reaches
///    `minInkContrast`, the paper is darkened or lightened until one does.
/// 5. A palette too close to the previous era's (`minNeighbourDeltaE`) is
///    skipped for the next candidate. With no usable colour at all (black
///    and white photos), one of the designed presets is picked by era id.
nonisolated enum PaletteBuilder {
    /// One sampled photo's swatches and how much the photo counts.
    struct PhotoSample: Sendable {
        let swatches: [Swatch]
        /// The number of photos in its moment, so bigger moments count more.
        let weight: Double
    }

    /// Swatches closer than this (OKLab distance) merge into one candidate.
    private static let mergeDistance = 0.08
    /// Candidates outside this lightness, or below this chroma, can't be paper.
    private static let usableLightness = 0.15...0.92
    private static let usableChroma = 0.03

    // MARK: - One era

    static func palette(
        photos: [PhotoSample],
        albumArt: [[Swatch]] = [],
        avoiding neighbours: [EraPalette] = [],
        fallbackKey: String,
        config: EraBuildConfig = .standard
    ) -> EraPalette {
        let neighbourPapers = neighbours.map { RGBColor(hex: $0.paperHex).oklab }
        func isDistinct(_ palette: EraPalette) -> Bool {
            let paper = RGBColor(hex: palette.paperHex).oklab
            return neighbourPapers.allSatisfy { paper.distance(to: $0) * 100 >= config.minNeighbourDeltaE }
        }

        for candidate in candidates(photos: photos, albumArt: albumArt, config: config) {
            let paper = OKLab(
                lightness: min(max(candidate.lightness, config.paperLightness.lowerBound), config.paperLightness.upperBound),
                chroma: min(max(candidate.chroma, config.paperChroma.lowerBound), config.paperChroma.upperBound),
                hue: candidate.hue
            )
            let palette = finish(paper: paper, config: config)
            if isDistinct(palette) {
                return palette
            }
        }
        return fallback(key: fallbackKey, where: isDistinct)
    }

    /// Possible paper colours, best first.
    private static func candidates(photos: [PhotoSample], albumArt: [[Swatch]], config: EraBuildConfig) -> [OKLab] {
        let hasPhotos = photos.contains { !$0.swatches.isEmpty && $0.weight > 0 }
        let artShare = albumArt.isEmpty ? 0 : (hasPhotos ? config.albumArtWeight : 1)
        let photoShare = 1 - artShare

        var weighted: [Swatch] = []
        let totalPhotoWeight = photos.filter { !$0.swatches.isEmpty }.reduce(0) { $0 + max(0, $1.weight) }
        if totalPhotoWeight > 0 {
            for photo in photos where !photo.swatches.isEmpty {
                let share = photoShare * max(0, photo.weight) / totalPhotoWeight
                weighted += photo.swatches.map { Swatch(color: $0.color, weight: $0.weight * share) }
            }
        }
        for art in albumArt {
            let share = artShare / Double(albumArt.count)
            weighted += art.map { Swatch(color: $0.color, weight: $0.weight * share) }
        }

        // Merge similar colours, heaviest first, into weighted averages.
        let ordered = weighted.sorted {
            ($1.weight, $0.color.lightness, $0.color.a, $0.color.b) < ($0.weight, $1.color.lightness, $1.color.a, $1.color.b)
        }
        var groups: [(seed: OKLab, l: Double, a: Double, b: Double, weight: Double)] = []
        for swatch in ordered where swatch.weight > 0 {
            if let index = groups.firstIndex(where: { $0.seed.distance(to: swatch.color) < mergeDistance }) {
                groups[index].l += swatch.color.lightness * swatch.weight
                groups[index].a += swatch.color.a * swatch.weight
                groups[index].b += swatch.color.b * swatch.weight
                groups[index].weight += swatch.weight
            } else {
                groups.append((
                    swatch.color,
                    swatch.color.lightness * swatch.weight,
                    swatch.color.a * swatch.weight,
                    swatch.color.b * swatch.weight,
                    swatch.weight
                ))
            }
        }

        return groups
            .map { (color: OKLab(lightness: $0.l / $0.weight, a: $0.a / $0.weight, b: $0.b / $0.weight), weight: $0.weight) }
            .filter { usableLightness.contains($0.color.lightness) && $0.color.chroma >= usableChroma }
            .map { (color: $0.color, score: $0.weight * $0.color.chroma) }
            .sorted { ($1.score, $0.color.lightness) < ($0.score, $1.color.lightness) }
            .map(\.color)
    }

    /// Chooses ink and tape for `paper`, adjusting the paper's lightness
    /// until the ink is readable.
    static func finish(paper: OKLab, config: EraBuildConfig = .standard) -> EraPalette {
        let lightInk = RGBColor(hex: EraPalette.lightInkHex)
        let darkInk = RGBColor(hex: EraPalette.darkInkHex)

        // Contrast is checked on the saved (hex) colour, which is what's shown.
        func rounded(_ color: OKLab) -> RGBColor { RGBColor(hex: color.displayable.hex) }
        var current = paper
        var shown = rounded(current)
        let useLightInk = shown.contrastRatio(with: lightInk) >= shown.contrastRatio(with: darkInk)
        let ink = useLightInk ? lightInk : darkInk

        // Step towards darker paper for cream ink, lighter for brown, in
        // small fixed steps so the result is always the same.
        var steps = 0
        while shown.contrastRatio(with: ink) < config.minInkContrast, steps < 100 {
            let lightness = current.lightness + (useLightInk ? -0.01 : 0.01)
            guard (0.05...0.98).contains(lightness) else { break }
            current = OKLab(lightness: lightness, chroma: current.chroma, hue: current.hue)
            shown = rounded(current)
            steps += 1
        }

        let tape = useLightInk ? EraPalette.amberTape : EraPalette.creamTape
        return EraPalette(paperHex: shown.hex, inkHex: ink.hex, tapeHex: tape.hex, tapeOpacity: tape.opacity)
    }

    /// A designed preset chosen by `key`, moving on to the next preset if it
    /// isn't distinct from the neighbours.
    static func fallback(key: String, where isDistinct: (EraPalette) -> Bool = { _ in true }) -> EraPalette {
        let presets = EraPalette.presets
        let first = StableHash.index(for: key, count: presets.count)
        for offset in 0..<presets.count {
            let preset = presets[(first + offset) % presets.count]
            if isDistinct(preset) { return preset }
        }
        return presets[first]
    }

    // MARK: - Every era

    /// Which of `count` moments to sample: all of them up to `limit`,
    /// otherwise `limit` spread evenly from first to last.
    static func sampleIndices(count: Int, limit: Int) -> [Int] {
        guard count > limit else { return Array(0..<count) }
        guard limit > 1 else { return limit == 1 ? [count / 2] : [] }
        return (0..<limit).map { Int((Double($0) * Double(count - 1) / Double(limit - 1)).rounded()) }
    }

    /// A palette for every draft, keyed by draft id.
    ///
    /// Eras are done oldest first so each can avoid the colour of the era
    /// before it. Cover photos are read one at a time, in order.
    static func palettes(
        for drafts: [EraDraft],
        moments: [PhotoMoment],
        sampler: some ColorSampler,
        config: EraBuildConfig = .standard
    ) async -> [String: EraPalette] {
        let byID = Dictionary(moments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var palettes: [String: EraPalette] = [:]
        var previous: EraPalette?

        for draft in drafts.sorted(by: { ($0.start, $0.id) < ($1.start, $1.id) }) {
            let eraMoments = draft.momentIDs.compactMap { byID[$0] }
            var samples: [PhotoSample] = []
            for index in sampleIndices(count: eraMoments.count, limit: config.paletteSampleMoments) {
                let moment = eraMoments[index]
                guard let image = await sampler.pixels(ofPhoto: moment.coverID) else { continue }
                samples.append(PhotoSample(swatches: ColorQuantizer.swatches(in: image), weight: Double(moment.photoIDs.count)))
            }
            let palette = palette(photos: samples, avoiding: previous.map { [$0] } ?? [], fallbackKey: draft.id, config: config)
            palettes[draft.id] = palette
            previous = palette
        }
        return palettes
    }
}
