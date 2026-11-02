import SwiftUI

/// Stands in for a real photo until PhotoKit is connected.
///
/// It draws a gradient whose colours are picked from `seed`, so each place
/// always gets the same look.
struct PhotoPlaceholder: View {
    let seed: String

    private static let palettes: [[Color]] = [
        [.orange, .pink],
        [.teal, .blue],
        [.purple, .indigo],
        [.green, .mint],
        [.yellow, .orange],
        [.cyan, .purple]
    ]

    var body: some View {
        LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .accessibilityHidden(true)
    }

    /// Adds up the seed's characters to choose a palette. (`String.hashValue`
    /// changes on every launch, so it can't be used for a stable choice.)
    private var palette: [Color] {
        let total = seed.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.palettes[total % Self.palettes.count]
    }
}

#Preview {
    PhotoPlaceholder(seed: "Bondi Beach")
        .frame(width: 200, height: 140)
        .clipShape(.rect(cornerRadius: 12))
}
