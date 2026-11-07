import Foundation

/// Lays eras out down the river as a timeline: 30 points to a month, with
/// long gaps between eras squeezed into a visible break.
///
/// This is plain geometry with no SwiftUI in it, so it stays easy to test.
nonisolated struct RiverLayout {
    /// A straight run of the ruler, where each month takes `monthHeight`.
    struct Segment {
        let from: Double
        let to: Double
        /// Where `baseMonth` falls, which can be above `from`.
        let originY: Double
        /// Months counted as `year * 12 + month - 1`.
        let baseMonth: Int
    }

    struct Tick {
        let y: Double
        /// `nil` draws a tick with no label.
        let label: String?
        let isQuarter: Bool
    }

    static let monthHeight = 30.0
    /// A print's date notch sits this far below the top of its row.
    static let notchOffset = 118.0
    /// Eras further apart than this get a break in the ruler.
    private static let breakAfterMonths = 40
    /// Eras always sit at least this far apart, so their prints don't overlap.
    private static let minimumSpacing = 330.0
    private static let breakSpacing = 344.0
    /// Formatter-backed names, because a bare `Calendar` has no locale and
    /// would give "M10" instead of "Oct".
    private static let monthNames = DateFormatter().shortMonthSymbols ?? []

    /// Each era's notch position, in the order the eras were given.
    private(set) var notches: [Double] = []
    private(set) var segments: [Segment] = []
    private(set) var breaks: [Double] = []
    private(set) var height = 0.0

    /// - Parameter eraDates: Each era's date, newest first.
    init(eraDates: [Date], now: Date, calendar: Calendar = .current) {
        func monthIndex(_ date: Date) -> Int {
            let parts = calendar.dateComponents([.year, .month], from: date)
            return (parts.year ?? 0) * 12 + (parts.month ?? 1) - 1
        }

        let topMonth = monthIndex(now)
        guard let newest = eraDates.first else {
            segments = [Segment(from: 0, to: 0, originY: 0, baseMonth: topMonth)]
            return
        }

        // Keep the newest print fully on the river, however recent it is.
        let newestMonth = monthIndex(newest)
        let natural = Double(topMonth - newestMonth) * Self.monthHeight
        let firstNotch = max(natural, Self.notchOffset + 14)
        var segmentFrom = 0.0
        var origin = firstNotch - natural
        var baseMonth = topMonth
        var previousMonth = newestMonth
        notches = [firstNotch]

        for date in eraDates.dropFirst() {
            let month = monthIndex(date)
            let previousNotch = notches[notches.count - 1]
            let gap = Double(previousMonth - month) * Self.monthHeight

            if previousMonth - month > Self.breakAfterMonths {
                let breakTop = previousNotch + 200
                segments.append(Segment(from: segmentFrom, to: breakTop, originY: origin, baseMonth: baseMonth))
                breaks.append(breakTop)
                let notch = previousNotch + Self.breakSpacing
                segmentFrom = breakTop + 60
                origin = notch
                baseMonth = month
                notches.append(notch)
            } else if gap < Self.minimumSpacing {
                // Too close to fit: restart the months from this era.
                let notch = previousNotch + Self.minimumSpacing
                segments.append(Segment(from: segmentFrom, to: notch - 1, originY: origin, baseMonth: baseMonth))
                segmentFrom = notch
                origin = notch
                baseMonth = month
                notches.append(notch)
            } else {
                notches.append(previousNotch + gap)
            }
            previousMonth = month
        }

        height = (notches.last ?? 0) + 156
        segments.append(Segment(from: segmentFrom, to: height, originY: origin, baseMonth: baseMonth))
    }

    /// The month ticks for the whole ruler. Ticks that would crowd a notch
    /// are left out.
    var ticks: [Tick] {
        var ticks: [Tick] = []
        for segment in segments {
            let first = Int(((segment.from - segment.originY) / Self.monthHeight).rounded(.up))
            let last = Int(((segment.to - segment.originY) / Self.monthHeight).rounded(.down))
            guard first <= last else { continue }

            for step in first...last {
                let y = segment.originY + Double(step) * Self.monthHeight
                let nearest = notches.map { abs($0 - y) }.min() ?? .infinity
                guard nearest >= 12 else { continue }

                let index = segment.baseMonth - step
                let month = ((index % 12) + 12) % 12
                let year = Int((Double(index) / 12).rounded(.down))
                let isQuarter = month.isMultiple(of: 3)
                var label: String?
                if isQuarter && nearest > 34 {
                    label = month == 0 ? "\(Self.monthNames[0])\n\(year)" : Self.monthNames[month]
                }
                ticks.append(Tick(y: y, label: label, isQuarter: isQuarter))
            }
        }
        return ticks
    }
}
