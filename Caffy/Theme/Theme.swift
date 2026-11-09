import CoreText
import SwiftUI

/// Caffy's shared colours and type, taken from the design.
enum Theme {
    /// Paper and ink. These stay the same in light and dark mode, because the
    /// design is printed on warm paper.
    static let cream = Color(hex: 0xFFF7EA)
    static let ink = Color(hex: 0x2E1C12)
    static let softInk = Color(hex: 0x6A5644)
    static let hairline = Color(hex: 0xEADCC6)
    static let rulerLine = Color(hex: 0x8A6A2F)
    static let shadow = Color(red: 60 / 255, green: 30 / 255, blue: 10 / 255)

    /// The Welcome screen's night look. It's the one place that changes in
    /// dark mode: espresso instead of paper, bone instead of ink.
    static let espresso = Color(hex: 0x1C130D)
    static let bone = Color(hex: 0xD6D2CA)
    static let softBone = Color(hex: 0xA89A88)

    /// Headlines and body text. `relativeTo` scales it with Dynamic Type.
    static func display(_ size: CGFloat, weight: Font.Weight = .medium, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Bricolage Grotesque", size: size, relativeTo: style).weight(weight)
    }

    /// Small labels and metadata.
    static func mono(_ size: CGFloat, medium: Bool = false, relativeTo style: Font.TextStyle = .caption) -> Font {
        .custom(medium ? "DMMono-Medium" : "DMMono-Regular", size: size, relativeTo: style)
    }

    /// The handwritten dates on each era.
    static func handwritten(_ size: CGFloat) -> Font {
        .custom("ReenieBeanie", size: size, relativeTo: .title2)
    }

    /// Loads the fonts in `Resources/Fonts`. Registering them here means the
    /// generated Info.plist doesn't need a list of font files.
    static func registerFonts() {
        let names = ["BricolageGrotesque-Variable", "DMMono-Regular", "DMMono-Medium", "ReenieBeanie"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                assertionFailure("Missing font: \(name)")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Color {
    /// A colour from a hex number, such as `0xFFF7EA`.
    nonisolated init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
