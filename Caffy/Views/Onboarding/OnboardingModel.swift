import Observation

/// Which onboarding step is showing, and how to move between steps.
///
/// It knows nothing about views or permissions, so it stays easy to test and
/// preview. `OnboardingView` animates whatever it changes.
@Observable final class OnboardingModel {
    enum Direction {
        case forward
        case backward
    }

    private(set) var step: OnboardingStep
    /// Which way the last move went, so the next screen slides in from the
    /// right side.
    private(set) var direction = Direction.forward

    @ObservationIgnored private let onFinish: () -> Void

    /// - Parameter direction: How the first step was "arrived at". Previews use
    ///   `.backward` to stop steps that move on by themselves from doing so.
    init(step: OnboardingStep = .welcome, direction: Direction = .forward, onFinish: @escaping () -> Void = {}) {
        self.step = step
        self.direction = direction
        self.onFinish = onFinish
    }

    func next() {
        guard let next = step.next else { return }
        move(to: next, direction: .forward)
    }

    func back() {
        guard step.allowsBack, let previous = step.previous else { return }
        move(to: previous, direction: .backward)
    }

    /// "Skip" on the explainer steps jumps to the Apple Music ask.
    func skipToPermissions() {
        guard step.allowsSkip else { return }
        move(to: .music, direction: .forward)
    }

    /// "Open Caffy" on the last step.
    func finish() {
        onFinish()
    }

    private func move(to step: OnboardingStep, direction: Direction) {
        self.direction = direction
        self.step = step
    }
}
