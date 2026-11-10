import SwiftUI

// MARK: - Constants

/// Every colour, timing and size `MemoryBurst` uses, in one place.
enum MemoryBurstStyle {
    // Colours. A burst follows light and dark mode unless it's given a colour.
    static let lightFilament = Theme.ink
    static let darkFilament = Theme.bone
    static let printBorder = Theme.cream
    static let printShadow = Theme.shadow.opacity(0.3)
    static let iconColor = Theme.cream.opacity(0.8)

    // Defaults, matching the original web component.
    static let tentacleCount = 260
    static let radius = 0.48
    static let duration = 1.35
    static let seed = 23
    static let particleRatio = 0.62
    static let maxTipArtwork = 6

    // The idle "inhale" after the burst.
    static let fieldSpeed = 0.92
    static let fieldAmount = 0.015
    static let lineSpeed = 1.28
    static let lineAmount = 0.018
    static let tipPulseAmount = 0.1
    static let chipPulseAmount = 0.04
    /// Breathing is slow, so 30fps is plenty and saves battery.
    static let breathFrameInterval = 1.0 / 30
    /// Seconds over which breathing fades in once the burst settles.
    static let breathRamp = 1.2

    // The centre stack: a photo print over a playlist cover. Sizes are
    // fractions of `printSide`, which is a fraction of the burst's shorter side.
    static let printSide = 0.27
    static let photoAspect = 0.8
    static let photoOffset = CGSize(width: -0.2, height: -0.05)
    static let photoTilt = -6.0
    static let photoCorner = 10.0
    static let photoBorder = 5.0
    static let coverScale = 0.82
    static let coverOffset = CGSize(width: 0.26, height: 0.14)
    static let coverTilt = 5.0
    static let coverCorner = 4.0
    static let coverBorder = 4.0
    static let printIconScale = 0.16
    static let printShadowRadius = 8.0
    static let printShadowY = 6.0
    /// The stack's widest extent, in `printSide`s. Filaments start at 30% of
    /// it, so they tuck under the prints and fill the notch where the two
    /// overlap. (The original uses 42% of `coreSize` for a single square mark.)
    static let coreExtent = 1.27
    static let coreInset = 0.3

    // Artwork chips riding on some filament tips.
    static let chipSize = 30.0
    static let chipCorner = 7.0
    static let chipBorder = 2.0
    static let chipLengths = 0.6...0.86
    static let chipMaxTilt = 8.0

    // Motion.
    static let centreSpring = Animation.spring(duration: 0.6, bounce: 0.3)
    static let centreStartScale = 0.85
    static let centreTapScale = 0.94
    static let calmFade = Animation.easeInOut(duration: 0.35)
    static let calmFadeOut = Animation.easeOut(duration: 0.15)
    /// How the burst fades in when it has waited for the launch splash to finish.
    static let afterSplashFade = Animation.easeOut(duration: 0.5)
}

// MARK: - Content

/// A picture shown in the burst: a placeholder for now, a real photo or
/// Apple Music artwork later.
enum BurstArtwork {
    /// A flat tone picked from `seed`, like elsewhere in the app.
    case placeholder(seed: String)
    /// A loaded image, such as a photo from PhotoKit.
    case image(Image)
    /// A remote image, such as MusicKit artwork from `Artwork.url(width:height:)`.
    case url(URL)

    /// Placeholder chips for the filament tips.
    static func placeholders(_ count: Int) -> [BurstArtwork] {
        let seeds = ["Night Drive", "Harbour", "Rooftop", "Road Trip", "Late Train", "Summer"]
        return seeds.prefix(count).map { .placeholder(seed: $0) }
    }
}

/// Draws one `BurstArtwork`, filling its frame.
struct BurstArtworkView: View {
    let artwork: BurstArtwork
    /// An SF Symbol drawn over placeholders, so they read as a photo or a cover.
    var iconSymbol: String? = nil
    var iconSize = 0.0

