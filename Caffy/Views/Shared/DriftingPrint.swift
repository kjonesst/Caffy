import SwiftUI

/// Makes a print drift as it scrolls: prints fan apart near the screen's edges
/// and gather together mid-screen. With Reduce Motion on, they stay still.
struct DriftingPrint: ViewModifier {
    /// How a print moves, given how far it sits from the middle of the screen.
    /// `distance` runs from about -1.3 (well above) to 1.3 (well below).
    typealias Drift = @Sendable (_ distance: Double) -> (x: Double, y: Double, rotation: Double)

    /// The print's resting tilt, in degrees.
    let tilt: Double
    let drift: Drift

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Copies for the closure, which SwiftUI may run off the main actor.
        let isCalm = reduceMotion
        let tilt = tilt
        let drift = drift

        // `visualEffect` reads the print's position on every scroll frame
        // without updating any state, so scrolling stays smooth.
        content.visualEffect { effect, geometry in
            let frame = geometry.frame(in: .scrollView)
            let middle = (geometry.bounds(of: .scrollView)?.height ?? 844) / 2
            let distance = min(1.3, max(-1.3, (frame.midY - middle) / middle))
            let move = isCalm ? (x: 0, y: 0, rotation: tilt) : drift(distance)
            return effect
                .rotationEffect(.degrees(move.rotation))
                .offset(x: move.x, y: move.y)
        }
    }
}
