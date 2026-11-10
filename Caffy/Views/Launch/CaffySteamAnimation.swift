//
//  CaffySteamAnimation.swift
//  Caffy
//
//  A 2.4 second full-screen launch animation in a flat, warm illustration style.
//
//  0–2s  A small cup of coffee on a saucer sits at the bottom centre of the screen.
//        Steam strands rise out of it one per letter, swelling as they climb, and each
//        pours into its own letter of the bold "caffy" wordmark in the middle of the
//        screen. The cup then drops off the bottom of the screen.
//  2–2.4s The background fades away to reveal the screen underneath. Each letter melts
//        back into a steam strand, the strands flow to wherever that screen's Caffy
//        heading sits, and the letters re-form there at the heading's size, then hand
//        over to the real heading.
//
//  Everything is drawn in code (no image assets).
//
//  Usage: `CaffyApp` wraps its root view in `CaffyLaunchContainer`. Home marks its
//  "caffy" heading with `.caffyTitleTarget()` (the melt hand-over).
//
//  Onboarding's Welcome screen uses a simpler hand-over — the title just glides into
//  place, then the message rolls in word by word and the button glows in. See
//  `OnboardingLayout`, which uses:
//
//      Text(...).caffyTitleTarget(.glide)
//      CaffyWordRollText("…")
//      buttons.caffyGlowIn(delay: 0.75)
//
//  Whichever view carries .caffyTitleTarget() is where the title lands — top left,
//  top right, centred, anywhere. It stays hidden during the splash so the title
//  never appears twice. If no screen marks a target, the title simply fades out.
//
//  Font setup: Bricolage Grotesque ships in `Resources/Fonts` as a variable font
//  and is registered by `Theme.registerFonts()` (called from `CaffyApp.init`),
//  which must run before `letters` is first used.
//

import SwiftUI
import CoreText
import UIKit

// MARK: - Launch container

/// Shows `content` with the Caffy splash on top, and flies the title to the
/// view marked with `.caffyTitleTarget()` before handing over.
struct CaffyLaunchContainer<Content: View>: View {
    private let content: Content
    @State private var showSplash = true
    @State private var titleTarget: CGRect?
    @State private var transition: CaffyTitleTransition = .melt

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .environment(\.caffySplashActive, showSplash)
                .environment(\.caffyReportTitleFrame, { frame, style in
                    titleTarget = frame
                    transition = style
                })

