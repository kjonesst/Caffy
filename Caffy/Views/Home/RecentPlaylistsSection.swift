import SwiftUI

/// A horizontally scrolling row of playlists that were updated recently.
struct RecentPlaylistsSection: View {
    let playlists: [CaffyPlaylist]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently Updated")
                .font(.title2.bold())

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: playlist) {
                            PlaylistTile(
                                name: playlist.name,
                                placeName: playlist.place?.name ?? playlist.name,
                                lastUpdated: playlist.lastUpdated
                            )
                        }
                        // Stops the whole tile from being tinted like a button.
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// A small square tile for one playlist.
struct PlaylistTile: View {
    let name: String
    let placeName: String
    let lastUpdated: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PhotoPlaceholder(seed: placeName)
                .frame(width: 140, height: 140)
                .clipShape(.rect(cornerRadius: 12))
            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("Updated \(lastUpdated, format: .relative(presentation: .named))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 140, alignment: .leading)
    }
}
