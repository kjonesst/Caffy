import SwiftUI

/// Home's scroll engine.
///
/// Each era card is a "chapter" you can scroll freely inside. The engine only
/// steps in when a scroll would carry you past the edge of the card you're in:
///
/// - A scroll that carries past a card's bottom keeps going, in one motion,
///   until the top of the next card is at the top of the screen.
/// - Scrolling up past a card's top mirrors this, landing on the bottom of the
///   previous card (or on the header, above the first card).
/// - Inside a card taller than the screen, a flick coasts only about half as
///   far as usual (`insideCardMomentum`) and stops at the card's end, so you
///   can't race past a card by accident.
/// - Moving between two cards has tension: a slow drag must pull at least
///   `tensionThreshold` past the edge, or it springs back. A quick flick made
///   from the card's end goes straight through. (`HomeView` draws the
///   resistance; see `EraScrollTension`.)
/// - Only one card is crossed per scroll, however hard the flick.
/// - From the header, the first scroll down brings the first card's top to the
///   top of the screen.
///
/// Card frames come from `HomeView` in the scroll content's coordinate space.
nonisolated struct EraScrollBehavior: ScrollTargetBehavior {
    /// The era cards' frames in scroll content coordinates, top to bottom.
    var cardFrames: [CGRect]

    /// How far (in points) outside a card the scroll can start and still count
    /// as being in that card, for example after an interrupted snap.
    var edgeTolerance: CGFloat = 32
    /// How far (in points) past a card's edge a scroll must go to move on to
    /// the neighbouring card. Anything less settles on the edge, so a stray
    /// touch doesn't change cards.
    var minimumStep: CGFloat = 12
    /// Space kept clear at the bottom of the screen for the floating tab bar,
    /// so a card's bottom lands just above it rather than underneath.
    var bottomClearance: CGFloat = 66
    /// How far (in points) a slow drag must pull past a card's edge before
    /// letting go moves on to the neighbouring card.
    var tensionThreshold: CGFloat = 140
    /// How much momentum (in points the scroll would have kept travelling
    /// after the finger lifted) counts as a flick, which skips the tension.
    var flickDistance: CGFloat = 500
    /// The share of a flick's coasting distance kept inside a card taller than
    /// the screen. Lower feels heavier; 1 would be normal iOS scrolling.
    var insideCardMomentum: CGFloat = 0.5

    /// Receives jumps and spring-backs so `HomeView` can animate them smoothly,
    /// instead of leaving them to the system's slower deceleration.
    var handoff: EraSnapHandoff?

    /// A range of scroll offsets the user can move through freely.
    struct Stop {
        var top: CGFloat
        var bottom: CGFloat
    }

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let proposed = target.rect.minY
        let start = context.originalTarget.rect.minY
        // How far the finger pulled past the edge, as recorded by `HomeView`
        // during the drag. Cleared once read, so a scroll `HomeView` animates
        // itself isn't mistaken for another pull against the tension.
        let dragOvershoot = handoff?.dragOvershoot ?? 0
        handoff?.dragOvershoot = 0
        let decision = resolve(
            from: start,
            proposed: proposed,
            viewport: context.containerSize.height,
            contentHeight: context.contentSize.height,
            dragOvershoot: dragOvershoot,
            releaseOffset: handoff?.releaseOffset ?? start
        )
        target.rect.origin.y = decision.offset

        // `HomeView` animates two kinds of release itself, each as one smooth
        // motion instead of the system's deceleration:
        // - a jump, when this behavior moved the target to another card;
        // - a settle, when a pull against the tension wasn't far enough and
        //   the card springs back to its edge.
        // Both need the target to have been changed here. When `HomeView`'s
        // own animation passes through, its target is already a card edge, so
        // nothing is handed over again and the two can't loop.
        guard let handoff, decision.offset != proposed else { return }
        let move: EraSnapHandoff.Move
        if decision.crossesCard {
            move = .jump
        } else if dragOvershoot != 0 {
            move = .settle
        } else {
            return
        }
        let offset = decision.offset
        // Runs just after the finger lifts.
        Task { @MainActor in handoff.move?(offset, move) }
    }

    /// Where a scroll should settle.
    ///
    /// - Parameters:
    ///   - start: The offset when the scroll began.
    ///   - proposed: Where the scroll would naturally come to rest.
    ///   - dragOvershoot: How far the finger pulled past the starting card's
    ///     edge (see `overshoot(start:current:viewport:contentHeight:)`).
    ///   - releaseOffset: The offset when the finger lifted.
    func offset(
        from start: CGFloat, proposed: CGFloat, viewport: CGFloat, contentHeight: CGFloat,
        dragOvershoot: CGFloat, releaseOffset: CGFloat
    ) -> CGFloat {
        resolve(
            from: start, proposed: proposed, viewport: viewport, contentHeight: contentHeight,
            dragOvershoot: dragOvershoot, releaseOffset: releaseOffset
        ).offset
    }

    /// The header (first) and each card's free range, top to bottom.
    func stops(viewport: CGFloat, contentHeight: CGFloat) -> [Stop] {
        let maxOffset = max(0, contentHeight - viewport)
        func clamp(_ y: CGFloat) -> CGFloat { min(max(y, 0), maxOffset) }

        // The header is a stop of its own at offset 0. Each card's free range
        // runs from its top at the top of the screen to its bottom just above
        // the tab bar; a card shorter than the screen has a single offset.
        let visibleHeight = max(viewport - bottomClearance, 1)
        var stops = [Stop(top: 0, bottom: 0)]
        for frame in cardFrames {
            let top = clamp(frame.minY)
            stops.append(Stop(top: top, bottom: max(top, clamp(frame.maxY - visibleHeight))))
        }
        return stops
    }

    /// The index of the stop a scroll starting at `start` began in, if any.
    private func stopIndex(containing start: CGFloat, in stops: [Stop]) -> Int? {
        stops.firstIndex { start >= $0.top - edgeTolerance && start <= $0.bottom + edgeTolerance }
    }

    /// How far a drag that began at `start` has pulled past the edge of the
    /// card it began in, toward a neighbouring card: positive past the bottom,
    /// negative past the top, and 0 inside the card. Moving to or from the
    /// header has no tension, so it's always 0 there.
    func overshoot(start: CGFloat, current: CGFloat, viewport: CGFloat, contentHeight: CGFloat) -> CGFloat {
        guard !cardFrames.isEmpty, viewport > 0 else { return 0 }
        let stops = stops(viewport: viewport, contentHeight: contentHeight)
        // Index 0 is the header, so cards start at 1.
        guard let index = stopIndex(containing: start, in: stops), index > 0 else { return 0 }
        let stop = stops[index]
        if current > stop.bottom && index + 1 < stops.count {
            return current - stop.bottom
        }
        if current < stop.top && index - 1 > 0 {
            return current - stop.top
        }
        return 0
    }

    /// The settling offset, and whether getting there moves to another card.
    private func resolve(
        from start: CGFloat, proposed: CGFloat, viewport: CGFloat, contentHeight: CGFloat,
        dragOvershoot: CGFloat, releaseOffset: CGFloat
    ) -> (offset: CGFloat, crossesCard: Bool) {
        guard !cardFrames.isEmpty, viewport > 0 else { return (proposed, false) }

        let maxOffset = max(0, contentHeight - viewport)
        func clamp(_ y: CGFloat) -> CGFloat { min(max(y, 0), maxOffset) }

        let stops = stops(viewport: viewport, contentHeight: contentHeight)
        let movingDown = proposed > start

        if let index = stopIndex(containing: start, in: stops) {
            let stop = stops[index]

            // Inside a card taller than the screen, coasting is shortened so a
            // flick can't race through the card, and it never carries past the
            // card's edge. This applies when the finger let go well inside the
            // card, not when it's at the end it's heading toward (where a
            // flick may move on) or pulling against the tension.
            let momentum = proposed - releaseOffset
            let releasedInside = releaseOffset >= stop.top && releaseOffset <= stop.bottom
            let atEndHeadingFor = momentum > 0
                ? releaseOffset >= stop.bottom - edgeTolerance
                : releaseOffset <= stop.top + edgeTolerance
            if stop.top < stop.bottom, dragOvershoot == 0, releasedInside, !atEndHeadingFor {
                let damped = releaseOffset + momentum * insideCardMomentum
                return (clamp(min(max(damped, stop.top), stop.bottom)), false)
            }

            if proposed >= stop.top && proposed <= stop.bottom {
                // Free scrolling inside the card.
                return (clamp(proposed), false)
            } else if proposed > stop.bottom {
                // Past the card's bottom: carry on to the next card's top, if
                // the drag beat the tension (leaving the header has none).
                let passedEdge = proposed - stop.bottom > minimumStep
                // A flick only counts when made from the card's end.
                let flickedFromEnd = releaseOffset >= stop.bottom - edgeTolerance
                    && proposed - releaseOffset >= flickDistance
                let beatTension = index == 0
                    || dragOvershoot >= tensionThreshold
                    || flickedFromEnd
                if passedEdge && beatTension && index + 1 < stops.count {
                    return (clamp(stops[index + 1].top), true)
                }
                return (clamp(stop.bottom), false)
            } else {
                // Past the card's top: carry on to the previous card's bottom,
                // if the drag beat the tension (returning to the header has
                // none).
                let passedEdge = stop.top - proposed > minimumStep
                let flickedFromEnd = releaseOffset <= stop.top + edgeTolerance
                    && releaseOffset - proposed >= flickDistance
                let beatTension = index == 1
                    || -dragOvershoot >= tensionThreshold
                    || flickedFromEnd
                if passedEdge && beatTension && index > 0 {
                    return (clamp(stops[index - 1].bottom), true)
                }
                return (clamp(stop.top), false)
            }
        } else if movingDown {
            // Between cards (for example, a snap was interrupted): go to the
            // next card's top.
            let next = stops.first(where: { $0.top > start })?.top ?? stops[stops.count - 1].bottom
            return (clamp(next), true)
        } else {
            // Between cards, moving up: go to the previous card's bottom.
            let previous = stops.last(where: { $0.bottom < start })?.bottom ?? 0
            return (clamp(previous), true)
        }
    }
}

/// Passes releases from `EraScrollBehavior` to `HomeView` to animate.
///
/// A scroll target behavior can only choose where scrolling ends, not how fast
/// it gets there, so `HomeView` sets `move` to animate the scroll itself.
/// It also carries the drag details `EraScrollBehavior` needs to judge the
/// tension when the finger lifts.
///
/// `@unchecked Sendable` is safe here because everything is only read and
/// written on the main thread, where scrolling runs.
nonisolated final class EraSnapHandoff: @unchecked Sendable {
    /// The kinds of release `HomeView` animates.
    enum Move {
        /// On to the neighbouring card.
        case jump
        /// Back to the edge of the same card, after a pull that didn't beat
        /// the tension.
        case settle
    }

    var move: (@MainActor (CGFloat, Move) -> Void)?
    /// How far the current drag has pulled past its card's edge.
    var dragOvershoot: CGFloat = 0
    /// The scroll offset at the latest moment of the drag.
    var releaseOffset: CGFloat = 0
}
