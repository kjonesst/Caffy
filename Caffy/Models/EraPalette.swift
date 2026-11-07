import SwiftUI

/// The colours an era's card is printed in.
///
/// `nonisolated` lets SwiftData encode and decode this from any thread.
nonisolated enum EraPalette: String, Codable, CaseIterable {
    case rust
    case olive
    case marigold
    case oxblood

    var paper: Color {
        switch self {
        case .rust: Color(hex: 0xA8492A)
        case .olive: Color(hex: 0x5A5B2E)
        case .marigold: Color(hex: 0xE9B44C)
        case .oxblood: Color(hex: 0x5B2E2A)
        }
    }

    var ink: Color {
        switch self {
        case .rust: Color(hex: 0xFFF3E2)
        case .olive: Color(hex: 0xFFF5DE)
        case .marigold: Color(hex: 0x2E1C12)
        case .oxblood: Color(hex: 0xFFEFE0)
        }
    }

    var tape: Color {
        switch self {
        case .marigold: Color(hex: 0xFFF7EA).opacity(0.78)
        case .rust, .olive, .oxblood: Color(hex: 0xF4CD82).opacity(0.82)
        }
    }
}
