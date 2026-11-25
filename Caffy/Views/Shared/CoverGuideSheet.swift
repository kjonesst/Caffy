import SwiftUI

/// Shown once after an era's playlist is first published: the era's
/// highlight photo, and how to make it the playlist's cover.
///
/// Apps can't set a playlist's cover (MusicKit has no way to), so the user
/// does it in Apple Music in a few taps. The photo is already in their
/// library; its date and place help them find it in the picker.
struct CoverGuideSheet: View {
    let era: Era
    let playlistURL: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("showsCoverGuide") private var showsCoverGuide = true

    private static let photoSize = CGSize(width: 220, height: 220)

    var body: some View {
        let palette = era.palette
        let highlight = era.highlightMoment

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Your playlist is in Apple Music")
                    .font(Theme.display(28, weight: .heavy, relativeTo: .title))
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)

                Text("Give it this era's photo as its cover.")
                    .font(Theme.display(17))

                VStack(spacing: 6) {
                    PhotoThumbnail(
                        assetIdentifier: highlight?.photoAssetIdentifier,
                        seed: era.title,
                        size: Self.photoSize,
                        showsIcon: false
                    )
                    .frame(width: Self.photoSize.width, height: Self.photoSize.height)
                    .padding(8)
                    .background(.white)
                    .rotationEffect(.degrees(-2))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
                    .accessibilityHidden(true)

                    if let highlight {
                        Text(caption(for: highlight))
                            .font(Theme.handwritten(24))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Tap Open in Apple Music below.")
                    step(2, "In the playlist, tap ••• and then Edit.")
                    step(3, "Tap the cover, choose Choose Photo, and pick this photo.")
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