            if showSplash {
                CaffySteamAnimation(target: titleTarget, transition: transition) {
                    // Short cross-fade so the hand-over to the real heading is seamless.
                    withAnimation(.easeOut(duration: 0.15)) { showSplash = false }
                }
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Title target

/// How the splash title travels to the screen's heading.
enum CaffyTitleTransition {
    /// Letters melt into faint steam strands that flow to the heading and re-form (Home).
    case melt
    /// The whole title simply glides and resizes into place (Onboarding).
    case glide
}

private struct CaffySplashActiveKey: EnvironmentKey {
    static let defaultValue = false
}

private struct CaffyReportTitleFrameKey: EnvironmentKey {
    static let defaultValue: (CGRect, CaffyTitleTransition) -> Void = { _, _ in }
}

extension EnvironmentValues {
    var caffySplashActive: Bool {
        get { self[CaffySplashActiveKey.self] }
        set { self[CaffySplashActiveKey.self] = newValue }
    }
    var caffyReportTitleFrame: (CGRect, CaffyTitleTransition) -> Void {
        get { self[CaffyReportTitleFrameKey.self] }
        set { self[CaffyReportTitleFrameKey.self] = newValue }
    }
}

extension View {
    /// Marks this view as the place the splash title flies to. Put it directly on
    /// the heading Text (before any .frame or .padding) so its frame is the text itself.
    /// `transition` picks how it gets there: `.melt` (Home) or `.glide` (Onboarding).
    func caffyTitleTarget(_ transition: CaffyTitleTransition = .melt) -> some View {
        modifier(CaffyTitleTargetModifier(transition: transition))
    }
}

private struct CaffyTitleTargetModifier: ViewModifier {
    let transition: CaffyTitleTransition
    @Environment(\.caffySplashActive) private var splashActive
    @Environment(\.caffyReportTitleFrame) private var report

    func body(content: Content) -> some View {
        content
            .opacity(splashActive ? 0 : 1)
            .background(
                GeometryReader { geometry in
                    let frame = geometry.frame(in: .global)
                    Color.clear.task(id: frame) { report(frame, transition) }
                }
            )
    }
}

/// The Caffy wordmark as a regular SwiftUI view, built from the exact same font,
/// size, spacing and colour as the splash, already marked as the title target.
struct CaffyTitle: View {
    /// `.melt` for Home, `.glide` for Onboarding.
    var transition: CaffyTitleTransition = .melt

    var body: some View {
        Text(CaffySteamRenderer.titleText)
            .font(Font(CaffySteamRenderer.titleFont))
            .kerning(CaffySteamRenderer.titleTracking)
            .foregroundStyle(CaffySteamRenderer.titleInk)
            .caffyTitleTarget(transition)
    }
}

// MARK: - Onboarding entrance helpers

/// Text that rolls in word by word once the splash has handed over
/// (or straight away if there's no splash on screen). Style it like normal Text:
///
///     CaffyWordRollText("Turn your photos and places into playlists.")
///         .font(.title3)
///         .foregroundStyle(.secondary)
struct CaffyWordRollText: View {
    let text: String
    var alignment: HorizontalAlignment = .center
    var startDelay: Double = 0.05     // after the splash hands over
    var wordDelay: Double = 0.07      // between words

    @Environment(\.caffySplashActive) private var splashActive
    @State private var shown = false

    init(_ text: String, alignment: HorizontalAlignment = .center,
         startDelay: Double = 0.05, wordDelay: Double = 0.07) {
        self.text = text
        self.alignment = alignment
        self.startDelay = startDelay
        self.wordDelay = wordDelay
    }

    var body: some View {
        let words = text.split(separator: " ").map(String.init)
        CaffyFlowLayout(alignment: alignment, spacing: 5, lineSpacing: 4) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 14)
                    .blur(radius: shown ? 0 : 3)
                    .animation(.spring(response: 0.45, dampingFraction: 0.82)
                                .delay(startDelay + Double(index) * wordDelay),
                               value: shown)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .task(id: splashActive) {
            if !splashActive { shown = true }
        }
    }

    /// How long the whole line takes to roll in — handy for timing what comes after it.
    var totalDuration: Double {
        startDelay + Double(max(text.split(separator: " ").count - 1, 0)) * wordDelay + 0.45
    }
}

/// Wraps words onto lines, like a paragraph, so each word can animate on its own.
struct CaffyFlowLayout: Layout {
    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = makeRows(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in makeRows(maxWidth: bounds.width, subviews: subviews) {
            var x: CGFloat
            switch alignment {
            case .leading:  x = bounds.minX
            case .trailing: x = bounds.maxX - row.width
            default:        x = bounds.minX + (bounds.width - row.width) / 2
            }
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func makeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

extension View {
    /// Fades the view in, then gives it a warm glow that blooms and settles, once the
    /// splash has handed over (or straight away if there's no splash on screen).
    /// Use `delay` to wait for the text above to finish rolling in, and `glowDelay`
    /// for how long after the fade starts the glow begins.
    func caffyGlowIn(delay: Double = 0.6,
                     glowDelay: Double = 0.5,
                     color: Color = Color(red: 0.86, green: 0.60, blue: 0.36)) -> some View {
        modifier(CaffyGlowInModifier(delay: delay, glowDelay: glowDelay, color: color))
    }
}

private struct CaffyGlowInModifier: ViewModifier {
    let delay: Double
    let glowDelay: Double
    let color: Color

    @Environment(\.caffySplashActive) private var splashActive
    @State private var shown = false      // 1. faded in, no glow yet
    @State private var glowing = false    // 2. glow blooms
    @State private var settled = false    // 3. glow settles to a soft halo

    private var glowOpacity: Double {
        guard glowing else { return 0 }
        return settled ? 0.28 : 0.8
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.94)
            .brightness(glowing && !settled ? 0.08 : 0)
            .shadow(color: color.opacity(glowOpacity), radius: glowing && !settled ? 24 : 10)
            .task(id: splashActive) {
                guard !splashActive, !shown else { return }
                try? await Task.sleep(for: .seconds(delay))
                withAnimation(.easeOut(duration: 0.45)) { shown = true }
                try? await Task.sleep(for: .seconds(glowDelay))
                withAnimation(.easeOut(duration: 0.4)) { glowing = true }
                try? await Task.sleep(for: .seconds(0.4))
                withAnimation(.easeInOut(duration: 0.7)) { settled = true }
            }
    }
}

// MARK: - Splash view

struct CaffySteamAnimation: View {
    /// Where the title should end up, in global (screen) coordinates. nil = fade out.
    var target: CGRect? = nil
    var transition: CaffyTitleTransition = .melt
    var introDuration: Double = 2.0   // cup, steam and title fill
    var moveDuration: Double = 0.4    // title glides to its place on the screen
    var onFinished: (() -> Void)? = nil

    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start)
            Canvas { ctx, size in
                CaffySteamRenderer.draw(in: &ctx,
                                        size: size,
                                        progress: min(max(elapsed / introDuration, 0), 1),
                                        move: min(max((elapsed - introDuration) / moveDuration, 0), 1),
                                        target: target,
                                        transition: transition,
                                        seconds: elapsed)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // fills the whole screen
        .ignoresSafeArea()
        .contentShape(Rectangle())                         // blocks taps during the splash
        .onAppear { start = .now }
        .task {
            try? await Task.sleep(for: .seconds(introDuration + moveDuration))
            onFinished?()
        }
        .accessibilityLabel("Caffy")
    }
}

// MARK: - Renderer

enum CaffySteamRenderer {

