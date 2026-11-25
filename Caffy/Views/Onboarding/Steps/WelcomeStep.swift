import SwiftData
import SwiftUI

/// Step 1: the memory burst, Caffy's name, and the promise.
struct WelcomeStep: View {
    /// Passed to `MemoryBurst` where there's no real art. On a first run
    /// there's none yet; when onboarding is replayed, covers from the
    /// newest eras take the playlist and tip spots.
    var photo: BurstArtwork = .placeholder(seed: "Bondi Beach")
    var artwork: BurstArtwork = .placeholder(seed: "Golden Hour")
    var tipArtwork: [BurstArtwork] = BurstArtwork.placeholders(MemoryBurstStyle.maxTipArtwork)

    @Environment(OnboardingModel.self) private var model
    @Query(sort: \Era.startDate, order: .reverse) private var eras: [Era]

    var body: some View {
        let covers = BurstArtwork.recentCovers(in: eras, count: 1 + MemoryBurstStyle.maxTipArtwork)
        OnboardingLayout(
            title: OnboardingCopy.Welcome.appName,
            message: OnboardingCopy.Welcome.headline,
            prominence: .hero,
            visualMinHeight: OnboardingStyle.heroMinHeight,
            primary: OnboardingAction(title: OnboardingCopy.Welcome.button, systemImage: "arrow.right", action: model.next)
        ) {
            MemoryBurst(
                photo: photo,
                artwork: covers.first.map(BurstArtwork.url) ?? artwork,
                tipArtwork: BurstArtwork.filling(tipArtwork, with: Array(covers.dropFirst()))
            )
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
