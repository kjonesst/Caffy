import Foundation

/// The seven onboarding screens, in order.
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case problem
    case howItWorks
    case privacy
    case music
    case photos
    case ready

    /// Steps 2–6 show the progress bar.
    var showsProgress: Bool { progressIndex != nil }

    /// Everything except the first and last screens can go back.
    var allowsBack: Bool { self != .welcome && self != .ready }

    /// The explainer screens can skip straight to the permission asks.
    var allowsSkip: Bool { [.problem, .howItWorks, .privacy].contains(self) }

    /// Position on the progress bar (1–5), or `nil` when it's hidden.
    var progressIndex: Int? {
        switch self {
        case .welcome, .ready: nil
        default: rawValue
        }
    }

    /// How many steps the progress bar counts.
    static let progressCount = 5

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    /// DEBUG only: the `-onboardingStep <1–7>` launch argument opens that step,
    /// so a single screen can be checked without tapping through the flow.
    static var launchStep: OnboardingStep {
        #if DEBUG
        let number = UserDefaults.standard.integer(forKey: "onboardingStep")
        return OnboardingStep(rawValue: number - 1) ?? .welcome
        #else
        return .welcome
        #endif
    }
}
