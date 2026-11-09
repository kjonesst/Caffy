import SwiftUI

/// Holds the onboarding steps: the top bar (Back, progress, Skip), the current
/// step, and the calm transition between steps.
struct OnboardingView: View {
    @State private var model: OnboardingModel

    @Environment(PermissionsManager.self) private var permissions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    init(
        startingAt step: OnboardingStep = .welcome,
        arriving direction: OnboardingModel.Direction = .forward,
        onFinish: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: OnboardingModel(step: step, direction: direction, onFinish: onFinish))
    }

    var body: some View {
        ZStack {
            stepView
                .id(model.step)
                .transition(transition)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsTopBar { topBar }
        }
        .animation(reduceMotion ? OnboardingStyle.calmStepAnimation : OnboardingStyle.stepAnimation, value: model.step)
        .background { OnboardingBackground().ignoresSafeArea() }
        .environment(model)
        .task { await permissions.refresh() }
        // Coming back from Settings: pick up anything the user changed there.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await permissions.refresh() }
            }
        }
    }

    @ViewBuilder private var stepView: some View {
        switch model.step {
        case .welcome: WelcomeStep()
        case .problem: ProblemStep()
        case .howItWorks: HowItWorksStep()
        case .privacy: PrivacyStep()
        case .music: MusicStep()
        case .photos: PhotosStep()
        case .ready: ReadyStep()
        }
    }

    /// The new step slides in a little from the side it's coming from, while
    /// the old one fades. With Reduce Motion, both only fade.
    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let slide = model.direction == .forward ? OnboardingStyle.stepSlide : -OnboardingStyle.stepSlide
        return .asymmetric(
            insertion: .offset(x: slide).combined(with: .opacity),
            removal: .opacity
        )
    }

    // MARK: Top bar

    private var showsTopBar: Bool {
        model.step.allowsBack || model.step.showsProgress || model.step.allowsSkip
    }

    private var topBar: some View {
        let palette = OnboardingStyle.palette(for: colorScheme)

        return ZStack {
            if let index = model.step.progressIndex {
                ProgressSegments(current: index, palette: palette)
            }
            HStack {
                if model.step.allowsBack {
                    Button(action: model.back) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: OnboardingStyle.topBarButtonSize, height: OnboardingStyle.topBarButtonSize)
                            .contentShape(.circle)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel(Text(OnboardingCopy.Common.back))
                    .accessibilityShowsLargeContentViewer {
                        Label { Text(OnboardingCopy.Common.back) } icon: { Image(systemName: "chevron.left") }
                    }
                }
                Spacer()
                if model.step.allowsSkip {
                    Button(action: model.skipToPermissions) {
                        Text(OnboardingCopy.Common.skip)
                            .font(Theme.display(17, weight: .semibold, relativeTo: .body))
                            .padding(.horizontal, 16)
                            .frame(minHeight: OnboardingStyle.topBarButtonSize)
                            .contentShape(.capsule)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .accessibilityHint(Text(OnboardingCopy.Common.skipHint))
                    .accessibilityShowsLargeContentViewer()
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.title)
        // The bar stops growing at the largest standard size so Skip never
        // runs into the progress bar; a long press shows it enlarged instead.
        .dynamicTypeSize(...OnboardingStyle.topBarMaxTypeSize)
        .frame(minHeight: OnboardingStyle.topBarButtonSize)
        .padding(.horizontal, OnboardingStyle.topBarHorizontalPadding)
        .padding(.top, 4)
    }
}

/// Five short bars, filled up to the current step.
private struct ProgressSegments: View {
    let current: Int
    let palette: OnboardingStyle.Palette

    var body: some View {
        HStack(spacing: OnboardingStyle.progressSegmentSpacing) {
            ForEach(1...OnboardingStep.progressCount, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? palette.accent : palette.faint)
                    .frame(width: OnboardingStyle.progressSegmentWidth, height: OnboardingStyle.progressSegmentHeight)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(OnboardingCopy.Common.progress(current, of: OnboardingStep.progressCount)))
    }
}

// MARK: - Previews

/// Sets up onboarding previews, which don't run `CaffyApp`: loads Caffy's
/// fonts and provides a fake `PermissionsManager` that hasn't asked yet. A
/// preview can provide its own manager to show a different outcome.
struct OnboardingPreview: PreviewModifier {
    static func makeSharedContext() async throws {
        Theme.registerFonts()
    }

    func body(content: Content, context: Void) -> some View {
        content
            .environment(PermissionsManager(client: PreviewPermissionsClient.notAsked))
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var onboarding: Self { .modifier(OnboardingPreview()) }
}

#Preview("Whole flow", traits: .onboarding) {
    OnboardingView()
}

#Preview("Whole flow, dark", traits: .onboarding) {
    OnboardingView()
        .preferredColorScheme(.dark)
}
