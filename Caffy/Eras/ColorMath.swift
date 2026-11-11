import Foundation

/// A colour in sRGB, each channel from 0 to 1.
///
/// Plain maths with no UIKit or SwiftUI, so palettes can be worked out and
/// tested anywhere.
nonisolated struct RGBColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// A colour from a hex number, such as `0xA8492A`.
    init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    /// The nearest hex colour, each channel clamped to 0...255.
    var hex: UInt32 {
        func byte(_ value: Double) -> UInt32 { UInt32(min(255, max(0, (value * 255).rounded()))) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }

    /// How bright the colour looks, from 0 (black) to 1 (white), as WCAG
    /// defines it.
    var relativeLuminance: Double {
        let (r, g, b) = linear
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// The WCAG contrast ratio, from 1 (the same) to 21 (black on white).
    func contrastRatio(with other: RGBColor) -> Double {
        let a = relativeLuminance
        let b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    var oklab: OKLab {
        let (r, g, b) = linear
        return OKLab(linearRed: r, green: g, blue: b)
    }

    /// The channels with the sRGB curve removed, so they add up like light.
    var linear: (Double, Double, Double) {
        (Self.toLinear(red), Self.toLinear(green), Self.toLinear(blue))
    }

    static func toLinear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    static func fromLinear(_ channel: Double) -> Double {
        channel <= 0.0031308 ? channel * 12.92 : 1.055 * pow(channel, 1 / 2.4) - 0.055
    }
}

/// A colour in OKLab, a colour space where equal distances look about equally
/// different. Lightness runs from 0 (black) to 1 (white); `a` and `b` are the
/// green–red and blue–yellow axes.
///
/// From Björn Ottosson, "A perceptual color space for image processing" (2020).
nonisolated struct OKLab: Hashable, Sendable {
    let lightness: Double
    let a: Double
    let b: Double

    init(lightness: Double, a: Double, b: Double) {
        self.lightness = lightness
        self.a = a
        self.b = b
    }

    /// A colour from linear (not gamma-encoded) sRGB channels.
    init(linearRed r: Double, green g: Double, blue b: Double) {
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        self.init(
            lightness: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    /// A colour from lightness, chroma (colourfulness) and hue (radians).
    init(lightness: Double, chroma: Double, hue: Double) {
        self.init(lightness: lightness, a: chroma * cos(hue), b: chroma * sin(hue))
    }

    /// How colourful it is: 0 for greys, about 0.3 for the most vivid sRGB colours.
    var chroma: Double { (a * a + b * b).squareRoot() }

    /// The hue angle in radians, from −π to π.
    var hue: Double { atan2(b, a) }

    /// How different two colours look. About 0.02 is just noticeable.
    func distance(to other: OKLab) -> Double {
        let dl = lightness - other.lightness
        let da = a - other.a
        let db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    /// The sRGB colour, or `nil` if this colour can't be shown on screen.
    var rgb: RGBColor? {
        let (r, g, b) = linear
        let tolerance = 1e-6
        guard [r, g, b].allSatisfy({ $0 >= -tolerance && $0 <= 1 + tolerance }) else { return nil }
        return RGBColor(
            red: RGBColor.fromLinear(min(1, max(0, r))),
            green: RGBColor.fromLinear(min(1, max(0, g))),
            blue: RGBColor.fromLinear(min(1, max(0, b)))
        )
    }

    /// The nearest colour that can be shown on screen with the same lightness
    /// and hue, found by lowering chroma until it fits.
    var displayable: RGBColor {
        if let rgb { return rgb }
        var low = 0.0
        var high = chroma
        // A fixed number of halvings, so the answer never depends on timing.
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if OKLab(lightness: lightness, chroma: middle, hue: hue).rgb != nil {
                low = middle
            } else {
                high = middle
            }
        }
        let clampedLightness = min(1, max(0, lightness))
        return OKLab(lightness: clampedLightness, chroma: low, hue: hue).rgb
            ?? RGBColor(red: clampedLightness, green: clampedLightness, blue: clampedLightness)
    }

    private var linear: (Double, Double, Double) {
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }
}
