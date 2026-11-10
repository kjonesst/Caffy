import SwiftUI

/// A button on an onboarding step.
struct OnboardingAction {
    let title: LocalizedStringResource
    var systemImage: String? = nil
    var hint: LocalizedStringResource? = nil
    let action: () -> Void
}

/// The shape every onboarding step shares: a visual on top, then the title,
/// message and any extra content, with the buttons pinned at the bottom.
///
/// When the text is too big to fit (large Dynamic Type sizes), the page
/// scrolls under the buttons instead of clipping.
struct OnboardingLayout<Visual: View, Content: View>: View {
    enum Prominence {
        /// Big title and message, for the Welcome screen.
        case hero
        case regular
    }

    let title: LocalizedStringResource
    let message: LocalizedStringResource?
    let prominence: Prominence
    let visualMinHeight: Double
    let primary: OnboardingAction
    let secondary: OnboardingAction?
    let visual: Visual
    let content: Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: LocalizedStringResource,
        message: LocalizedStringResource? = nil,
        prominence: Prominence = .regular,
        visualMinHeight: Double = OnboardingStyle.visualMinHeight,
        primary: OnboardingAction,
        secondary: OnboardingAction? = nil,
        @ViewBuilder visual: () -> Visual,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.message = message
        self.prominence = prominence
        self.visualMinHeight = visualMinHeight
        self.primary = primary
        self.secondary = secondary
        self.visual = visual()
        self.content = content()
    }

    private var palette: OnboardingStyle.Palette { OnboardingStyle.palette(for: colorScheme) }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    visual
                        .frame(maxWidth: .infinity, minHeight: visualMinHeight, maxHeight: .infinity)

                    copy
                        .padding(.horizontal, OnboardingStyle.horizontalPadding)
                        .padding(.bottom, OnboardingStyle.copySpacing)

                    if !pinsButtons { buttons }
                }
                // Fills the screen when it fits, so the visual takes the
                // spare room; grows past it and scrolls when it doesn't.
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaBar(edge: .bottom) {
            if pinsButtons { buttons }
        }
    }

    /// Buttons stay pinned at the bottom, except at accessibility text sizes,
    /// where they'd cover a third of the screen. There they come last in the
    /// scrolling page instead.
    private var pinsButtons: Bool { !dynamicTypeSize.isAccessibilitySize }

    private var copy: some View {
        VStack(alignment: .leading, spacing: OnboardingStyle.copySpacing) {
            titleText

            if let message {
                messageText(message)
            }

            content
                .padding(.top, OnboardingStyle.contentTopSpacing - OnboardingStyle.copySpacing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// On the Welcome hero, the launch splash's title glides into this heading.
    @ViewBuilder private var titleText: some View {
        let text = Text(title)
            .font(titleFont)
            .tracking(prominence == .hero ? -2 : -0.8)
            .foregroundStyle(palette.title)
        if prominence == .hero {
            text
                .caffyTitleTarget(.glide)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        } else {
            text
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// On the Welcome hero, the message rolls in word by word once the splash hands over.
    @ViewBuilder private func messageText(_ message: LocalizedStringResource) -> some View {
        if prominence == .hero {
            CaffyWordRollText(String(localized: message), alignment: .leading)
                .font(messageFont)
                .foregroundStyle(palette.title)
        } else {
            Text(message)
                .font(messageFont)
                .foregroundStyle(palette.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var titleFont: Font {
        prominence == .hero
            ? Theme.display(OnboardingStyle.heroTitleSize, weight: .heavy, relativeTo: .largeTitle)
            : Theme.display(OnboardingStyle.titleSize, weight: .heavy, relativeTo: .largeTitle)
    }

    private var messageFont: Font {
        prominence == .hero
            ? Theme.display(OnboardingStyle.heroMessageSize, weight: .medium, relativeTo: .title2)
            : Theme.display(OnboardingStyle.messageSize, relativeTo: .body)
    }

    /// On the Welcome hero, the buttons glow in as the message finishes rolling in.
    @ViewBuilder private var buttons: some View {
        if prominence == .hero {
            buttonStack.caffyGlowIn(delay: 0.75)
        } else {
            buttonStack
        }
    }

    private var buttonStack: some View {
        VStack(spacing: OnboardingStyle.buttonSpacing) {
            OnboardingPrimaryButton(action: primary)
            if let secondary {
                OnboardingSecondaryButton(action: secondary)
            }
        }
        .padding(.horizontal, OnboardingStyle.horizontalPadding)
        .padding(.top, OnboardingStyle.buttonAreaTopPadding)
        .padding(.bottom, OnboardingStyle.buttonAreaBottomPadding)
    }
}

extension OnboardingLayout where Content == EmptyView {
    init(
        title: LocalizedStringResource,
        message: LocalizedStringResource? = nil,
        prominence: Prominence = .regular,
        visualMinHeight: Double = OnboardingStyle.visualMinHeight,
        primary: OnboardingAction,
        secondary: OnboardingAction? = nil,
        @ViewBuilder visual: () -> Visual
    ) {
        self.init(
            title: title,
            message: message,
            prominence: prominence,
            visualMinHeight: visualMinHeight,
            primary: primary,
            secondary: secondary,
            visual: visual,
            content: { EmptyView() }
        )
    }
}

// MARK: - Buttons

/// The main call to action: ink on paper by day, paper on espresso by night,
/// in the shape of the Listen pill on Home.
struct OnboardingPrimaryButton: View {
    let action: OnboardingAction

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = OnboardingStyle.palette(for: colorScheme)

        Button(action: action.action) {
            HStack {
                Text(action.title)
                    .font(Theme.display(OnboardingStyle.buttonTextSize, weight: .heavy, relativeTo: .title3))
                    .tracking(-0.2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if let systemImage = action.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(.body, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(palette.buttonLabel)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(minHeight: OnboardingStyle.buttonMinHeight)
            .background {
                Capsule()
                    .fill(palette.buttonFill.shadow(.inner(color: .white.opacity(0.3), radius: 0, y: 1)))
                    .shadow(color: palette.buttonShadow, radius: 11, y: 10)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityHint(action.hint.map { Text($0) } ?? Text(verbatim: ""))
    }
}

/// A quieter text button under the main one.
struct OnboardingSecondaryButton: View {
    let action: OnboardingAction

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action.action) {
            Label {
                Text(action.title)
            } icon: {
                if let systemImage = action.systemImage {
                    Image(systemName: systemImage)
                }
            }
            .font(Theme.display(17, weight: .semibold, relativeTo: .body))
            .foregroundStyle(OnboardingStyle.palette(for: colorScheme).title)
            .frame(maxWidth: .infinity, minHeight: OnboardingStyle.secondaryButtonMinHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(action.hint.map { Text($0) } ?? Text(verbatim: ""))
    }
}

// MARK: - Content pieces

/// One point in a list, with its symbol in a soft circle.
struct OnboardingPoint: View {
    let content: OnboardingPointContent

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var iconSize = OnboardingStyle.pointIconSize

    var body: some View {
        let palette = OnboardingStyle.palette(for: colorScheme)

        HStack(alignment: .top, spacing: 14) {
            Image(systemName: content.symbol)
                .font(.system(size: iconSize * 0.45, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: iconSize, height: iconSize)
                .background(palette.accent.opacity(0.14), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(Theme.display(OnboardingStyle.pointTitleSize, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(palette.title)
                Text(content.detail)
                    .font(Theme.display(OnboardingStyle.pointDetailSize, relativeTo: .subheadline))
                    .foregroundStyle(palette.body)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        // VoiceOver reads the title and detail together.
        .accessibilityElement(children: .combine)
    }
}

/// A list of points with even spacing.
struct OnboardingPointList: View {
    let points: [OnboardingPointContent]

    var body: some View {
        VStack(alignment: .leading, spacing: OnboardingStyle.pointSpacing) {
            ForEach(points) { OnboardingPoint(content: $0) }
        }
    }
}

/// The tone of a status card or badge.
enum OnboardingTone {
    case positive
    case neutral
    case caution

    func color(in palette: OnboardingStyle.Palette) -> Color {
        switch self {
        case .positive: palette.positive
        case .neutral: palette.accent
        case .caution: palette.caution
        }
    }
}

/// What a permission step shows once the user has answered.
struct OnboardingStatus {
    let tone: OnboardingTone
    let symbol: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
}

/// A short note about a permission answer: what works, what doesn't, and
/// what to do about it.
struct OnboardingStatusCard: View {
    let status: OnboardingStatus

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = OnboardingStyle.palette(for: colorScheme)

        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.symbol)
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(status.tone.color(in: palette))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(status.title)
                    .font(Theme.display(OnboardingStyle.pointTitleSize, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(palette.title)
                Text(status.detail)
                    .font(Theme.display(OnboardingStyle.pointDetailSize, relativeTo: .subheadline))
                    .foregroundStyle(palette.body)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OnboardingStyle.statusCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: .rect(cornerRadius: OnboardingStyle.statusCardCorner))
        .accessibilityElement(children: .combine)
    }
}

/// One large SF Symbol in a soft circle, with an optional badge for a
/// permission answer. Decorative, so VoiceOver skips it; the status card says
/// the same thing in words.
struct OnboardingSymbolVisual: View {
    let symbol: String
    var badge: OnboardingTone? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = OnboardingStyle.palette(for: colorScheme)
        let badgeTransition: AnyTransition = reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity)

        Image(systemName: symbol)
            .font(.system(size: 40, weight: .semibold))
            .foregroundStyle(palette.accent)
            .frame(width: 96, height: 96)
            .background(palette.accent.opacity(0.14), in: .circle)
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    Image(systemName: badge == .positive ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(palette.base, badge.color(in: palette))
                        .background(palette.base, in: .circle)
                        .offset(x: 4, y: 4)
                        .transition(badgeTransition)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Paper by day, espresso by night, with the same fine grain.
struct OnboardingBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            Theme.espresso
                .overlay {
                    Image("PaperGrain")
                        .resizable(resizingMode: .tile)
                        .opacity(OnboardingStyle.darkGrainOpacity)
                }
                .accessibilityHidden(true)
        } else {
            PaperBackground()
        }
    }
}
