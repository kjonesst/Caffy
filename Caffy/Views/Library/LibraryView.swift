import SwiftData
import SwiftUI

/// The two collections the Library tab can switch between.
///
/// `CaseIterable` gives us `allCases` to build the picker from, and
/// `Identifiable` lets `ForEach` loop over the cases.
enum LibrarySection: CaseIterable, Identifiable {
    case playlists
    case places

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .playlists: "Playlists"
        case .places: "Places"
        }
    }
}

/// The Library tab: a segmented switch between Caffy's playlists and places.
struct LibraryView: View {
    /// `@State` is storage this view owns. Changing it re-renders the view.
    @State private var section: LibrarySection = .playlists

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // `$section` is a binding: it lets the picker both read and
                // change the `section` value.
                Picker("Section", selection: $section) {
                    ForEach(LibrarySection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                switch section {
                case .playlists:
                    PlaylistList()
                case .places:
                    PlaceList()
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: CaffyPlaylist.self) { playlist in
                PlaylistDetailView(playlist: playlist)
            }
            .navigationDestination(for: Place.self) { place in
                PlaceDetailView(place: place)
            }
        }
    }
}

/// Every Caffy playlist, A to Z.
struct PlaylistList: View {
    @Query(sort: \CaffyPlaylist.name) private var playlists: [CaffyPlaylist]

    var body: some View {
        List(playlists) { playlist in
            NavigationLink(value: playlist) {
                LibraryRow(
                    title: playlist.name,
                    subtitle: playlist.place?.name ?? "",
                    seed: playlist.place?.name ?? playlist.name
                )
            }
        }
        .overlay {
            if playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists Yet",
                    systemImage: "music.note.list",
                    description: Text("Playlists appear here as Caffy discovers places.")
                )
            }
        }
    }
}

/// Every place Caffy knows about, A to Z.
struct PlaceList: View {
    @Query(sort: \Place.name) private var places: [Place]

    var body: some View {
        List(places) { place in
            NavigationLink(value: place) {
                LibraryRow(
                    title: place.name,
                    subtitle: String(localized: "\(place.moments.count) moments"),
                    seed: place.name
                )
            }
        }
        .overlay {
            if places.isEmpty {
                ContentUnavailableView(
                    "No Places Yet",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Places appear here as Caffy finds them in your photos.")
                )
            }
        }
    }
}

/// A list row with a small thumbnail, a title, and a subtitle.
struct LibraryRow: View {
    let title: String
    let subtitle: String
    let seed: String

    var body: some View {
        HStack(spacing: 12) {
            PhotoPlaceholder(seed: seed)
                .frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview(traits: .sampleData) {
    LibraryView()
}
