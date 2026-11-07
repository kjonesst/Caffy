import SwiftUI

/// The cream panel of an era's songs.
struct SongList: View {
    let songs: [Song]
    /// Puts a plain listen button above the songs. Home leaves this off, because
    /// its cards have `ListenPill` instead.
    var showsListenButton = false

    var body: some View {
        VStack(spacing: 0) {
            if showsListenButton {
                // Publishing to Apple Music comes later, so this does nothing yet.
                Button {} label: {
                    Text("Listen in Apple Music")
                        .font(Theme.display(16))
                        .foregroundStyle(Theme.cream)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.ink)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)
            }

            ForEach(songs) { song in
                SongRow(song: song)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, showsListenButton ? 10 : 4)
        .padding(.bottom, showsListenButton ? 4 : 6)
        .background(Theme.cream)
    }
}

/// The big listen button on an era's card, printed in the era's colours.
struct ListenPill: View {
    let palette: EraPalette

    var body: some View {
        // Publishing to Apple Music comes later, so this does nothing yet.
        Button {} label: {
            HStack(spacing: 14) {
                Image(systemName: "play.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.ink)
                    .frame(width: 48, height: 48)
                    .background(palette.paper, in: .circle)

                Text("Listen in Apple Music")
                    .font(Theme.display(20, weight: .heavy))
                    .tracking(-0.2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(palette.paper)
            .padding(.leading, 8)
            .padding(.trailing, 22)
            .padding(.vertical, 8)
            .frame(minHeight: 64)
            .background {
                // The inner shadow is the thin highlight along the top edge.
                Capsule()
                    .fill(palette.ink.shadow(.inner(color: .white.opacity(0.35), radius: 0, y: 1)))
                    .shadow(color: Color(hex: 0x281206).opacity(0.34), radius: 11, y: 10)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
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
    VStack {
        ListenPill(palette: .rust)
        SongList(songs: MockMusicProvider.songsByYear[2026] ?? [], showsListenButton: true)
    }
    .padding()
}
