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
    /// A listen button drawn above the songs (`EraListenButton` in its plain
    /// style). Home leaves this off, because its cards have the pill instead.
    var listenButton: AnyView? = nil
    /// Shows only this many songs, followed by a "See all" row. `nil` shows
    /// every song.
    var limit: Int? = nil
    /// Called by the "See all" row.
    var showAll: () -> Void = {}

    init(songs: [Song], listenButton: AnyView? = nil, limit: Int? = nil, showAll: @escaping () -> Void = {}) {
        self.init(sections: [SongSection(title: nil, songs: songs)], listenButton: listenButton, limit: limit, showAll: showAll)
    }

    /// Empty sections are left out.
    init(sections: [SongSection], listenButton: AnyView? = nil, limit: Int? = nil, showAll: @escaping () -> Void = {}) {
        self.sections = sections.filter { !$0.songs.isEmpty }
        self.listenButton = listenButton
        self.limit = limit
        self.showAll = showAll
    }

    private var showsListenButton: Bool { listenButton != nil }

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
            if let listenButton {
                listenButton
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

/// What a listen button says: ready, working, or what went wrong.
struct ListenDisplay: Equatable {
    var title: String
    /// Publishing is under way: shows a spinner and ignores taps.
    var isWorking = false
    /// Something stopped it; the title says what, and a tap tries again
    /// (or opens Settings, where that's the fix).
    var isProblem = false

    static let ready = ListenDisplay(title: String(localized: "Listen in Apple Music"))
}

/// The big listen button on an era's card, printed in the era's colours.
/// It only draws; `EraListenButton` decides what it says and does.
struct ListenPill: View {
    let palette: EraPalette
    var display: ListenDisplay = .ready
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Group {
                    if display.isWorking {
                        ProgressView().tint(palette.ink)
                    } else {
                        Image(systemName: display.isProblem ? "exclamationmark" : "play.fill")
                            .font(.system(size: 18, weight: display.isProblem ? .bold : .regular))
                    }
                }
                .foregroundStyle(palette.ink)
                .frame(width: 48, height: 48)
                .background(palette.paper, in: .circle)

                Text(display.title)
                    .font(Theme.display(display.isProblem ? 17 : 20, weight: .heavy))
                    .tracking(-0.2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)

                Image(systemName: display.isProblem ? "arrow.clockwise" : "arrow.up.right")
                    .font(.system(size: 17, weight: .bold))
                    .opacity(display.isWorking ? 0 : 1)
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
            .animation(.easeOut(duration: 0.2), value: display)
        }
        .buttonStyle(.plain)
        .disabled(display.isWorking)
        .accessibilityLabel(display.title)
        .accessibilityHint(display.isProblem ? "Tries again" : "Opens this era's playlist in Apple Music, making it first if needed")
    }
}

/// The plain listen button above an era's full song list.
struct PlainListenButton: View {
    var display: ListenDisplay = .ready
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if display.isWorking {
                    ProgressView().tint(Theme.cream)
                }
                Text(display.title)
                    .font(Theme.display(16))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Theme.cream)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.ink)
        }
        .buttonStyle(.plain)
        .disabled(display.isWorking)
        .accessibilityHint(display.isProblem ? "Tries again" : "Opens this era's playlist in Apple Music, making it first if needed")
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
        ListenPill(palette: .rust) {}
        ListenPill(palette: .rust, display: ListenDisplay(title: "Making your playlist…", isWorking: true)) {}
        SongList(songs: SampleData.previewSongs, listenButton: AnyView(PlainListenButton {}))
        SongList(sections: [
            SongSection(title: "Playing at these moments", songs: Array(SampleData.previewSongs.prefix(2))),
            SongSection(title: "Added to your library around this time", songs: Array(SampleData.previewSongs.suffix(2)))
        ])
    }
    .padding()
}
