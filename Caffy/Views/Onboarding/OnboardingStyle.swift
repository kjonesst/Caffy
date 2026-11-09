import SwiftUI

/// Every colour, size and timing the onboarding flow uses.
enum OnboardingStyle {
    /// The colours for one appearance. Light mode is Caffy's paper; dark mode
    /// is the espresso night look the Welcome hero introduced.
    struct Palette {
        let title: Color
        let body: Color
        let accent: Color
        let faint: Color
        let buttonFill: Color
        let buttonLabel: Color
        let buttonShadow: Color
        let base: Color
        /// Status cards on the permission steps.
        let card: Color
        let positive: Color
        let caution: Color
    }

    static func palette(for scheme: ColorScheme) -> Palette {
        scheme == .dark ? night : day
    }

    private static let day = Palette(
        title: Theme.ink,
        body: Theme.softInk,
        accent: Theme.rulerLine,
        faint: Theme.ink.opacity(0.12),
        buttonFill: Theme.ink,
        buttonLabel: Theme.cream,
        buttonShadow: Color(hex: 0x281206).opacity(0.3),
        base: Theme.cream,
        card: Theme.ink.opacity(0.05),
        positive: Color(hex: 0x5E7A45),
        caution: Color(hex: 0xA8532F)
    )

    private static let night = Palette(
        title: Theme.cream,
        body: Theme.softBone,
        accent: Color(hex: 0xD9B77A),
        faint: Theme.cream.opacity(0.16),
        buttonFill: Theme.cream,
        buttonLabel: Theme.espresso,
        buttonShadow: .clear,
        base: Theme.espresso,
        card: Theme.cream.opacity(0.07),
        positive: Color(hex: 0xA9C48C),
        caution: Color(hex: 0xE79A78)
    )

    static let darkGrainOpacity = 0.25

    // Spacing.
    static let horizontalPadding = 24.0
    static let copySpacing = 12.0
    static let contentTopSpacing = 16.0
    static let pointSpacing = 18.0
    static let buttonSpacing = 4.0
    static let buttonAreaTopPadding = 12.0
    static let buttonAreaBottomPadding = 8.0
    static let topBarHorizontalPadding = 16.0

    // Sizes.
    static let visualMinHeight = 220.0
    static let heroMinHeight = 280.0
    static let buttonMinHeight = 60.0
    static let secondaryButtonMinHeight = 44.0
    static let topBarButtonSize = 44.0
    static let topBarMaxTypeSize = DynamicTypeSize.xxxLarge
    static let pointIconSize = 40.0
    static let progressSegmentWidth = 22.0
    static let progressSegmentHeight = 4.0
    static let progressSegmentSpacing = 6.0

    // Type sizes. Each scales with Dynamic Type through `Theme`.
    static let heroTitleSize = 56.0
    static let heroMessageSize = 24.0
    static let titleSize = 34.0
    static let messageSize = 18.0
    static let pointTitleSize = 17.0
    static let pointDetailSize = 15.0
    static let footnoteSize = 13.0
    static let buttonTextSize = 20.0

    // Motion. Screens slide a little and fade; with Reduce Motion they only fade.
    static let stepAnimation = Animation.easeInOut(duration: 0.35)
    static let calmStepAnimation = Animation.easeInOut(duration: 0.25)
    static let stepSlide = 24.0
    /// How status cards fade in after a permission answer.
    static let statusAnimation = Animation.easeInOut(duration: 0.3)
    /// How long "Apple Music is connected" shows before moving on, when it
    /// was already connected (for example after a reinstall).
    static let autoAdvanceDelay = 1.2

    static let statusCardCorner = 16.0
    static let statusCardPadding = 16.0
}
