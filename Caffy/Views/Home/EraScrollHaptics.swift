import CoreHaptics

/// The haptics that go with Home's scroll engine.
///
/// - `pullStarted()`: a soft tap as a drag starts pulling toward the next card.
/// - `passedThreshold()`: a crisp tick once the pull is far enough to move on.
/// - `springBack()`: five taps, strong to soft, as a card springs back to its
///   edge, like a ratchet winding down.
///
/// Core Haptics plays each cue as one pattern with exact timing, which a
/// series of single taps fired on timers can't do. It needs no entitlement.
/// On the simulator, and on devices without haptics, every call does nothing.
@MainActor
final class EraScrollHaptics {
    /// One tap: when it plays (seconds from the start of the cue), how strong
    /// it is, and how sharp it feels (0 is a dull thud, 1 a crisp click).
    private struct Tap {
        let time: TimeInterval
        let intensity: Float
        let sharpness: Float
    }

    // The cues. Tune them here.
    private static let pullStartedTaps = [Tap(time: 0, intensity: 0.35, sharpness: 0.2)]
    private static let passedThresholdTaps = [Tap(time: 0, intensity: 0.6, sharpness: 0.7)]
    /// The gaps widen as the card slows into place over the 0.35s settle, and
    /// the last tap lands just before it stops.
    private static let springBackTaps = [
        Tap(time: 0, intensity: 1.0, sharpness: 0.5),
        Tap(time: 0.05, intensity: 0.8, sharpness: 0.45),
        Tap(time: 0.11, intensity: 0.6, sharpness: 0.4),
        Tap(time: 0.18, intensity: 0.45, sharpness: 0.35),
        Tap(time: 0.26, intensity: 0.3, sharpness: 0.3)
    ]

    private let engine: CHHapticEngine?
    private let pullStartedPattern: CHHapticPattern?
    private let passedThresholdPattern: CHHapticPattern?
    private let springBackPattern: CHHapticPattern?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = try? CHHapticEngine() else {
            engine = nil
            pullStartedPattern = nil
            passedThresholdPattern = nil
            springBackPattern = nil
            return
        }
        // No audio, and let the hardware sleep between cues to save power.
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        Self.restartAfterReset(engine)
        self.engine = engine
        pullStartedPattern = Self.pattern(Self.pullStartedTaps)
        passedThresholdPattern = Self.pattern(Self.passedThresholdTaps)
        springBackPattern = Self.pattern(Self.springBackTaps)
    }

    /// Starts the engine ahead of the first cue, so it plays without delay.
    func prepare() {
        try? engine?.start()
    }

    func pullStarted() { play(pullStartedPattern) }
    func passedThreshold() { play(passedThresholdPattern) }
    func springBack() { play(springBackPattern) }

    private func play(_ pattern: CHHapticPattern?) {
        guard let engine, let pattern else { return }
        // Haptics are decoration, so a failure here is simply ignored.
        try? engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
    }

    /// The system can reset the engine (for example, after the app returns from
    /// the background); this restarts it so the next cue still plays.
    ///
    /// `nonisolated` because the reset handler runs on a background queue: a
    /// closure made inside this main-actor class would expect the main thread.
    nonisolated private static func restartAfterReset(_ engine: CHHapticEngine) {
        engine.resetHandler = { [weak engine] in
            try? engine?.start()
        }
    }

    private static func pattern(_ taps: [Tap]) -> CHHapticPattern? {
        let events = taps.map { tap in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: tap.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: tap.sharpness)
                ],
                relativeTime: tap.time
            )
        }
        return try? CHHapticPattern(events: events, parameters: [])
    }
}
