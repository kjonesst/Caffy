import SwiftUI

/// How the user's listening has split between genres over time.
///
/// The widths are hand-written sample data. Apple's listening history is too
/// short to compute this yet, so its real source is still an open question.
nonisolated struct GenreRiver {
    /// One genre's stream through the river.
    struct Band {
        let name: String
        let fill: Color
        let ink: Color
        /// The band's width at each of the river's `stops`, in points on a
        /// 390-point-wide screen.
        let widths: [Double]
        /// How far down the river the name sits, from 0 to 1.
        let labelPosition: Double
        /// Nudges the name sideways, for bands that bulge unevenly.
        var labelOffset: Double = 0
    }

    /// Positions down the river, from 0 (now) to 1 (the earliest era).
    let stops: [Double]
    let bands: [Band]

    static let sample = GenreRiver(
        stops: [0, 0.13, 0.4, 0.66, 0.9, 1],
        bands: [
            Band(name: "Classic rock", fill: Color(hex: 0x1E2A47), ink: .white,
                 widths: [10, 10, 14, 26, 112, 26], labelPosition: 0.9, labelOffset: 21),
            Band(name: "Chillout", fill: Color(hex: 0x3F6B46), ink: .white,
                 widths: [26, 28, 104, 38, 8, 2], labelPosition: 0.5),
            Band(name: "Trance", fill: Color(hex: 0x2B66C8), ink: .white,
                 widths: [92, 124, 34, 72, 5, 1], labelPosition: 0.13),
            Band(name: "Progressive", fill: Color(hex: 0xB23A26), ink: .white,
                 widths: [56, 70, 34, 104, 7, 1], labelPosition: 0.54),
            Band(name: "Drum & bass", fill: Color(hex: 0xEDC94A), ink: Color(hex: 0x2E1C12),
                 widths: [22, 30, 72, 10, 0, 0], labelPosition: 0.4)
        ]
    )

    /// A band's width at position `t`, easing smoothly between stops.
    private func width(of band: Band, at t: Double) -> Double {
        var index = 0
        while index < stops.count - 2 && t > stops[index + 1] {
            index += 1
        }
        let progress = (t - stops[index]) / (stops[index + 1] - stops[index])
        let eased = (1 - cos(.pi * progress)) / 2
        return band.widths[index] + (band.widths[index + 1] - band.widths[index]) * eased
    }

    /// The left and right edge of every band at position `t`, on a 390-point
    /// width. The whole river sways gently around the middle of the screen.
    func edges(at t: Double) -> [(left: Double, right: Double)] {
        let widths = bands.map { width(of: $0, at: t) }
        let centre = 195 + sin(t * 8.5) * 16
        var x = centre - widths.reduce(0, +) / 2
        return widths.map { width in
            defer { x += width }
            return (left: x, right: x + width)
        }
    }
}
