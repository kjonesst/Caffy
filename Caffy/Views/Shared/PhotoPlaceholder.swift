import SwiftUI

/// Stands in for a real photo or album cover until PhotoKit and MusicKit are
/// connected.
///
/// It draws a flat tone picked from `seed`, so each item keeps the same look.
struct PhotoPlaceholder: View {
    let seed: String
    var showsIcon = true

    private static let tones: [Color] = [
        Color(hex: 0xD9A06B),
        Color(hex: 0x8C9A6A),
        Color(hex: 0xC97B5A),
        Color(hex: 0x7F8FA3),
        Color(hex: 0xB9A27A),
        Color(hex: 0xA5705C)
    ]

    var body: some View {
        tone
            .overlay {
                if showsIcon {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(Theme.cream.opacity(0.75))
                }
            }
            .accessibilityHidden(true)
    }

    /// Adds up the seed's characters to choose a tone. (`String.hashValue`
    /// changes on every launch, so it can't be used for a stable choice.)
    private var tone: Color {
        let total = seed.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.tones[total % Self.tones.count]
    }
}

#Preview {
    PhotoPlaceholder(seed: "Bondi Beach")
        .frame(width: 200, height: 140)
}
