import SwiftUI

/// Step 4: what Caffy promises, before it asks for anything.
struct PrivacyStep: View {
    @Environment(OnboardingModel.self) private var model

    var body: some View {
        OnboardingLayout(
            title: OnboardingCopy.Privacy.title,
            message: OnboardingCopy.Privacy.message,
            visualMinHeight: 130,
            primary: OnboardingAction(title: OnboardingCopy.Common.next, systemImage: "arrow.right", action: model.next)
        ) {
            OnboardingSymbolVisual(symbol: "hand.raised.fill")
        } content: {
            OnboardingPointList(points: OnboardingCopy.Privacy.points)
        }
    }
}

#Preview("Light", traits: .onboarding) {
    OnboardingView(startingAt: .privacy)
}

#Preview("Dark", traits: .onboarding) {
    OnboardingView(startingAt: .privacy)
        .preferredColorScheme(.dark)
}

#Preview("Largest text", traits: .onboarding) {
    OnboardingView(startingAt: .privacy)
        .dynamicTypeSize(.accessibility3)
}
