import SwiftUI

/// One era on Home: its label, title, photo collage, and music.
struct EraCard: View {
    let era: Era
    /// The era's position counting from the oldest, starting at 1.
    let number: Int

    /// How many songs the card lists before "See all".
    private static let songLimit = 10

    @State private var showsAllSongs = false

    private var tag: String {
        guard era.isCurrent else { return String(localized: "Era \(number)") }
        let updated = era.playlist?.lastUpdated ?? .now
        if Calendar.current.isDateInToday(updated) {
            return String(localized: "Now · updated today")
        }
        let relative = updated.formatted(.relative(presentation: .named))
        return String(localized: "Now · updated \(relative)")
    }

    var body: some View {
        // A sync can delete this era while it's on screen. Draw nothing for
        // the one redraw before the list drops it (see `isLive`).
        if era.isLive {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        // Sorted once per update and shared by the collage and the songs.
        let moments = era.momentsNewestFirst

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text(tag.uppercased())
                    .font(Theme.mono(11, medium: true))
                    .tracking(0.9)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(era.palette.ink)
                    .foregroundStyle(era.palette.paper)
                Spacer(minLength: 0)
                Text(era.whenLabel)
                    .font(Theme.handwritten(30))
            }

            Text(era.title)
                .font(Theme.display(56, weight: .heavy, relativeTo: .largeTitle))
                .tracking(-2)
                .lineHeight(.multiple(factor: 0.92))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            // The first five moments, newest first.
            EraCollage(moments: Array(moments.prefix(5)), tapeColor: era.palette.tape)

            ListenPill(palette: era.palette)

            SongList(songs: Era.songs(in: moments), limit: Self.songLimit) {
                showsAllSongs = true
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 14)
        // The glass blurs away the fine paper grain behind it, so the same
        // grain is drawn again here: above the glass, below the card's content.
        .background {
            Image("PaperGrain")
                .resizable(resizingMode: .tile)
                .accessibilityHidden(true)
        }
        // Tinted Liquid Glass in the era's colour, for the edge highlights and depth.
        .glassEffect(.regular.tint(era.palette.paper.opacity(0.8)), in: .rect)
        .foregroundStyle(era.palette.ink)
        // The full era, with every song.
        .sheet(isPresented: $showsAllSongs) {
            EraSheet(era: era)
        }
    }
}
