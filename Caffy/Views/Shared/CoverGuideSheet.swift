import SwiftUI

/// Shown once after an era's playlist is first published: the era's
/// highlight photo, and how to make it the playlist's cover.
///
/// Apps can't set a playlist's cover (MusicKit has no way to), so the user
/// does it in Apple Music in a few taps. The photo is normally waiting in
/// the "Caffinated" album (`CoverAlbum`), which the steps point to; if it
/// couldn't be added there, its date and place help find it instead.
struct CoverGuideSheet: View {
    let era: Era
    let playlistURL: URL
    /// The photo to use as the cover (`EraPublisher.ListenResult.coverPhotoID`).
    let photoID: String
    /// The photo is in the cover album.
    let isInAlbum: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("showsCoverGuide") private var showsCoverGuide = true

    private static let photoSize = CGSize(width: 220, height: 220)

    @State private var showsAlbum = false

    /// The highlight photo as a taped-in print.
    private var photoPrint: some View {
        PhotoThumbnail(
            assetIdentifier: photoID,
            seed: era.title,
            size: Self.photoSize,
            showsIcon: false
        )
        .frame(width: Self.photoSize.width, height: Self.photoSize.height)
        .padding(8)
        .background(.white)
        .rotationEffect(.degrees(-2))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        .contentShape(.rect)
    }

    var body: some View {
        let palette = era.palette
        let highlight = era.moments.first { $0.photoAssetIdentifier == photoID }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Your playlist is in Apple Music")
                    .font(Theme.display(28, weight: .heavy, relativeTo: .title))
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)

                Text("Give it this era's photo as its cover.")
                    .font(Theme.display(17))

                VStack(spacing: 6) {
                    // In the album, the print opens it; otherwise it's just the photo.
                    if isInAlbum {
                        Button {
                            showsAlbum = true
                        } label: {
                            photoPrint
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show the \(PhotoKitCoverAlbum.title) album")
                        .accessibilityHint("Shows every era's cover photo")
                    } else {
                        photoPrint
                            .accessibilityHidden(true)
                    }

                    if let highlight {
                        Text(caption(for: highlight))
                            .font(Theme.handwritten(24))
                            .multilineTextAlignment(.center)
                    }
                    if isInAlbum {
                        Text("Tap the photo to see the \(PhotoKitCoverAlbum.title) album")
                            .font(Theme.mono(11))
                            .opacity(0.8)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Tap Open in Apple Music below.")
                    step(2, "In the playlist, tap ••• and then Edit.")
                    if isInAlbum {
                        step(3, "Tap the cover and choose Choose Photo.")
                        step(4, "Open Albums, then \(PhotoKitCoverAlbum.title), and pick this photo.")
                    } else {
                        step(3, "Tap the cover, choose Choose Photo, and pick this photo.")
                    }
                }

                if isInAlbum {
                    Label {
                        Text("Caffy keeps every era's cover photo in the \(PhotoKitCoverAlbum.title) album in Photos.")
                            .font(Theme.mono(12))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "photo.stack")
                    }
                }

                Button {
                    dismiss()
                    openURL(playlistURL)
                } label: {
                    Text("Open in Apple Music")
                        .font(Theme.display(18, weight: .heavy))
                        .foregroundStyle(palette.paper)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(palette.ink, in: .capsule)
                }
                .buttonStyle(.plain)

                Button("Not now") { dismiss() }
                    .font(Theme.mono(13, medium: true))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain)

                Toggle("Don't show this again", isOn: Binding(
                    get: { !showsCoverGuide },
                    set: { showsCoverGuide = !$0 }
                ))
                .font(Theme.mono(12))
                .tint(palette.ink)
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 20)
            .foregroundStyle(palette.ink)
        }
        .presentationDetents([.large])
        .presentationBackground(palette.paper)
        .sheet(isPresented: $showsAlbum) {
            CoverAlbumSheet(highlightID: photoID, palette: palette)
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(Theme.mono(13, medium: true))
                .frame(width: 22, height: 22)
                .background(era.palette.ink.opacity(0.12), in: .circle)
            Text(text)
                .font(Theme.display(16))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Taken 14 Sep 2026 · Fremantle", for spotting it in the photo picker.
    private func caption(for moment: Moment) -> String {
        let date = moment.date.formatted(.dateTime.day().month(.abbreviated).year())
        if let place = moment.place?.name {
            return String(localized: "Taken \(date) · \(place)")
        }
        return String(localized: "Taken \(date)")
    }
}
