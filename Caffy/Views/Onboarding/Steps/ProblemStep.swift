import SwiftUI

/// Step 2: one idea. Your photos and your music live in separate apps.
struct ProblemStep: View {
    @Environment(OnboardingModel.self) private var model

    var body: some View {
        OnboardingLayout(
            title: OnboardingCopy.Problem.title,
            message: OnboardingCopy.Problem.message,
            primary: OnboardingAction(title: OnboardingCopy.Common.next, systemImage: "arrow.right", action: model.next)
        ) {
            SeparateAppsVisual()
        }
    }
}

// MARK: - Visual

/// Sizes for the two app cards.
private enum SeparateAppsStyle {
    static let maxWidth = 360.0
    static let cardCorner = 18.0
    static let cardPadding = 12.0
    static let photosTilt = -4.0
    static let musicTilt = 3.0
    static let gapWidth = 40.0
    static let thumbCorner = 6.0
    static let coverSize = 26.0
    static let labelFont = Font.custom("Bricolage Grotesque", fixedSize: 14).weight(.semibold)
    static let captionFont = Font.custom("DMMono-Medium", fixedSize: 10)
    /// Seeds chosen so the four placeholder tones differ.
    static let photoSeeds = ["Alfama", "Sintra", "Harbour", "Sunset"]
    static let songSeeds = ["Song A", "Song B", "Song C"]
}

/// A Photos card and a Music card, with a broken link between them. The
/// cards are decorative, so their sizes stay fixed at every text size.
private struct SeparateAppsVisual: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = OnboardingStyle.palette(for: colorScheme)

        HStack(spacing: 0) {
            AppCard(label: OnboardingCopy.Problem.photosLabel, symbol: "photo.on.rectangle.angled") {
                Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                    GridRow { thumb(0); thumb(1) }
                    GridRow { thumb(2); thumb(3) }
                }
                caption(OnboardingCopy.Problem.photosCaption, symbol: "mappin.circle.fill")
            }
            .rotationEffect(.degrees(SeparateAppsStyle.photosTilt))

            BrokenLink(color: palette.accent)
                .frame(width: SeparateAppsStyle.gapWidth)

            AppCard(label: OnboardingCopy.Problem.musicLabel, symbol: "music.note") {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(SeparateAppsStyle.songSeeds, id: \.self) { seed in
                        songRow(seed: seed)
                    }
                }
                caption(OnboardingCopy.Problem.musicCaption, symbol: "clock")
            }
            .rotationEffect(.degrees(SeparateAppsStyle.musicTilt))
        }
        .frame(maxWidth: SeparateAppsStyle.maxWidth)
        .padding(.horizontal, OnboardingStyle.horizontalPadding)
        .padding(.vertical, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(OnboardingCopy.Problem.visualLabel))
        .accessibilityAddTraits(.isImage)
    }

    private func thumb(_ index: Int) -> some View {
        PhotoPlaceholder(seed: SeparateAppsStyle.photoSeeds[index], showsIcon: false)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.rect(cornerRadius: SeparateAppsStyle.thumbCorner))
    }

    private func songRow(seed: String) -> some View {
        HStack(spacing: 8) {
            PhotoPlaceholder(seed: seed, showsIcon: false)
                .frame(width: SeparateAppsStyle.coverSize, height: SeparateAppsStyle.coverSize)
                .clipShape(.rect(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(Theme.ink.opacity(0.7)).frame(height: 5)
                Capsule().fill(Theme.ink.opacity(0.25)).frame(height: 4).padding(.trailing, 24)
            }
        }
    }

    private func caption(_ text: LocalizedStringResource, symbol: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
        }
        .font(SeparateAppsStyle.captionFont)
        .foregroundStyle(Theme.softInk)
        .lineLimit(1)
    }
}

/// A printed card standing in for an app.
private struct AppCard<Content: View>: View {
    let label: LocalizedStringResource
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(label)
            } icon: {
                Image(systemName: symbol)
            }
            .font(SeparateAppsStyle.labelFont)
            .foregroundStyle(Theme.ink)
            content
        }
        .padding(SeparateAppsStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cream, in: .rect(cornerRadius: SeparateAppsStyle.cardCorner))
        .overlay {
            RoundedRectangle(cornerRadius: SeparateAppsStyle.cardCorner)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
        .compositingGroup()
        .shadow(color: Theme.shadow.opacity(0.22), radius: 10, y: 8)
    }
}

/// A dashed line with a gap in the middle: the missing connection.
private struct BrokenLink: View {
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            dashes
            dashes
        }
        .frame(maxWidth: .infinity)
    }

    private var dashes: some View {
        HStack(spacing: 3) {
            ForEach(0..<2, id: \.self) { _ in
                Capsule().fill(color).frame(width: 5, height: 2)
            }
        }
    }
}

#Preview("Light", traits: .onboarding) {
    OnboardingView(startingAt: .problem)
}

#Preview("Dark", traits: .onboarding) {
    OnboardingView(startingAt: .problem)
        .preferredColorScheme(.dark)
}

#Preview("Largest text", traits: .onboarding) {
    OnboardingView(startingAt: .problem)
        .dynamicTypeSize(.accessibility3)
}
