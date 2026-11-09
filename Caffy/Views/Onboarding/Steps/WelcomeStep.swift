import SwiftUI

/// Step 1: the memory burst, Caffy's name, and the promise.
struct WelcomeStep: View {
    /// Passed straight to `MemoryBurst`. Placeholders until PhotoKit and
    /// MusicKit are connected.
    var photo: BurstArtwork = .placeholder(seed: "Bondi Beach")
    var artwork: BurstArtwork = .placeholder(seed: "Golden Hour")
    var tipArtwork: [BurstArtwork] = BurstArtwork.placeholders(MemoryBurstStyle.maxTipArtwork)

    @Environment(OnboardingModel.self) private var model

    var body: some View {
        OnboardingLayout(
            title: OnboardingCopy.Welcome.appName,
            message: OnboardingCopy.Welcome.headline,
            prominence: .hero,
            visualMinHeight: OnboardingStyle.heroMinHeight,
            primary: OnboardingAction(title: OnboardingCopy.Welcome.button, systemImage: "arrow.right", action: model.next)
        ) {
            MemoryBurst(photo: photo, artwork: artwork, tipArtwork: tipArtwork)
        }
    }
}

#Preview("Light", traits: .onboarding) {
    OnboardingView(startingAt: .welcome)
}

#Preview("Dark", traits: .onboarding) {
    OnboardingView(startingAt: .welcome)
        .preferredColorScheme(.dark)
}

#Preview("Largest text", traits: .onboarding) {
    OnboardingView(startingAt: .welcome)
        .dynamicTypeSize(.accessibility3)
}
