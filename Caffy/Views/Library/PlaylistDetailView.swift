import SwiftData
import SwiftUI

/// Shows one playlist: a header, its songs, and the moments they came from.
struct PlaylistDetailView: View {
    let playlist: CaffyPlaylist

    var body: some View {
        // `songs` is computed, so read it once rather than in two places.
        let songs = playlist.songs

        List {
            Section {
                PlaylistHeader(
                    placeName: playlist.place?.name ?? playlist.name,
                    songCount: songs.count,
                    lastUpdated: playlist.lastUpdated
                )
            }

            Section("Songs") {
                ForEach(songs) { song in
                    SongRow(song: song)
                }
            }

            if let place = playlist.place {
                Section("From These Moments") {
                    ForEach(place.momentsNewestFirst) { moment in
                        MomentRow(date: moment.date, songs: moment.songs)
                    }
                }
            }
        }
        .navigationTitle(playlist.name)
    }
}

/// Artwork and summary at the top of a playlist.
struct PlaylistHeader: View {
    let placeName: String
    let songCount: Int
    let lastUpdated: Date

    var body: some View {
        VStack(spacing: 12) {
            PhotoPlaceholder(seed: placeName)
                .frame(width: 180, height: 180)
                .clipShape(.rect(cornerRadius: 16))
            Text(placeName)
                .font(.headline)
            Text("\(songCount) songs · Updated \(lastUpdated, format: .relative(presentation: .named))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview(traits: .sampleData) {
    @Previewable @Query var playlists: [CaffyPlaylist]
    NavigationStack {
        if let playlist = playlists.first {
            PlaylistDetailView(playlist: playlist)
        }
    }
}