    var body: some View {
        switch artwork {
        case .placeholder(let seed):
            placeholder(seed: seed)
        case .image(let image):
            image.resizable().scaledToFill()
        case .url(let url):
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder(seed: url.absoluteString)
            }
        }
    }

    private func placeholder(seed: String) -> some View {
        PhotoPlaceholder(seed: seed, showsIcon: false)
            .overlay {
                if let iconSymbol {
                    Image(systemName: iconSymbol)
                        .font(.system(size: iconSize))
                        .foregroundStyle(MemoryBurstStyle.iconColor)
                }
            }
    }
}

// MARK: - Component

/// Caffy's Welcome hero: hair-line filaments burst out from a photo and its
/// playlist cover, a few carrying more artwork on their tips, then keep a slow
/// inhale. Tap to replay.
///
/// A native port of the 21st.dev "LogoBurst" component. With Reduce Motion on,
/// it fades in already settled and doesn't breathe.
struct MemoryBurst: View {
    let photo: BurstArtwork
    let artwork: BurstArtwork
    let tipArtwork: [BurstArtwork]
    let radius: Double
    let duration: Double
    let breathes: Bool
    let color: Color?
    let replayTrigger: Int
    let replaysOnTap: Bool
    private let layout: BurstLayout

    /// - Parameters:
    ///   - photo: The print in the centre.
    ///   - artwork: The playlist cover overlapping it.
    ///   - tipArtwork: Up to six small pictures riding on filament tips.
    ///   - tentacleCount: How many filaments (24–900).
    ///   - radius: Outer reach, as a fraction of the shorter side (0.12–0.95).
    ///   - duration: Burst length in seconds (0.2–6).
    ///   - seed: Picks the filament layout. The same seed always looks the same.
    ///   - particleRatio: Share of filaments with a dot on the tip (0–1).
    ///   - breathes: Keep a slow inhale after the burst.
    ///   - color: Filament colour. `nil` follows light and dark mode.
    ///   - replayTrigger: Change it to replay the burst from code.
    ///   - replaysOnTap: Tapping the burst replays it.
    init(
        photo: BurstArtwork = .placeholder(seed: "Bondi Beach"),
        artwork: BurstArtwork = .placeholder(seed: "Golden Hour"),
        tipArtwork: [BurstArtwork] = BurstArtwork.placeholders(MemoryBurstStyle.maxTipArtwork),
        tentacleCount: Int = MemoryBurstStyle.tentacleCount,
        radius: Double = MemoryBurstStyle.radius,
        duration: Double = MemoryBurstStyle.duration,
        seed: Int = MemoryBurstStyle.seed,
        particleRatio: Double = MemoryBurstStyle.particleRatio,
        breathes: Bool = true,
        color: Color? = nil,
        replayTrigger: Int = 0,
        replaysOnTap: Bool = true
    ) {
        let tips = Array(tipArtwork.prefix(MemoryBurstStyle.maxTipArtwork))
        self.photo = photo
        self.artwork = artwork
        self.tipArtwork = tips
        self.radius = min(max(radius, 0.12), 0.95)
        self.duration = min(max(duration, 0.2), 6)
        self.breathes = breathes
        self.color = color
        self.replayTrigger = replayTrigger
        self.replaysOnTap = replaysOnTap
        layout = BurstLayout(
            count: min(max(tentacleCount, 24), 900),
            seed: seed,
            particleRatio: min(max(particleRatio, 0), 1),
            chipCount: tips.count
        )
    }

    private enum Phase { case bursting, breathing }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// True while the launch splash covers the screen. The burst waits for it
    /// to finish, then fades in and plays from the start.
    @Environment(\.caffySplashActive) private var splashActive

    @State private var startDate = Date.now
    @State private var phase = Phase.bursting
    @State private var isVisible = false
    /// Fades the whole burst in, and out and back for a calm replay.
    @State private var isRevealed = false
    @State private var centreScale = MemoryBurstStyle.centreStartScale
    @State private var centreOpacity = 0.0
    @State private var tapCount = 0

