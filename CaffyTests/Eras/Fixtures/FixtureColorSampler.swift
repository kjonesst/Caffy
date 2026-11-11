import Foundation
@testable import Caffy

/// A `ColorSampler` that hands back solid-colour images.
struct FixtureColorSampler: ColorSampler {
    /// Each photo's colour as a hex number. Photos not listed can't be read.
    let colors: [String: UInt32]

    func pixels(ofPhoto id: String) async -> RGBAImage? {
        colors[id].map { FixtureImages.solid($0) }
    }
}

enum FixtureImages {
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
        let pixels = bytes.count / 4
        return RGBAImage(width: 8, height: pixels / 8, bytes: bytes)
    }
}