    // Palette (flat, warm browns)
    static let background  = Color(red: 0.85, green: 0.75, blue: 0.65)   // latte tan
    static let cupDark     = Color(red: 0.29, green: 0.17, blue: 0.12)
    static let cupMid      = Color(red: 0.43, green: 0.26, blue: 0.17)
    static let rimCream    = Color(red: 0.95, green: 0.87, blue: 0.76)
    static let coffeeTop   = Color(red: 0.47, green: 0.29, blue: 0.18)
    static let crema       = Color(red: 0.36, green: 0.21, blue: 0.13)
    static let saucerEdge  = Color(red: 0.80, green: 0.65, blue: 0.49)
    static let saucerInner = Color(red: 0.84, green: 0.70, blue: 0.54)
    static let shadow      = Color(red: 0.74, green: 0.60, blue: 0.47)
    static let steamOuter  = Color(red: 0.47, green: 0.28, blue: 0.17)
    static let steamInner  = Color(red: 0.63, green: 0.40, blue: 0.25)
    static let titleInk    = Color(red: 46 / 255, green: 28 / 255, blue: 18 / 255)   // #2E1C12

    // Layout. Artwork is designed for a 320pt-wide screen and scaled to the real width.
    static let designWidth: CGFloat = 320
    static let maxScale: CGFloat = 1.6                   // stops it getting huge on iPad
    static let cupSize: CGFloat = 0.4                    // cup scale (smaller = smaller cup)
    static let cupBottomInset: CGFloat = 80              // cup centre, measured up from the bottom edge

    // One strand per letter. Each entry: root x (relative to cup centre), resting height,
    // width at rest. Cycled if the title has more letters than entries.
    static let strandStyles: [(x: CGFloat, height: CGFloat, width: CGFloat)] = [
        (-12, 92, 15),
        ( 18, 64, 11),
        ( -2, 80, 13),
        ( 22, 58, 10),
        (-16, 72, 12),
    ]
    static let steamRootY: CGFloat = -44                 // just above the coffee surface
    static let strandArrivalWidth: CGFloat = 11          // strand width on arrival, in points (≈ letter stem at 56pt)

    // Timing, as fractions of the total duration. Letter i's strand leaves after letter i-1's.
    static let stagger = 0.075
    static func emergeWindow(_ i: Int) -> (Double, Double) { (-0.06 + stagger * Double(i), 0.02 + stagger * Double(i)) }
    static func riseWindow(_ i: Int) -> (Double, Double)   { (0.02 + stagger * Double(i), 0.44 + stagger * Double(i)) }
    static func fadeWindow(_ i: Int) -> (Double, Double)   { (0.40 + stagger * Double(i), 0.54 + stagger * Double(i)) }
    static func pourWindow(_ i: Int) -> (Double, Double)   { (0.36 + stagger * Double(i), 0.56 + stagger * Double(i)) }
    static func settleWindow(_ i: Int) -> (Double, Double) { (0.54 + stagger * Double(i), 0.66 + stagger * Double(i)) }
    static let cupExitWindow = (0.62, 0.95)   // cup drops down off the bottom of the screen

