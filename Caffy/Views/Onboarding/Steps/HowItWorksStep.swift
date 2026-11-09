import SwiftUI

/// Step 3: connect, match, playlists, and a reminder that you listen in
/// Apple Music.
struct HowItWorksStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        OnboardingLayout(
            title: OnboardingCopy.HowItWorks.title,
            message: OnboardingCopy.HowItWorks.message,
            visualMinHeight: 150,
            primary: OnboardingAction(title: OnboardingCopy.Common.next, systemImage: "arrow.right", action: model.next)
        ) {
            MomentPairVisual()
        } content: {
            OnboardingPointList(points: OnboardingCopy.HowItWorks.points)
            Label {
                Text(OnboardingCopy.HowItWorks.footnote)
            } icon: {
                Image(systemName: "arrow.up.forward.app")
            }
            .font(Theme.display(OnboardingStyle.footnoteSize, relativeTo: .footnote))
            .foregroundStyle(OnboardingStyle.palette(for: colorScheme).body)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
        }
    }
}

/// A photo print and a playlist cover, pinned together. Decorative: the
/// points below say the same thing in words.
private struct MomentPairVisual: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let accent = OnboardingStyle.palette(for: colorScheme).accent

        ZStack {
            print(seed: "Bondi Beach", icon: "photo", width: 84, height: 104)
                .rotationEffect(.degrees(-7))
                .offset(x: -40, y: -4)
            print(seed: "Golden Hour", icon: "music.note", width: 88, height: 88)
                .rotationEffect(.degrees(6))
                .offset(x: 40, y: 8)
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.cream, accent)
                .offset(x: -2, y: -46)
        }
        .accessibilityHidden(true)
    }

    private func print(seed: String, icon: String, width: Double, height: Double) -> some View {
        BurstArtworkView(artwork: .placeholder(seed: seed), iconSymbol: icon, iconSize: 22)
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cream, lineWidth: 4)
            }
            .compositingGroup()
            .shadow(color: Theme.shadow.opacity(0.25), radius: 7, y: 5)
    }
}

#Preview("Light", traits: .onboarding) {
    OnboardingView(startingAt: .howItWorks)
}

#Preview("Dark", traits: .onboarding) {
    OnboardingView(startingAt: .howItWorks)
        .preferredColorScheme(.dark)
}

#Preview("Largest text", traits: .onboarding) {
    OnboardingView(startingAt: .howItWorks)
        .dynamicTypeSize(.accessibility3)
}