    private var filamentColor: Color {
        color ?? (colorScheme == .dark ? MemoryBurstStyle.darkFilament : MemoryBurstStyle.lightFilament)
    }

    var body: some View {
        GeometryReader { proxy in
            let printSide = min(proxy.size.width, proxy.size.height) * MemoryBurstStyle.printSide
            ZStack {
                field(printSide: printSide)
                centreStack(printSide: printSide)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .opacity(isRevealed ? 1 : 0)
        .contentShape(.rect)
        .onTapGesture {
            guard replaysOnTap else { return }
            tapCount += 1
            replay()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your photos and music, connected")
        .accessibilityAddTraits(.isImage)
        .accessibilityAction(named: "Replay animation") { replay() }
        .onAppear {
            isVisible = true
            // Behind the launch splash, wait until it hands over (see below).
            if !splashActive { start() }
        }
        .onChange(of: splashActive) { _, active in
            if !active { start(fadingIn: true) }
        }
        .onDisappear { isVisible = false }
        .onChange(of: replayTrigger) { replay() }
        .onChange(of: reduceMotion) { start() }
        // Switches to the slower breathing frame rate once every filament is out.
        .task(id: startDate) {
            guard !reduceMotion, phase == .bursting else { return }
            try? await Task.sleep(for: .seconds(layout.settleTime * duration))
            if !Task.isCancelled { phase = .breathing }
        }
    }

    // MARK: Filaments

    private func field(printSide: Double) -> some View {
        let isBreathing = phase == .breathing && breathes && !reduceMotion
        let isPaused = reduceMotion || !isVisible || splashActive || scenePhase != .active
            || (phase == .breathing && !breathes)
        let interval = phase == .bursting ? nil : MemoryBurstStyle.breathFrameInterval
        let inset = printSide * MemoryBurstStyle.coreExtent * MemoryBurstStyle.coreInset
        let color = filamentColor
        let settleTime = layout.settleTime * duration

        return TimelineView(.animation(minimumInterval: interval, paused: isPaused)) { timeline in
            // Reduce Motion always draws the settled frame.
            let elapsed = reduceMotion ? settleTime + 1 : timeline.date.timeIntervalSince(startDate)
            Canvas { context, size in
                let breath = isBreathing
                    ? min(max((elapsed - settleTime) / MemoryBurstStyle.breathRamp, 0), 1)
                    : 0
                draw(in: &context, size: size, elapsed: elapsed, breath: breath, inset: inset, color: color)
            } symbols: {
                ForEach(tipArtwork.indices, id: \.self) { index in
                    BurstArtworkView(artwork: tipArtwork[index])
                        .frame(width: MemoryBurstStyle.chipSize, height: MemoryBurstStyle.chipSize)
                        .clipShape(.rect(cornerRadius: MemoryBurstStyle.chipCorner))
                        .overlay {
                            RoundedRectangle(cornerRadius: MemoryBurstStyle.chipCorner)
                                .strokeBorder(MemoryBurstStyle.printBorder, lineWidth: MemoryBurstStyle.chipBorder)
                        }
                        .tag(index)
                }
            }
        }
    }

    /// Paints one frame. A line-for-line port of the original's `paint`.
    private func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        elapsed: Double,
        breath: Double,
        inset: Double,
        color: Color
    ) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxR = min(size.width, size.height) * radius
        let inner = min(maxR * 0.92, inset)
        let field = sin(elapsed * MemoryBurstStyle.fieldSpeed) * MemoryBurstStyle.fieldAmount * breath
        let lineStyle = StrokeStyle(lineCap: .round)
        var chips: [(symbol: Int, point: CGPoint, scale: Double, tilt: Double, opacity: Double)] = []

        for (index, tentacle) in layout.tentacles.enumerated() {
            let p = progress(of: tentacle, elapsed: elapsed)
            let wobble = sin(elapsed * MemoryBurstStyle.lineSpeed + tentacle.phase)
            let scale = 1 + field + wobble * MemoryBurstStyle.lineAmount * breath
            let span = (maxR - inner) * tentacle.length * scale
            let reach = inner + span * p
            guard reach > inner + 0.4 else { continue }

            let shimmer = 0.9 + 0.1 * sin(elapsed * MemoryBurstStyle.fieldSpeed + tentacle.phase * 0.35)
            let fade = 1 + (shimmer - 1) * breath
            let direction = CGPoint(x: cos(tentacle.angle), y: sin(tentacle.angle))
            func point(at r: Double) -> CGPoint {
                CGPoint(x: centre.x + direction.x * r, y: centre.y + direction.y * r)
            }

            var line = Path()
            line.move(to: point(at: inner))
            line.addLine(to: point(at: reach))
            var style = lineStyle
            style.lineWidth = tentacle.width
            context.stroke(line, with: .color(color.opacity(tentacle.alpha * (0.55 + p * 0.45) * fade)), style: style)

            for mid in tentacle.mids where p >= mid.t {
                let r = inner + span * mid.t
                context.fill(dot(at: point(at: r), radius: mid.size), with: .color(color.opacity(mid.alpha * fade)))
            }

            guard p > 0.92 else { continue }
            let appear = min(max((p - 0.92) / 0.08, 0), 1)

            if let symbol = layout.chips[index] {
                let pulse = 1 + MemoryBurstStyle.chipPulseAmount * wobble * breath
                chips.append((
                    symbol: symbol,
                    point: point(at: reach + MemoryBurstStyle.chipSize * 0.3),
                    scale: (0.6 + 0.4 * Self.easeOutBack(appear)) * pulse,
                    tilt: (tentacle.phase / .pi - 1) * MemoryBurstStyle.chipMaxTilt,
                    opacity: appear
                ))
            } else if tentacle.hasTip {
                let r = inner + span * (1 + tentacle.tipOvershoot)
                let pulse = 1 + MemoryBurstStyle.tipPulseAmount * wobble * breath
                context.fill(
                    dot(at: point(at: r), radius: tentacle.tipSize * pulse),
                    with: .color(color.opacity(0.78 * appear * fade))
                )
            }
        }

        // Chips go on top of every filament.
        for chip in chips {
            guard let symbol = context.resolveSymbol(id: chip.symbol) else { continue }
            var layer = context
            layer.opacity = chip.opacity
            layer.translateBy(x: chip.point.x, y: chip.point.y)
            layer.rotate(by: .degrees(chip.tilt))
            layer.scaleBy(x: chip.scale, y: chip.scale)
            layer.draw(symbol, at: .zero)
        }
    }

    private func progress(of tentacle: BurstLayout.Tentacle, elapsed: Double) -> Double {
        let t = (elapsed - tentacle.delay * duration) / (duration * tentacle.grow)
        return Self.easeOutQuart(t)
    }

    private func dot(at point: CGPoint, radius: Double) -> Path {
        Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }

    private static func easeOutQuart(_ t: Double) -> Double {
        let p = 1 - min(max(t, 0), 1)
        return 1 - p * p * p * p
    }

    private static func easeOutBack(_ t: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }

    // MARK: Centre stack

    private func centreStack(printSide side: Double) -> some View {
        ZStack {
            print(
                photo, icon: "photo",
                width: side * MemoryBurstStyle.photoAspect, height: side,
                corner: MemoryBurstStyle.photoCorner, border: MemoryBurstStyle.photoBorder,
                iconSize: side * MemoryBurstStyle.printIconScale
            )
            .rotationEffect(.degrees(MemoryBurstStyle.photoTilt))
            .offset(x: side * MemoryBurstStyle.photoOffset.width, y: side * MemoryBurstStyle.photoOffset.height)

            let cover = side * MemoryBurstStyle.coverScale
            print(
                artwork, icon: "music.note",
                width: cover, height: cover,
                corner: MemoryBurstStyle.coverCorner, border: MemoryBurstStyle.coverBorder,
                iconSize: side * MemoryBurstStyle.printIconScale
            )
            .rotationEffect(.degrees(MemoryBurstStyle.coverTilt))
            .offset(x: side * MemoryBurstStyle.coverOffset.width, y: side * MemoryBurstStyle.coverOffset.height)
        }
        .scaleEffect(centreScale)
        .opacity(centreOpacity)
    }

    private func print(
        _ artwork: BurstArtwork,
        icon: String,
        width: Double,
        height: Double,
        corner: Double,
        border: Double,
        iconSize: Double
    ) -> some View {
        BurstArtworkView(artwork: artwork, iconSymbol: icon, iconSize: iconSize)
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: corner))
            .overlay {
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(MemoryBurstStyle.printBorder, lineWidth: border)
            }
            // One static shadow per print, as on Home. Nothing else here blurs.
            .compositingGroup()
            .shadow(
                color: MemoryBurstStyle.printShadow,
                radius: MemoryBurstStyle.printShadowRadius,
                y: MemoryBurstStyle.printShadowY
            )
    }

    // MARK: Playback

    /// The first play, and a fresh start when Reduce Motion changes.
    /// `fadingIn` fades the burst in as it starts, for when it waited for the launch splash.
    private func start(fadingIn: Bool = false) {
        startDate = .now
        phase = .bursting
        if reduceMotion {
            centreScale = 1
            centreOpacity = 1
            withAnimation(MemoryBurstStyle.calmFade) { isRevealed = true }
        } else {
            if fadingIn {
                withAnimation(MemoryBurstStyle.afterSplashFade) { isRevealed = true }
            } else {
                isRevealed = true
            }
            withAnimation(MemoryBurstStyle.centreSpring) {
                centreScale = 1
                centreOpacity = 1
            }
        }
    }

    private func replay() {
        if reduceMotion {
            // No re-burst: a quick cross-fade back to the same still frame.
            withAnimation(MemoryBurstStyle.calmFadeOut) {
                isRevealed = false
            } completion: {
                withAnimation(MemoryBurstStyle.calmFade) { isRevealed = true }
            }
            return
        }
        startDate = .now
        phase = .bursting
        withAnimation(.snappy(duration: 0.12)) {
            centreScale = MemoryBurstStyle.centreTapScale
        } completion: {
            withAnimation(MemoryBurstStyle.centreSpring) { centreScale = 1 }
        }
    }
}