    // Title spec (matches "Heading 1" in the Caffy design):
    // Bricolage Grotesque, Extra Bold, 56pt, letter spacing -0.04em, #2E1C12.
    // The title is drawn at its real point size so it matches the in-app heading.
    static let titleFontSize: CGFloat = 56
    static let titleTracking: CGFloat = -0.04 * titleFontSize
    static let titleFont: CTFont = loadTitleFont(size: titleFontSize)

    /// Finds Bricolage Grotesque Extra Bold in the app bundle. Works with either the
    /// static ExtraBold .ttf or the variable font (weight axis set to 800). Falls back
    /// to the heavy system font if Bricolage hasn't been added to the project yet.
    static func loadTitleFont(size: CGFloat) -> CTFont {
        // 1. Static Extra Bold file (Google Fonts ships several optical-size cuts)
        let staticNames = ["BricolageGrotesque-ExtraBold",
                           "BricolageGrotesque48pt-ExtraBold",
                           "BricolageGrotesque96pt-ExtraBold",
                           "BricolageGrotesque36pt-ExtraBold",
                           "BricolageGrotesque24pt-ExtraBold"]
        for name in staticNames {
            let font = CTFontCreateWithName(name as CFString, size, nil)
            if (CTFontCopyPostScriptName(font) as String) == name { return font }
        }

        // 2. Variable font: pick the family and set the weight axis ('wght') to 800
        let wghtAxis = NSNumber(value: 0x77676874)
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute as String: "Bricolage Grotesque",
            kCTFontVariationAttribute as String: [wghtAxis: 800],
        ] as CFDictionary)
        let variable = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        if (CTFontCopyFamilyName(variable) as String).contains("Bricolage") { return variable }

        // 3. Fallback
        #if DEBUG
        print("⚠️ Bricolage Grotesque not found in the app bundle — using the system font.")
        #endif
        return UIFont.systemFont(ofSize: size, weight: .heavy) as CTFont
    }

    static let titleText = "caffy"
    static let letters: [Path] = makeGlyphPaths(titleText, font: titleFont, tracking: titleTracking)
    static let title: Path = letters.reduce(into: Path()) { $0.addPath($1) }

    // Line metrics, used to line the title up exactly with a SwiftUI Text's frame.
    static let titleAscent = CTFontGetAscent(titleFont)
    static let titleLineHeight = CTFontGetAscent(titleFont) + CTFontGetDescent(titleFont) + CTFontGetLeading(titleFont)

    // MARK: Frame

