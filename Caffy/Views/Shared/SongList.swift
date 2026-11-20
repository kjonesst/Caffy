import SwiftUI

/// A labelled group of songs in a `SongList`.
struct SongSection: Identifiable {
    /// Shown above the songs in the mono caption font. `nil` shows no label.
    let title: String?
    let songs: [Song]

    var id: String { title ?? "" }
}

/// The cream panel of an era's songs, optionally in labelled groups.
struct SongList: View {
    let sections: [SongSection]
    /// The era's published playlist. When set, a plain listen button above
    /// the songs opens it in Apple Music. Home leaves this off, because its
    /// cards have `ListenPill` instead; unpublished eras have no link.
    var listenURL: URL? = nil
    /// Shows only this many songs, followed by a "See all" row. `nil` shows
    /// every song.
    var limit: Int? = nil
    /// Called by the "See all" row.
    var showAll: () -> Void = {}

    @Environment(\.openURL) private var openURL

    init(songs: [Song], listenURL: URL? = nil, limit: Int? = nil, showAll: @escaping () -> Void = {}) {
        self.init(sections: [SongSection(title: nil, songs: songs)], listenURL: listenURL, limit: limit, showAll: showAll)
    }

    /// Empty sections are left out.
    init(sections: [SongSection], listenURL: URL? = nil, limit: Int? = nil, showAll: @escaping () -> Void = {}) {
        self.sections = sections.filter { !$0.songs.isEmpty }
        self.listenURL = listenURL
        self.limit = limit
        self.showAll = showAll
    }

    private var showsListenButton: Bool { listenURL != nil }

    private var songCount: Int {
        sections.reduce(0) { $0 + $1.songs.count }
    }

    /// The sections cut down to `limit` songs in all, in order.
    private var visibleSections: [SongSection] {
        var remaining = limit ?? songCount
        var visible: [SongSection] = []
        for section in sections where remaining > 0 {
            let songs = Array(section.songs.prefix(remaining))
            visible.append(SongSection(title: section.title, songs: songs))
            remaining -= songs.count
        }
        return visible
    }

    var body: some View {
        VStack(spacing: 0) {
            if let listenURL {
                Button {
                    openURL(listenURL)
                } label: {
                    Text("Listen in Apple Music")
                        .font(Theme.display(16))
                        .foregroundStyle(Theme.cream)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this era's playlist in Apple Music")
                .padding(.bottom, 4)
            }

            let visible = visibleSections
            ForEach(visible) { section in
                if let title = section.title {
                    Text(title)
                        .font(Theme.mono(11, medium: true))
                        .tracking(0.6)
                        .foregroundStyle(Theme.softInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(section.songs) { song in
                    SongRow(song: song)
                }
            }

            if visible.reduce(0, { $0 + $1.songs.count }) < songCount {
                Button(action: showAll) {
                    HStack {
                        Text("See all \(songCount) songs")
                            .font(Theme.mono(12, medium: true))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 48)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, showsListenButton ? 10 : 4)
        .padding(.bottom, showsListenButton ? 4 : 6)
        .background(Theme.cream)
    }
}

/// The big listen button on an era's card, printed in the era's colours.
///
/// Opens the era's published playlist in Apple Music. Draws nothing until
/// the era has one: a button that can't do anything yet would only confuse.
struct ListenPill: View {
    let palette: EraPalette
    /// The published playlist's link (`CaffyPlaylist.appleMusicURL`).
    let url: URL?

    @Environment(\.openURL) private var openURL

    var body: some View {
        if let url {
            button(opening: url)
        }
    }

    private func button(opening url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
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
        .accessibilityHint("Opens this era's playlist in Apple Music")
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
        ListenPill(palette: .rust, url: URL(string: "https://music.apple.com"))
        SongList(songs: SampleData.previewSongs, listenURL: URL(string: "https://music.apple.com"))
        SongList(sections: [
            SongSection(title: "Playing at these moments", songs: Array(SampleData.previewSongs.prefix(2))),
            SongSection(title: "Added to your library around this time", songs: Array(SampleData.previewSongs.suffix(2)))
        ])
    }
    .padding()
}
