import SwiftData
import SwiftUI

/// The Home tab: one card per era, newest first.
struct HomeView: View {
    /// `@Query` fetches from SwiftData and re-renders the view when the data
    /// changes.
    @Query(sort: \Era.startDate, order: .reverse) private var eras: [Era]

    /// Each era card's frame in the scroll content, used by the scroll engine.
    @State private var cardFrames: [Era.ID: CGRect] = [:]

    /// Where the feed is scrolled to. Bound to the scroll view so jumps and
    /// spring-backs can be animated from here.
    @State private var position = ScrollPosition()
    /// Receives jumps and spring-backs from the scroll engine.
    @State private var snapHandoff = EraSnapHandoff()
    /// The resistance drawn while dragging from one card toward the next.
    @State private var tension = EraScrollTension()
    /// The taps that go with pulling between cards and springing back.
    @State private var haptics = EraScrollHaptics()

    private static let contentSpace = "HomeScrollContent"
    /// How card-to-card jumps move: quick, settling without a bounce.
    private static let jumpAnimation = Animation.snappy(duration: 0.3)
    /// How a card springs back to its edge after a pull that didn't beat the
    /// tension: smooth, no bounce.
    private static let settleAnimation = Animation.smooth(duration: 0.35)

    /// The scroll engine, built from the latest card frames.
    private var scrollEngine: EraScrollBehavior {
        EraScrollBehavior(
            cardFrames: eras.compactMap { cardFrames[$0.id] }.sorted { $0.minY < $1.minY },
            handoff: snapHandoff
        )
    }

    var body: some View {
        // Built once per update and shared with the drag tracking below, so
        // the per-frame work during a drag is only arithmetic.
        let engine = scrollEngine

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("caffy")
                        .font(Theme.display(56, weight: .heavy, relativeTo: .largeTitle))
                        .tracking(-2.2)
                        // The launch splash's title flies here, then hands over.
                        .caffyTitleTarget()
                        .accessibilityAddTraits(.isHeader)
                    Text("Your photos, with the music of the time.")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.softInk)
                }
                .padding(.horizontal, 6)

                ForEach(Array(eras.enumerated()), id: \.element.id) { index, era in
                    EraCard(era: era, number: eras.count - index)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .named(Self.contentSpace))
                        } action: { frame in
                            cardFrames[era.id] = frame
                        }
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 120)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .background(PaperBackground())
            .coordinateSpace(.named(Self.contentSpace))
            // Outside the coordinate space, so the card frames measured above
            // don't move with the tension.
            .modifier(TensionOffset(tension: tension))
        }
        .scrollPosition($position)
        .scrollTargetBehavior(engine)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(geometry)
        } action: { _, metrics in
            updateTension(with: metrics, engine: engine)
        }
        .onScrollPhaseChange { oldPhase, newPhase in
            if newPhase == .interacting {
                tension.beginDrag()
                snapHandoff.dragOvershoot = 0
                snapHandoff.releaseOffset = tension.currentOffset
            } else if oldPhase == .interacting {
                fingerLifted()
            }
        }
        .onAppear {
            haptics.prepare()
            snapHandoff.move = { [position = $position, tension, haptics] offset, move in
                // Five fading taps as the card springs back, starting with
                // the animation.
                if move == .settle { haptics.springBack() }
                // The scroll and the resistance move in one transaction, on
                // one curve, so the card glides without passing its resting
                // point and coming back.
                withAnimation(move == .jump ? Self.jumpAnimation : Self.settleAnimation) {
                    position.wrappedValue.scrollTo(y: offset)
                    tension.endDrag()
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(Theme.cream)
        .overlay {
            if eras.isEmpty {
                ContentUnavailableView(
                    "No Eras Yet",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Caffy will add eras from your photos and listening.")
                )
            }
        }
    }

    /// Tracks how far the current drag has pulled past its card's edge, for
    /// the drawn resistance and for the engine's decision at release.
    private func updateTension(with metrics: ScrollMetrics, engine: EraScrollBehavior) {
        tension.currentOffset = metrics.offset
        guard let start = tension.dragStart else { return }
        let overshoot = engine.overshoot(
            start: start, current: metrics.offset,
            viewport: metrics.viewport, contentHeight: metrics.contentHeight
        )
        let wasPulling = tension.isPulling
        let hadPassedThreshold = tension.passedThreshold
        tension.update(overshoot: overshoot, threshold: engine.tensionThreshold, viewport: metrics.viewport)
        // A soft tap as the drag starts pulling toward the next card, and a
        // crisp tick once the pull is far enough to move on.
        if !wasPulling && tension.isPulling { haptics.pullStarted() }
        if !hadPassedThreshold && tension.passedThreshold { haptics.passedThreshold() }
        snapHandoff.dragOvershoot = overshoot
        snapHandoff.releaseOffset = metrics.offset
    }

    /// Called when the finger lifts.
    private func fingerLifted() {
        tension.releaseDrag()
        guard tension.visualOffset != 0 else {
            // No resistance showing, so there's nothing to ease away.
            tension.endDrag()
            return
        }
        // The engine hands this release to `snapHandoff.move`, which eases the
        // resistance away together with the scroll. As a safety net, if it
        // had nothing to hand over (for example, the drag came back inside
        // the card before letting go), ease the resistance away shortly after.
        let drag = tension.dragID
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard tension.dragID == drag, tension.visualOffset != 0 else { return }
            withAnimation(Self.settleAnimation) { tension.endDrag() }
        }
    }
}

/// The parts of the scroll geometry the tension needs, in the same
/// coordinates `EraScrollBehavior` works in: offset 0 is the top of the
/// content resting just below the status bar, and the viewport is the height
/// between the safe areas.
nonisolated private struct ScrollMetrics: Equatable {
    var offset: CGFloat
    var viewport: CGFloat
    var contentHeight: CGFloat

    init(_ geometry: ScrollGeometry) {
        offset = geometry.contentOffset.y + geometry.contentInsets.top
        // Already excludes the safe areas, matching the engine's viewport.
        viewport = geometry.containerSize.height
        contentHeight = geometry.contentSize.height
    }
}

#Preview(traits: .sampleData) {
    HomeView()
}
