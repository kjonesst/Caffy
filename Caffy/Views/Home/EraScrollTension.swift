import SwiftUI

/// The resistance you feel when dragging from one era card toward the next.
///
/// SwiftUI's scroll view always follows the finger 1:1, so the resistance is
/// drawn instead: once a drag pulls past a card's edge, `visualOffset` pushes
/// the content back toward that edge, so it only travels a rubber-banded
/// fraction of the finger's distance. `EraScrollBehavior` then decides, when
/// the finger lifts, whether the pull was far enough to move on.
@Observable
final class EraScrollTension {
    /// The latest scroll offset. Ignored by Observation because it changes on
    /// every frame and no view needs to redraw for it.
    @ObservationIgnored var currentOffset: CGFloat = 0

    /// The scroll offset when the finger went down, or `nil` when no drag is
    /// being tracked.
    @ObservationIgnored private(set) var dragStart: CGFloat?

    /// Counts drags, so a delayed clean-up can tell whether a new drag has
    /// started since it was scheduled.
    @ObservationIgnored private(set) var dragID = 0

    /// How far to push the content back toward the edge it's being pulled
    /// past. Only `TensionOffset` reads this, so per-frame changes don't
    /// redraw the era cards.
    private(set) var visualOffset: CGFloat = 0

    /// How far the drag has pulled past its card's edge (negative when
    /// pulling up past the top), or 0 inside the card.
    @ObservationIgnored private(set) var overshoot: CGFloat = 0

    /// Whether the drag is pulling toward a neighbouring card.
    var isPulling: Bool { overshoot != 0 }

    /// Whether the pull is far enough that letting go will move on. Read by
    /// `HomeView` for the haptics, never in a view's `body`, so it's ignored
    /// by Observation and a pull never redraws Home.
    @ObservationIgnored private(set) var passedThreshold = false

    func beginDrag() {
        dragStart = currentOffset
        dragID += 1
        // A new drag starts unpulled, so its first pull gets its own tap.
        overshoot = 0
        passedThreshold = false
    }

    /// Stops tracking when the finger lifts, but keeps the resistance drawn
    /// until `endDrag()` eases it away together with the scroll.
    func releaseDrag() {
        dragStart = nil
    }

    /// Updates the resistance for a drag that has pulled `overshoot` points
    /// past its card's edge (negative when pulling up past the top).
    func update(overshoot: CGFloat, threshold: CGFloat, viewport: CGFloat) {
        self.overshoot = overshoot
        let offset = overshoot - Self.rubberBand(overshoot, dimension: viewport)
        // Observation notifies on every assignment, so only assign changes.
        if offset != visualOffset { visualOffset = offset }
        passedThreshold = abs(overshoot) >= threshold
    }

    /// Clears the drag and its resistance. Call inside the same `withAnimation`
    /// as the scroll that follows the release, so both move on one curve.
    func endDrag() {
        dragStart = nil
        overshoot = 0
        if visualOffset != 0 { visualOffset = 0 }
        passedThreshold = false
    }

    /// How far content travels for a pull of `distance`, using the same curve
    /// as iOS's own over-scroll: almost 1:1 at first, then stiffer the further
    /// you pull. A 140pt pull on a 778pt-tall screen moves the content ~70pt.
    static func rubberBand(_ distance: CGFloat, dimension: CGFloat) -> CGFloat {
        guard dimension > 0 else { return distance }
        let stretched = (1 - 1 / (abs(distance) * 0.55 / dimension + 1)) * dimension
        return distance < 0 ? -stretched : stretched
    }
}

/// Shifts the scroll content by the tension's `visualOffset`.
///
/// This uses `visualEffect` rather than `.offset`: `.offset` also moves the
/// geometry that the card frames are measured from, which made the scroll
/// engine's card edges drift during a pull (and redrew all of Home on every
/// frame). A visual effect only changes what's drawn.
struct TensionOffset: ViewModifier {
    let tension: EraScrollTension

    func body(content: Content) -> some View {
        let offset = tension.visualOffset
        content.visualEffect { effect, _ in
            effect.offset(y: offset)
        }
    }
}
