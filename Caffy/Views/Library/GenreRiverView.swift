import SwiftUI

/// The genre river and the month ruler running down its left edge.
struct GenreRiverView: View {
    let river: GenreRiver
    let layout: RiverLayout
    /// The date stamp beside each era's notch, such as "Apr\n2026".
    let stamps: [String]

    /// The river is drawn on a 390-point width, then stretched to fit.
    private static let designWidth = 390.0

    var body: some View {
        // `Canvas` draws everything in one pass, which suits a shape with
        // hundreds of points much better than a view for each part.
        Canvas { context, size in
            drawRuler(in: &context)
            drawBands(in: &context, size: size)
        }
        .frame(height: layout.height)
        .accessibilityElement()
        .accessibilityLabel("Genre river")
        .accessibilityValue(description)
    }

    private var description: String {
        river.bands.map(\.name).formatted(.list(type: .and))
    }

    private func drawBands(in context: inout GraphicsContext, size: CGSize) {
        let horizontalScale = size.width / Self.designWidth
        let sampleCount = 280
        var lefts = Array(repeating: [CGPoint](), count: river.bands.count)
        var rights = lefts

        for sample in 0...sampleCount {
            let t = Double(sample) / Double(sampleCount)
            for (band, edge) in river.edges(at: t).enumerated() {
                let y = t * layout.height
                lefts[band].append(CGPoint(x: edge.left * horizontalScale, y: y))
                rights[band].append(CGPoint(x: edge.right * horizontalScale, y: y))
            }
        }

        for (index, band) in river.bands.enumerated() {
            var path = Path()
            path.addLines(lefts[index] + rights[index].reversed())
            path.closeSubpath()
            context.fill(path, with: .color(band.fill))
        }

        for (index, band) in river.bands.enumerated() {
            let edge = river.edges(at: band.labelPosition)[index]
            let x = ((edge.left + edge.right) / 2 + band.labelOffset) * horizontalScale
            let label = Text(band.name)
                .font(Theme.mono(11, medium: true))
                .foregroundStyle(band.ink)
            context.draw(label, at: CGPoint(x: x, y: band.labelPosition * layout.height))
        }
    }

    private func drawRuler(in context: inout GraphicsContext) {
        var line = Path()
        var minor = Path()
        var major = Path()

        for tick in layout.ticks {
            if tick.isQuarter {
                major.move(to: CGPoint(x: 9, y: tick.y))
                major.addLine(to: CGPoint(x: 18, y: tick.y))
            } else {
                minor.move(to: CGPoint(x: 9, y: tick.y))
                minor.addLine(to: CGPoint(x: 14, y: tick.y))
            }
            if let label = tick.label {
                drawLabel(label, y: tick.y, size: 9, opacity: 0.7, in: &context)
            }
        }

        // The spine, with a chevron pointing at each era's date.
        var breaks = layout.breaks[...]
        line.move(to: CGPoint(x: 6, y: 0))
        for (notch, stamp) in zip(layout.notches, stamps) {
            if let breakTop = breaks.first, notch > breakTop {
                line.addLine(to: CGPoint(x: 6, y: breakTop))
                line.move(to: CGPoint(x: 6, y: breakTop + 60))
                minor.move(to: CGPoint(x: 2, y: breakTop + 24))
                minor.addLine(to: CGPoint(x: 10, y: breakTop + 18))
                minor.move(to: CGPoint(x: 2, y: breakTop + 36))
                minor.addLine(to: CGPoint(x: 10, y: breakTop + 30))
                breaks = breaks.dropFirst()
            }
            line.addLine(to: CGPoint(x: 6, y: notch - 14))
            line.addLine(to: CGPoint(x: 15, y: notch))
            line.addLine(to: CGPoint(x: 6, y: notch + 14))
            major.move(to: CGPoint(x: 15, y: notch))
            major.addLine(to: CGPoint(x: 21, y: notch))
            drawLabel(stamp, y: notch, size: 10, opacity: 1, medium: true, in: &context)
        }
        line.addLine(to: CGPoint(x: 6, y: layout.height))

        var rulerContext = context
        rulerContext.opacity = 0.5
        rulerContext.stroke(line, with: .color(Theme.rulerLine), lineWidth: 1.5)
        rulerContext.stroke(minor, with: .color(Theme.rulerLine), lineWidth: 1)
        rulerContext.stroke(major, with: .color(Theme.rulerLine), lineWidth: 1.75)
    }

    private func drawLabel(
        _ text: String,
        y: Double,
        size: CGFloat,
        opacity: Double,
        medium: Bool = false,
        in context: inout GraphicsContext
    ) {
        let label = Text(text)
            .font(Theme.mono(size, medium: medium))
            .foregroundStyle(Theme.softInk.opacity(opacity))
        context.draw(label, at: CGPoint(x: 23, y: y), anchor: .leading)
    }
}
