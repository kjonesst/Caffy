import Foundation

/// The colours an era's card is printed in.
///
/// Colours are stored as hex numbers so SwiftData can save them (views read
/// them as `Color`s, see `EraPalette+Color.swift`), and each era
/// can have its own palette taken from its photos (see `PaletteBuilder`).
/// The four designed palettes stay available as presets.
///
/// `nonisolated` lets SwiftData encode and decode this from any thread.
nonisolated struct EraPalette: Codable, Hashable, Sendable {
    /// The card's background.
    var paperHex: UInt32
    /// Text and icons on the card.
    var inkHex: UInt32
    /// The strips of tape holding photos down.
    var tapeHex: UInt32
    var tapeOpacity: Double

    // MARK: - Presets

    /// Cream text, for dark paper.
    static let lightInkHex: UInt32 = 0xFFF3E2
    /// Dark brown text, for light paper.
    static let darkInkHex: UInt32 = 0x2E1C12

    /// Amber tape, for dark paper.
    static let amberTape = (hex: UInt32(0xF4CD82), opacity: 0.82)
    /// Cream tape, for light paper.
    static let creamTape = (hex: UInt32(0xFFF7EA), opacity: 0.78)

    static let rust = EraPalette(paperHex: 0xA8492A, inkHex: lightInkHex, tapeHex: amberTape.hex, tapeOpacity: amberTape.opacity)
    static let olive = EraPalette(paperHex: 0x5A5B2E, inkHex: 0xFFF5DE, tapeHex: amberTape.hex, tapeOpacity: amberTape.opacity)
    static let marigold = EraPalette(paperHex: 0xE9B44C, inkHex: darkInkHex, tapeHex: creamTape.hex, tapeOpacity: creamTape.opacity)
    static let oxblood = EraPalette(paperHex: 0x5B2E2A, inkHex: 0xFFEFE0, tapeHex: amberTape.hex, tapeOpacity: amberTape.opacity)

    /// The designed palettes, used when an era's photos don't give a usable colour.
    static let presets: [EraPalette] = [.rust, .olive, .marigold, .oxblood]
}