// MARK: - Layout

/// The filaments, generated once from a seed exactly as the original does,
/// so a seed gives the same burst on the web and here.
struct BurstLayout {
    nonisolated struct Tentacle {
        nonisolated struct Mid {
            let t: Double
            let size: Double
            let alpha: Double
        }

        let angle: Double
        let length: Double
        let width: Double
        let alpha: Double
        /// Start delay and growth time, both in multiples of the duration.
        let delay: Double
        let grow: Double
        let phase: Double
        let hasTip: Bool
        let tipSize: Double
        let tipOvershoot: Double
        let mids: [Mid]
    }

    let tentacles: [Tentacle]
    /// Which tentacles carry an artwork chip: tentacle index → artwork index.
    let chips: [Int: Int]
    /// When the last filament finishes growing, in multiples of the duration.
    let settleTime: Double

    init(count: Int, seed: Int, particleRatio: Double, chipCount: Int) {
        var random = Mulberry32(seed: seed)
        var tentacles: [Tentacle] = []
        tentacles.reserveCapacity(count)

        for i in 0..<count {
            let base = Double(i) / Double(count) * 2 * .pi
            let angle = base + (random.next() - 0.5) * (2 * .pi * 0.018)
            // A power curve: mostly mid-length, a few long outliers, some stubs.
            let roll = random.next()
            let length = roll < 0.12
                ? 0.22 + random.next() * 0.18
                : roll < 0.78 ? 0.48 + random.next() * 0.32 : 0.78 + random.next() * 0.22
            let hasTip = random.next() < particleRatio
            // The random numbers are drawn in the same order as the original,
            // including its short-circuits, so seeds match.
            let midCount: Int
            if random.next() < 0.22 {
                midCount = 2
            } else {
                midCount = random.next() < 0.48 ? 1 : 0
            }
            var mids: [Tentacle.Mid] = []
            for _ in 0..<midCount {
                let t = 0.28 + random.next() * 0.52
                let size = 0.55 + random.next() * 0.7
                let alpha = 0.28 + random.next() * 0.38
                mids.append(.init(t: t, size: size, alpha: alpha))
            }
            let width = 0.35 + random.next() * 0.85
            let alpha = 0.22 + random.next() * 0.55
            let delay = random.next() * 0.42 + Double(i) / Double(count) * 0.08
            let grow = 0.55 + random.next() * 0.7
            let phase = random.next() * 2 * .pi
            let tipSize = 0.85 + random.next() * 1.35
            var tipOvershoot = 0.0
            if hasTip, random.next() < 0.35 {
                tipOvershoot = 0.018 + random.next() * 0.05
            }

            tentacles.append(Tentacle(
                angle: angle,
                length: min(max(length, 0.16), 1),
                width: width,
                alpha: alpha,
                delay: delay,
                grow: grow,
                phase: phase,
                hasTip: hasTip,
                tipSize: tipSize,
                tipOvershoot: tipOvershoot,
                mids: mids
            ))
        }

        self.tentacles = tentacles
        settleTime = tentacles.map { $0.delay + $0.grow }.max() ?? 1
        chips = Self.chooseChips(from: tentacles, count: chipCount)
    }

