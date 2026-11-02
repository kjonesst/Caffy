import SwiftData
import SwiftUI

/// The Home tab: recently updated playlists, then a collage of recent moments.
struct HomeView: View {
    /// `@Query` fetches from SwiftData and re-renders the view when the data
    /// changes. These two keep moments and playlists newest-first.
    @Query(sort: \Moment.date, order: .reverse) private var moments: [Moment]
    @Query(sort: \CaffyPlaylist.lastUpdated, order: .reverse) private var playlists: [CaffyPlaylist]

    var body: some View {
        // `NavigationStack` lets views push detail pages with `NavigationLink`.
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !playlists.isEmpty {
                        RecentPlaylistsSection(playlists: Array(playlists.prefix(5)))
                    }
                    MomentsCollage(moments: moments)
                }
                .padding()
            }
            .navigationTitle("Caffy")
            // When a `NavigationLink(value:)` is tapped, these decide which
            // page to show for that type of value.
            .navigationDestination(for: CaffyPlaylist.self) { playlist in
                PlaylistDetailView(playlist: playlist)
            }
            .navigationDestination(for: Place.self) { place in
                PlaceDetailView(place: place)
            }
        }
    }
}

#Preview(traits: .sampleData) {
    HomeView()
}
