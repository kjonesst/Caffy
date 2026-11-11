import SwiftUI

/// An era's print sitting on the river. Tapping it opens the era's music.
struct EraPrint: View {
    let era: Era
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        // A sync can delete this era while it's on screen. Draw nothing for
        // the one redraw before the list drops it (see `isLive`).
        if era.isLive {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // The era's newest photo stands for it on the river.
                PhotoThumbnail(
                    assetIdentifier: era.momentsNewestFirst.first?.photoAssetIdentifier,
                    seed: era.title,
                    size: CGSize(width: 180, height: 152)
                )
                    .frame(height: 152)
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        Text(era.startDate, format: .dateTime.month(.wide))
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.cream)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Theme.ink.opacity(0.74), in: .rect(cornerRadius: 4))
                            .padding(6)
                    }
                    .padding([.top, .horizontal], 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(era.title)
                        .font(Theme.display(17, weight: .heavy))
                        .tracking(-0.34)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(Theme.ink)
                    Text(era.whenLabel)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.softInk)
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
            .frame(width: 132, alignment: .leading)
            .background(Theme.cream)
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.ink, lineWidth: 3)
                }
            }
            .compositingGroup()
            .shadow(color: Theme.shadow.opacity(0.35), radius: 9, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(era.title), \(era.whenLabel)")
    }
}
