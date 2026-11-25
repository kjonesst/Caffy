import SwiftUI

/// The "Caffinated" album, shown inside Caffy: every published playlist's
/// cover photo, newest first, with the current era's marked.
///
/// iOS has no public way to open a given album in the Photos app, so the
/// cover guide shows the album here instead. The photos are read live from
/// the Photos library (`CoverAlbum.photos()`), so what's shown is what
/// Apple Music's photo picker will find under Albums.
struct CoverAlbumSheet: View {
    /// The photo to mark: the era's cover.
    let highlightID: String
    let palette: EraPalette
    var album: any CoverAlbum = PhotoKitCoverAlbum()

    @Environment(\.dismiss) private var dismiss
    @State private var photoIDs: [String]?

    private static let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]
    private static let tileSize = CGSize(width: 120, height: 120)

    var body: some View {
        NavigationStack {
            Group {
                if let photoIDs, photoIDs.isEmpty {
                    ContentUnavailableView(
                        "No photos yet",
                        systemImage: "photo.stack",
                        description: Text("Each playlist's cover photo appears here once it's published.")
                    )
                } else if let photoIDs {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("In Apple Music, Choose Photo → Albums → \(PhotoKitCoverAlbum.title) shows these same photos.")
                                .font(Theme.mono(12))
                                .fixedSize(horizontal: false, vertical: true)

                            LazyVGrid(columns: Self.columns, spacing: 6) {
                                ForEach(photoIDs, id: \.self) { id in
                                    tile(id)
                                }
                            }
                        }
                        .padding(16)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .foregroundStyle(palette.ink)
            .navigationTitle(PhotoKitCoverAlbum.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(palette.ink)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.paper)
        .task {
            photoIDs = await album.photos()
        }
    }

    private func tile(_ id: String) -> some View {
        let isHighlight = id == highlightID
        return PhotoThumbnail(assetIdentifier: id, seed: id, size: Self.tileSize, showsIcon: false)
            .aspectRatio(1, contentMode: .fill)
            .clipShape(.rect(cornerRadius: 3))
            .overlay {
                if isHighlight {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(palette.ink, lineWidth: 3)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isHighlight {
                    Text("This era")
                        .font(Theme.mono(10, medium: true))
                        .foregroundStyle(palette.paper)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(palette.ink)
                        .padding(6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(isHighlight ? "This era's cover photo" : "Cover photo")
    }
}
