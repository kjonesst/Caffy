import SwiftUI

/// The cream panel under an era: its songs, then a button to listen.
struct SongList: View {
    let songs: [Song]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(songs) { song in
                SongRow(song: song)
            }

            // Publishing to Apple Music comes later, so this does nothing yet.
            Button {} label: {
                Text("Listen in Apple Music")
                    .font(Theme.display(16))
                    .foregroundStyle(Theme.cream)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.ink)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(Theme.cream)
    }
}

/// One song: cover art, title on top, artist underneath.
struct SongRow: View {
    let song: Song

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: song.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                PhotoPlaceholder(seed: song.title, showsIcon: false)
            }
            .frame(width: 42, height: 42)
            .clipShape(.rect(cornerRadius: 2))

            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .font(Theme.display(16))
                    .foregroundStyle(Theme.ink)
                Text(song.artist)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.softInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) {
            Theme.hairline.frame(height: 1)
        }
        // Read title and artist together in VoiceOver.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SongList(songs: MockMusicProvider.songsByYear[2026] ?? [])
        .padding()
}
