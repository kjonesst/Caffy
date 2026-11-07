import SwiftUI

/// The sheet that rises when an era is tapped on the river.
struct EraSheet: View {
    let era: Era

    @Environment(\.dismiss) private var dismiss
    /// The content's height, so short eras get a short sheet.
    @State private var contentHeight: CGFloat = 420

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(era.whenLabel)
                            .font(Theme.handwritten(28))
                        Text(era.title)
                            .font(Theme.display(44, weight: .heavy, relativeTo: .largeTitle))
                            .tracking(-1.3)
                            .lineHeight(.multiple(factor: 0.95))
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 0)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(era.palette.paper)
                            .frame(width: 44, height: 44)
                            .background(era.palette.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                Text(era.summary)
                    .font(Theme.display(17))

                SongList(songs: era.songs)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 30)
            .foregroundStyle(era.palette.ink)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                contentHeight = height
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(min(contentHeight, 620))])
        .presentationBackground(era.palette.paper)
    }
}
