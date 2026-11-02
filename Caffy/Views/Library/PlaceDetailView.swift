import SwiftData
import SwiftUI

/// Shows one place: a header, a link to its playlist, and its moments.
struct PlaceDetailView: View {
    let place: Place

    var body: some View {
        List {
            Section {
                PlaceHeader(name: place.name, momentCount: place.moments.count)
            }

            if let playlist = place.playlist {
                Section("Playlist") {
                    NavigationLink(value: playlist) {
                        Label(playlist.name, systemImage: "music.note.list")
                    }
                }
            }

            Section("Moments") {
                ForEach(place.momentsNewestFirst) { moment in
                    MomentRow(date: moment.date, songs: moment.songs)
                }
            }
        }
        .navigationTitle(place.name)
    }
}

/// Photo and summary at the top of a place.
struct PlaceHeader: View {
    let name: String
    let momentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotoPlaceholder(seed: name)
                .frame(height: 180)
                .clipShape(.rect(cornerRadius: 16))
            Text("\(momentCount) moments")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview(traits: .sampleData) {
    @Previewable @Query var places: [Place]
    NavigationStack {
        if let place = places.first {
            PlaceDetailView(place: place)
        }
    }
}
