import Foundation

/// A small image's pixels: 8-bit red, green, blue and alpha, row by row.
nonisolated struct RGBAImage: Sendable {
    let width: Int
    let height: Int
    /// `width × height × 4` bytes, with straight (not premultiplied) alpha.
    let bytes: [UInt8]
}

/// One colour found in an image, and how much of the image it covers.
nonisolated struct Swatch: Hashable, Sendable {
    let color: OKLab
    /// The share of the image's visible pixels, from 0 to 1.
    let weight: Double
}

/// Gets the pixels of photos and album art for working out palettes.
///
/// The app's version reads small thumbnails through PhotoKit; tests hand
/// back made-up pixels.
nonisolated protocol ColorSampler: Sendable {
    /// A small (about 32 × 32) copy of the photo, or `nil` if it can't be read.
    func pixels(ofPhoto id: String) async -> RGBAImage?
}

/// Finds the main colours in an image.
///
/// Pixels are sorted into fixed bins by lightness, colourfulness and hue in
/// OKLab, and each bin's average colour becomes a swatch. Fixed bins (rather
/// than k-means) give the same answer every time, with no random start.
nonisolated enum ColorQuantizer {
    /// Lightness is split into this many equal bins.
    private static let lightnessBins = 6
    /// Below this chroma a pixel counts as grey and ignores hue.
    private static let greyChroma = 0.03
    /// Chroma bins for colourful pixels: 0.03–0.08, 0.08–0.15 and above.
    private static let chromaEdges = [0.08, 0.15]
    private static let hueBins = 12

    /// The image's swatches, biggest first. Pixels less than half opaque are
    /// left out, and the weights of the rest add up to 1.
    static func swatches(in image: RGBAImage) -> [Swatch] {
        let colourBins = (chromaEdges.count + 1) * hueBins
        // One bin per lightness for greys, after the colourful ones.
        let binsPerLightness = colourBins + 1
        var counts = Array(repeating: 0, count: lightnessBins * binsPerLightness)
        var sums = Array(repeating: (l: 0.0, a: 0.0, b: 0.0), count: counts.count)
        var visible = 0

        let pixelCount = min(image.width * image.height, image.bytes.count / 4)
        for pixel in 0..<pixelCount {
            let offset = pixel * 4
            guard image.bytes[offset + 3] >= 128 else { continue }
            let color = oklab(image.bytes[offset], image.bytes[offset + 1], image.bytes[offset + 2])

            let lightnessBin = min(lightnessBins - 1, max(0, Int(color.lightness * Double(lightnessBins))))
            let chroma = color.chroma
            let bin: Int
            if chroma < greyChroma {
                bin = colourBins
            } else {
                let chromaBin = chromaEdges.firstIndex { chroma < $0 } ?? chromaEdges.count
                let turn = (color.hue + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi) / (2 * .pi)
                let hueBin = min(hueBins - 1, Int(turn * Double(hueBins)))
                bin = chromaBin * hueBins + hueBin
            }
            let index = lightnessBin * binsPerLightness + bin
            counts[index] += 1
            sums[index].l += color.lightness
            sums[index].a += color.a
            sums[index].b += color.b
            visible += 1
        }
        guard visible > 0 else { return [] }

        return counts.indices
            .filter { counts[$0] > 0 }
            .sorted { (counts[$1], $0) < (counts[$0], $1) }
            .map { index in
                let count = Double(counts[index])
                return Swatch(
                    color: OKLab(lightness: sums[index].l / count, a: sums[index].a / count, b: sums[index].b / count),
                    weight: count / Double(visible)
                )
            }
    }

    /// The sRGB curve for each byte value, worked out once.
    private static let linearByByte: [Double] = (0...255).map { RGBColor.toLinear(Double($0) / 255) }

    private static func oklab(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> OKLab {
        OKLab(linearRed: linearByByte[Int(red)], green: linearByByte[Int(green)], blue: linearByByte[Int(blue)])
    }
}
