import SwiftUI

/// A two-column grid of moment cards, each pairing a photo with its music.
struct MomentsCollage: View {
    let moments: [Moment]

    /// Two equal-width columns. `LazyVGrid` only builds the cards on screen.
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Moments")
                .font(.title2.bold())

            if moments.isEmpty {
                ContentUnavailableView(
                    "No Moments Yet",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Caffy will add moments from your photos and listening.")
                )
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(moments) { moment in
                        // Tapping a card opens the place it was captured at.
                        NavigationLink(value: moment.place) {
                            MomentCard(
                                placeName: moment.place?.name ?? String(localized: "Unknown Place"),
                                date: moment.date,
                                songs: Array(moment.songs.prefix(2))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// One card in the collage: photo, place, date, and a couple of songs.
struct MomentCard: View {
    let placeName: String
    let date: Date
    let songs: [Song]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotoPlaceholder(seed: placeName)
                .frame(height: 140)
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(placeName)
                    .font(.headline)
                    .lineLimit(1)
                Text(date, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(songs) { song in
                    Label(song.title, systemImage: "music.note")
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