    /// Picks mid-to-long tipped filaments spread evenly round the circle, so
    /// the artwork never bunches up or runs off the edge.
    private static func chooseChips(from tentacles: [Tentacle], count: Int) -> [Int: Int] {
        guard count > 0 else { return [:] }
        var candidates = tentacles.indices.filter {
            tentacles[$0].hasTip && MemoryBurstStyle.chipLengths.contains(tentacles[$0].length)
        }
        var chips: [Int: Int] = [:]
        for k in 0..<count {
            // Start just off the top, so no chip sits straight above the prints.
            let target = -Double.pi / 2 + (Double(k) + 0.5) / Double(count) * 2 * .pi
            let nearest = candidates.indices.min { a, b in
                angularDistance(tentacles[candidates[a]].angle, target)
                    < angularDistance(tentacles[candidates[b]].angle, target)
            }
            guard let nearest else { break }
            chips[candidates[nearest]] = k
            candidates.remove(at: nearest)
        }
        return chips
    }

    private static func angularDistance(_ a: Double, _ b: Double) -> Double {
        abs((a - b).remainder(dividingBy: 2 * .pi))
    }
}

/// The original's `mulberry32` seeded random generator, bit for bit.
nonisolated struct Mulberry32 {
    private var state: UInt32

    init(seed: Int) {
        state = UInt32(truncatingIfNeeded: seed)
    }

    /// A number in 0..<1.
    mutating func next() -> Double {
        state = state &+ 0x6D2B_79F5
        var t = (state ^ (state >> 15)) &* (state | 1)
        t = (t &+ ((t ^ (t >> 7)) &* (t | 61))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

// MARK: - Previews

#Preview("Light") {
    MemoryBurst()
        .frame(height: 440)
        .background(Theme.cream)
}

#Preview("Dark") {
    MemoryBurst()
        .frame(height: 440)
        .background(Theme.espresso)
        .preferredColorScheme(.dark)
}

#Preview("Sparse, custom colour") {
    MemoryBurst(tipArtwork: [], tentacleCount: 90, particleRatio: 0.4, color: Theme.rulerLine)
        .frame(height: 440)
        .background(Theme.cream)
}

#Preview("Dense, no breathing") {
    MemoryBurst(tentacleCount: 600, particleRatio: 0.85, breathes: false)
        .frame(height: 440)
        .background(Theme.cream)
}
