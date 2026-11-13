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
    /// Puts a plain listen button above the songs. Home leaves this off, because
    /// its cards have `ListenPill` instead.
    var showsListenButton = false
    /// Shows only this many songs, followed by a "See all" row. `nil` shows
    /// every song.
    var limit: Int? = nil
    /// Called by the "See all" row.
    var showAll: () -> Void = {}

    init(songs: [Song], showsListenButton: Bool = false, limit: Int? = nil, showAll: @escaping () -> Void = {}) {
        self.init(sections: [SongSection(title: nil, songs: songs)], showsListenButton: showsListenButton, limit: limit, showAll: showAll)
    }

    /// Empty sections are left out.
    init(sections: [SongSection], showsListenButton: Bool = false, limit: Int? = nil, showAll: @escaping () -> Void = {}) {
        self.sections = sections.filter { !$0.songs.isEmpty }
        self.showsListenButton = showsListenButton
        self.limit = limit
        self.showAll = showAll
    }

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
            if showsListenButton {
                // Publishing to Apple Music comes later, so this does nothing yet.
                Button {} label: {
                    Text("Listen in Apple Music")
                        .font(Theme.display(16))
                        .foregroundStyle(Theme.cream)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.ink)
                }
                .buttonStyle(.plain)
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
struct ListenPill: View {
    let palette: EraPalette

    var body: some View {
        // Publishing to Apple Music comes later, so this does nothing yet.
        Button {} label: {
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
        ListenPill(palette: .rust)
        SongList(songs: SampleData.previewSongs, showsListenButton: true)
        SongList(sections: [
            SongSection(title: "Playing at these moments", songs: Array(SampleData.previewSongs.prefix(2))),
            SongSection(title: "Added to your library around this time", songs: Array(SampleData.previewSongs.suffix(2)))
        ])
    }
    .padding()
}
