import SwiftUI

/// One era on Home: its label, title, photo collage, and music.
struct EraCard: View {
    let era: Era
    /// The era's position counting from the oldest, starting at 1.
    let number: Int

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
            EraCollage(moments: Array(era.momentsNewestFirst.prefix(5)), tapeColor: era.palette.tape)

            ListenPill(palette: era.palette)

            SongList(songs: era.songs)
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(era.palette.paper)
        .foregroundStyle(era.palette.ink)
    }
}
