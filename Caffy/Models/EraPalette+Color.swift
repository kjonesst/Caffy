import SwiftUI

/// The palette's colours for views. Kept apart from `EraPalette` so the era
/// pipeline, which builds palettes, doesn't depend on SwiftUI.
extension EraPalette {
    var paper: Color { Color(hex: paperHex) }
    var ink: Color { Color(hex: inkHex) }
    var tape: Color { Color(hex: tapeHex).opacity(tapeOpacity) }
}