    static func draw(in ctx: inout GraphicsContext, size: CGSize, progress t: Double,
                     move: Double, target: CGRect?, transition: CaffyTitleTransition = .melt,
                     seconds: Double) {
        // Seconds 2–2.4: the background fades away to reveal the screen underneath.
        let m = ease(move)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background.opacity(1 - m)))

        let k = min(size.width / designWidth, maxScale)   // overall artwork scale
        let ck = k * cupSize                              // cup scale

        // Cup: starts at bottom centre, then accelerates down and off screen.
        let cupRestY = size.height - cupBottomInset * k
        let exit = easeIn(phase(t, cupExitWindow))
        let cup = CGPoint(x: size.width / 2,
                          y: cupRestY + exit * (size.height - cupRestY + 100 * ck))

        // Title: ends up dead centre of the screen.
        let tb = title.boundingRect
        let titleCenter = CGPoint(x: size.width / 2, y: size.height / 2)
        let titleOrigin = CGPoint(x: titleCenter.x - tb.midX, y: titleCenter.y - tb.midY)

        if cup.y - 80 * ck < size.height {
            drawCup(ctx, center: cup, scale: ck)
        }

        // Seconds 2–2.4: each letter melts back into a steam strand, the strand
        // flows up to that letter's place in the target heading, and the letter
        // re-forms there at the heading's size. With no target, the title fades out.
        if m > 0, let target, target.height > 0, transition == .glide {
            // Onboarding: the finished title simply glides and resizes into place.
            let s = target.height / titleLineHeight
            let end = CGPoint(x: target.minX, y: target.minY + titleAscent * s)
            let origin = CGPoint(x: titleOrigin.x + (end.x - titleOrigin.x) * m,
                                 y: titleOrigin.y + (end.y - titleOrigin.y) * m)
            for i in letters.indices {
                drawLetter(ctx, index: i, origin: origin, scale: 1 + (s - 1) * m,
                           progress: t, seconds: seconds)
            }
        } else if m > 0, let target, target.height > 0 {
            let s = target.height / titleLineHeight
            let endOrigin = CGPoint(x: target.minX, y: target.minY + titleAscent * s)
            for i in letters.indices {
                drawLetterTransfer(ctx, index: i, from: titleOrigin, to: endOrigin, toScale: s,
                                   move: move, seconds: seconds)
            }
        } else {
            var titleCtx = ctx
            titleCtx.opacity = 1 - m
            // Letters fill first so the arriving strands sit on top of them.
            for i in letters.indices {
                drawLetter(titleCtx, index: i, origin: titleOrigin, scale: 1, progress: t, seconds: seconds)
            }
        }

        // One strand per letter: grows out of the coffee, rises and swells,
        // then its tail draws up into the letter as the letter fills.
        let rootY = cupRestY + steamRootY * ck
        for i in letters.indices {
            let style = strandStyles[i % strandStyles.count]
            let grow = ease(phase(t, emergeWindow(i)))
            let p = ease(phase(t, riseWindow(i)))
            let fade = 1 - phase(t, fadeWindow(i))
            guard grow > 0, fade > 0 else { continue }

            let lb = letters[i].boundingRect
            let rootX = cup.x + style.x * ck
            let landing = CGPoint(x: titleOrigin.x + lb.midX, y: titleOrigin.y + lb.midY)
            let baseY = rootY + (landing.y + 12 - rootY) * p
            let length = style.height * ck * grow + 60 * k * sin(.pi * p) + 10 * p
            let width = style.width * ck * (1 - p) + strandArrivalWidth * p
            let tail = min(0.92, max(0, (p - 0.62) / 0.38))
            let amplitude = 7 * ck * (1 - 0.6 * p)
            let wave = seconds * 2.4 + Double(i) * 2.1
            let drift = (landing.x - rootX) * p

            let shape = steamShape(rootX: rootX, baseY: baseY, length: length, width: width,
                                   drift: drift, from: tail, wave: wave, amplitude: amplitude)
            let highlight = steamShape(rootX: rootX - width * 0.12, baseY: baseY, length: length * 0.92,
                                       width: width * 0.42, drift: drift, from: tail,
                                       wave: wave, amplitude: amplitude)
            ctx.fill(shape, with: .color(steamOuter.opacity(fade)))
            ctx.fill(highlight, with: .color(steamInner.opacity(0.9 * fade)))
        }
    }

    // MARK: Steam

    /// A tapered, flame-like steam strand rising from (rootX, baseY).
    /// `from` trims the bottom (0…1); `drift` slides it sideways, more at the top.
    static func steamShape(rootX: CGFloat, baseY: CGFloat, length: CGFloat, width: CGFloat,
                           drift: CGFloat, from s0: Double, wave: Double, amplitude: CGFloat) -> Path {
        guard length > 0.5, width > 0.1 else { return Path() }
        let n = 40
        var centre: [CGPoint] = []
        var half: [CGFloat] = []
        for j in 0...n {
            let s = s0 + (1 - s0) * Double(j) / Double(n)
            let y = baseY - length * s
            let x = rootX + drift * (0.35 + 0.65 * s) + amplitude * s * sin(s * 6.5 + wave)
            // Fat in the lower middle, pointed at the top; a trimmed tail tapers smoothly.
            var w = width * pow(sin(.pi * s), 0.85) * (1.2 - 0.6 * s)
            if s0 > 0 { w *= min(1, (s - s0) / 0.18) }
            centre.append(CGPoint(x: x, y: y))
            half.append(max(w / 2, 0))
        }
        return Path { p in
            p.move(to: CGPoint(x: centre[0].x - half[0], y: centre[0].y))
            for j in 1...n { p.addLine(to: CGPoint(x: centre[j].x - half[j], y: centre[j].y)) }
            for j in stride(from: n, through: 0, by: -1) {
                p.addLine(to: CGPoint(x: centre[j].x + half[j], y: centre[j].y))
            }
            p.closeSubpath()
        }
    }

    // MARK: Cup

    static func drawCup(_ ctx: GraphicsContext, center: CGPoint, scale: CGFloat) {
        var c = ctx
        c.translateBy(x: center.x, y: center.y)
        c.scaleBy(x: scale, y: scale)

        // Shadow, off to the right
        c.fill(Path(ellipseIn: CGRect(x: -40, y: 50, width: 170, height: 24)), with: .color(shadow))

        // Saucer: darker underside for thickness, cream top, tan well
        c.fill(Path(ellipseIn: CGRect(x: -80, y: 42, width: 160, height: 30)), with: .color(saucerEdge))
        c.fill(Path(ellipseIn: CGRect(x: -80, y: 36, width: 160, height: 30)), with: .color(rimCream))
        c.fill(Path(ellipseIn: CGRect(x: -58, y: 41, width: 116, height: 19)), with: .color(saucerInner))

        // Handle (drawn first so the body covers its ends)
        let handle = Path { p in
            p.move(to: CGPoint(x: 54, y: -18))
            p.addCurve(to: CGPoint(x: 91, y: -5),
                       control1: CGPoint(x: 72, y: -36), control2: CGPoint(x: 93, y: -26))
            p.addCurve(to: CGPoint(x: 48, y: 30),
                       control1: CGPoint(x: 89, y: 16), control2: CGPoint(x: 70, y: 28))
        }
        c.stroke(handle, with: .color(cupDark), style: StrokeStyle(lineWidth: 13, lineCap: .round))

        // Body
        let body = Path { p in
            p.move(to: CGPoint(x: -62, y: -30))
            p.addCurve(to: CGPoint(x: -26, y: 50),
                       control1: CGPoint(x: -62, y: 24), control2: CGPoint(x: -46, y: 48))
            p.addLine(to: CGPoint(x: 26, y: 50))
            p.addCurve(to: CGPoint(x: 62, y: -30),
                       control1: CGPoint(x: 46, y: 48), control2: CGPoint(x: 62, y: 24))
            p.closeSubpath()
        }
        c.fill(body, with: .color(cupDark))

        // Lighter brown wave across the left of the body
        var bc = c
        bc.clip(to: body)
        let wave = Path { p in
            p.move(to: CGPoint(x: -70, y: -40))
            p.addLine(to: CGPoint(x: 10, y: -40))
            p.addCurve(to: CGPoint(x: 0, y: 14),
                       control1: CGPoint(x: 32, y: -12), control2: CGPoint(x: -22, y: 0))
            p.addCurve(to: CGPoint(x: 30, y: 60),
                       control1: CGPoint(x: 16, y: 26), control2: CGPoint(x: 32, y: 44))
            p.addLine(to: CGPoint(x: -70, y: 60))
            p.closeSubpath()
        }
        bc.fill(wave, with: .color(cupMid))

        // Rim and coffee surface with a darker crema ridge
        c.fill(Path(ellipseIn: CGRect(x: -62, y: -42, width: 124, height: 24)), with: .color(rimCream))
        let surface = Path(ellipseIn: CGRect(x: -55, y: -39, width: 110, height: 18))
        c.fill(surface, with: .color(coffeeTop))
        var sc = c
        sc.clip(to: surface)
        let ridge = Path { p in
            p.move(to: CGPoint(x: -56, y: -29))
            p.addLine(to: CGPoint(x: -32, y: -32))
            p.addLine(to: CGPoint(x: -16, y: -36))
            p.addLine(to: CGPoint(x: -2, y: -33))
            p.addLine(to: CGPoint(x: 14, y: -37))
            p.addLine(to: CGPoint(x: 32, y: -32))
            p.addLine(to: CGPoint(x: 56, y: -30))
            p.addLine(to: CGPoint(x: 56, y: -18))
            p.addLine(to: CGPoint(x: -56, y: -18))
            p.closeSubpath()
        }
        sc.fill(ridge, with: .color(crema))
    }

    // MARK: Title

    // Within the move, letter i starts a little after letter i-1.
    static let transferStagger = 0.05
    // While travelling, strands fade to a faint light grey so they don't pull focus.
    static let transferStrandColor = Color(white: 0.85)
    static let transferStrandOpacity = 0.22

    /// Letter i shrinks back into a steam strand at its centred position, the strand
    /// flows to the letter's spot in the target heading, and the letter re-forms there.
    static func drawLetterTransfer(_ ctx: GraphicsContext, index i: Int,
                                   from startOrigin: CGPoint, to endOrigin: CGPoint, toScale s: CGFloat,
                                   move: Double, seconds: Double) {
        let lastStart = transferStagger * Double(letters.count - 1)
        let u = phase(move, (transferStagger * Double(i), 1 - lastStart + transferStagger * Double(i)))

        let lb = letters[i].boundingRect
        let from = CGPoint(x: startOrigin.x + lb.midX, y: startOrigin.y + lb.midY)
        let to = CGPoint(x: endOrigin.x + lb.midX * s, y: endOrigin.y + lb.midY * s)

        // 1. Letter drains away into the strand at its old position.
        let unfill = 1 - easeOut(phase(u, (0, 0.45)))
        drawLetterFill(ctx, index: i, origin: startOrigin, scale: 1,
                       fill: unfill, settle: 1 - phase(u, (0, 0.25)), seconds: seconds)

        // 2. Letter pours back in at the target, settling to the title ink.
        drawLetterFill(ctx, index: i, origin: endOrigin, scale: s,
                       fill: easeOut(phase(u, (0.55, 1))), settle: phase(u, (0.75, 1)), seconds: seconds)

        // 3. The strand between them: head leads from the old letter to the new one,
        //    tail follows, so it stretches out mid-flight and is gone at both ends.
        let headP = ease(phase(u, (0.05, 0.65)))
        let tailP = ease(phase(u, (0.35, 0.95)))
        guard headP > tailP else { return }
        let head = CGPoint(x: from.x + (to.x - from.x) * headP, y: from.y + (to.y - from.y) * headP)
        let tail = CGPoint(x: from.x + (to.x - from.x) * tailP, y: from.y + (to.y - from.y) * tailP)
        let width = strandArrivalWidth * (1 + (s - 1) * u)
        let wave = seconds * 2.4 + Double(i) * 2.1

        // steamShape draws upwards; flip it vertically when the heading is below the title.
        let up = head.y <= tail.y
        var sc = ctx
        if !up {
            sc.translateBy(x: 0, y: tail.y * 2)
            sc.scaleBy(x: 1, y: -1)
        }
        let length = max(abs(tail.y - head.y), 1)
        // steamShape offsets its bottom by 35% of the drift, so solve for a drift and
        // root that put the bottom exactly on the tail and the top on the head.
        let drift = (head.x - tail.x) / 0.65
        let rootX = tail.x - 0.35 * drift
        let shape = steamShape(rootX: rootX, baseY: tail.y, length: length, width: width,
                               drift: drift, from: 0, wave: wave, amplitude: 3)
        let highlight = steamShape(rootX: rootX - width * 0.12, baseY: tail.y, length: length * 0.92,
                                   width: width * 0.42, drift: drift, from: 0,
                                   wave: wave, amplitude: 3)
        // Brown as it leaves the letter, quickly turning faint light grey for the journey.
        let grey = easeOut(phase(u, (0.05, 0.3)))
        let alpha = 1 - (1 - transferStrandOpacity) * grey
        sc.fill(shape, with: .color(steamOuter.opacity(alpha * (1 - grey))))
        sc.fill(shape, with: .color(transferStrandColor.opacity(alpha * grey)))
        if grey < 1 {
            sc.fill(highlight, with: .color(steamInner.opacity(0.9 * alpha * (1 - grey))))
        }
    }

    /// Letter i fills outward from where its strand lands (a wobbly, growing blob
    /// clipped to the letter), starting steam brown and settling to the title ink.
    static func drawLetter(_ ctx: GraphicsContext, index i: Int, origin: CGPoint, scale: CGFloat,
                           progress t: Double, seconds: Double) {
        drawLetterFill(ctx, index: i, origin: origin, scale: scale,
                       fill: easeOut(phase(t, pourWindow(i))),
                       settle: phase(t, settleWindow(i)),
                       seconds: seconds)
    }

    /// Draws letter i filled by a wobbly blob of radius `fill` (0…1 of the letter),
    /// coloured steam brown blending to the title ink by `settle` (0…1).
    static func drawLetterFill(_ ctx: GraphicsContext, index i: Int, origin: CGPoint, scale: CGFloat,
                               fill f: Double, settle: Double, seconds: Double) {
        guard f > 0 else { return }

        var c = ctx
        c.translateBy(x: origin.x, y: origin.y)
        c.scaleBy(x: scale, y: scale)

        let letter = letters[i]
        let lb = letter.boundingRect
        let centre = CGPoint(x: lb.midX, y: lb.midY + lb.height * 0.15)   // strands arrive from below
        let r = hypot(lb.width, lb.height) * 0.8 * f
        let wobble = 0.15 * (1 - f)
        let blob = Path { p in
            let n = 60
            for j in 0...n {
                let a = Double(j) / Double(n) * 2 * .pi
                let rr = r * (1 + wobble * sin(4 * a + seconds * 6 + Double(i)))
                let pt = CGPoint(x: centre.x + rr * cos(a), y: centre.y + rr * sin(a))
                if j == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }

        var fc = c
        fc.clip(to: blob)
        fc.fill(letter, with: .color(steamOuter))
        if settle > 0 {
            fc.fill(letter, with: .color(titleInk.opacity(settle)))
        }
    }

    /// Converts a string into one vector Path per glyph using Core Text (baseline at y = 0).
    /// Ligatures are turned off so "ff" stays two separate letters, each with its own strand.
    static func makeGlyphPaths(_ string: String, font: CTFont, tracking: CGFloat = 0) -> [Path] {
        let attributed = NSAttributedString(
            string: string,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                         NSAttributedString.Key(kCTKernAttributeName as String): tracking,
                         NSAttributedString.Key(kCTLigatureAttributeName as String): 0])
        let line = CTLineCreateWithAttributedString(attributed)
        var result: [Path] = []

        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for i in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(font, glyphs[i], nil) else { continue }
                // Core Text is y-up; SwiftUI is y-down, so flip each glyph.
                var transform = CGAffineTransform(translationX: positions[i].x, y: positions[i].y)
                    .scaledBy(x: 1, y: -1)
                if let placed = glyph.copy(using: &transform) {
                    result.append(Path(placed))
                }
            }
        }
        return result
    }

    // MARK: Helpers

    static func phase(_ t: Double, _ window: (Double, Double)) -> Double {
        min(max((t - window.0) / (window.1 - window.0), 0), 1)
    }

    static func ease(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    /// Starts slow, speeds up — for the cup falling away.
    static func easeIn(_ x: Double) -> Double { x * x * x }

    /// Starts fast, settles gently — for the pour.
    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
}

// MARK: - Preview

// Previews don't run `CaffyApp.init`, so each one loads the bundled fonts first.

#Preview("Splash → Home") {
    let _ = Theme.registerFonts()
    CaffyLaunchContainer {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    CaffyTitle()          // top right, as an example target
                }
                Text("Home").font(.title2.bold())
                Spacer()
            }
            .padding()
        }
    }
}

#Preview("Splash → Onboarding") {
    let _ = Theme.registerFonts()
    CaffyLaunchContainer {
        VStack(spacing: 20) {
            Spacer()
            CaffyTitle(transition: .glide)
            CaffyWordRollText("Your photos and places, turned into playlists that grow with you.")
                .font(.title3)
                .foregroundStyle(CaffySteamRenderer.cupMid)
                .padding(.horizontal, 32)
            Spacer()
            Button {
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(CaffySteamRenderer.rimCream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(CaffySteamRenderer.titleInk, in: Capsule())
            }
            .padding(.horizontal, 32)
            .caffyGlowIn(delay: 0.75)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(CaffySteamRenderer.background.opacity(0.35))
    }
}

#Preview("Splash only") {
    let _ = Theme.registerFonts()
    CaffySteamAnimation()
}
