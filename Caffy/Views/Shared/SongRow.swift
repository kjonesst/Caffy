import SwiftUI

/// One song in a list: title on top, artist underneath.
struct SongRow: View {
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        // Read title and artist together in VoiceOver.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        SongRow(song: MockMusicProvider.catalog[0])
        SongRow(song: MockMusicProvider.catalog[1])
    }
}
