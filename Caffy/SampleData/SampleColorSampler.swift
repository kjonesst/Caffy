import Foundation

/// A `ColorSampler` that hands back made-up images, for sample data and
/// tests, where there are no real photos to read.
nonisolated struct SampleColorSampler: ColorSampler {
    /// Each photo's pixels. Photos not listed can't be read.
    let images: [String: RGBAImage]

    init(images: [String: RGBAImage]) {
        self.images = images
    }

    /// Each photo as one solid colour, given as a hex number.
    init(colors: [String: UInt32]) {
        images = colors.mapValues { SampleImages.solid($0) }
    }

    func pixels(ofPhoto id: String) async -> RGBAImage? {
        images[id]
    }
}

nonisolated enum SampleImages {
    /// An 8 × 8 image of one colour.
    static func solid(_ hex: UInt32) -> RGBAImage {
        stripes([(hex, 64)])
    }

    /// An 8-pixel-wide image made of runs of colours, top to bottom, with
    /// `count` pixels each. `nil` makes transparent pixels.
    static func stripes(_ runs: [(hex: UInt32?, count: Int)]) -> RGBAImage {
        var bytes: [UInt8] = []
        for (hex, count) in runs {
            for _ in 0..<count {
                if let hex {
                    bytes += [UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF), 255]
                } else {
                    bytes += [0, 0, 0, 0]
                }
            }
        }
        return RGBAImage(width: 8, height: bytes.count / 4 / 8, bytes: bytes)
    }
}
