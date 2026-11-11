import SwiftUI

/// Where one print sits in a collage, on a canvas 338 points wide.
nonisolated struct CollageSlot {
    /// A strip of tape stuck over a print, relative to that print's corner.
    struct Tape {
        let x: Double
        let y: Double
        let rotation: Double
    }

    let x: Double
    let y: Double
    let width: Double
    let height: Double
    /// The print's resting tilt, in degrees.
    let tilt: Double
    var stacking: Double = 0
    var tape: Tape? = nil

    /// The collage layouts from the design, chosen by photo count. Collages
    /// show five photos at most.
    static func layout(forPhotoCount count: Int, firstPhotoAspectRatio: Double) -> [CollageSlot] {
        switch count {
        case ...0: []
        case 1: firstPhotoAspectRatio > 1 ? singleLandscape : singlePortrait
        case 2: Array(three.prefix(2))
        case 3: three
        case 4: Array(five.prefix(4))
        default: five
        }
    }

    private static let singleLandscape = [
        CollageSlot(x: 0, y: 8, width: 330, height: 188, tilt: -1.5, tape: Tape(x: 18, y: -10, rotation: -8))
    ]

    private static let singlePortrait = [
        CollageSlot(x: 34, y: 4, width: 272, height: 360, tilt: 2, tape: Tape(x: 100, y: -8, rotation: -3))
    ]

    private static let three = [
        CollageSlot(x: 0, y: 6, width: 216, height: 286, tilt: -2, stacking: 1, tape: Tape(x: 58, y: -9, rotation: 6)),
        CollageSlot(x: 164, y: 0, width: 168, height: 212, tilt: 3, stacking: 2),
        CollageSlot(x: 136, y: 196, width: 196, height: 206, tilt: -2, stacking: 3)
    ]

    private static let five = [
        CollageSlot(x: 0, y: 0, width: 318, height: 196, tilt: -2, stacking: 1, tape: Tape(x: 128, y: -8, rotation: -5)),
        CollageSlot(x: 172, y: 150, width: 166, height: 232, tilt: 3, stacking: 3, tape: Tape(x: 54, y: -8, rotation: 7)),
        CollageSlot(x: 0, y: 182, width: 176, height: 176, tilt: -3, stacking: 2),
        CollageSlot(x: 22, y: 330, width: 136, height: 150, tilt: 2, stacking: 4),
        CollageSlot(x: 170, y: 348, width: 160, height: 130, tilt: -2, stacking: 5)
    ]

    /// How a print moves on scroll, mirroring the design's Home motion.
    func drift(index: Int) -> DriftingPrint.Drift {
        let centreX = x + width / 2
        let tilt = tilt
        return { distance in
            let side: Double = index.isMultiple(of: 2) ? 1 : -1
            let fan = (centreX - 165) / 165
            return (
                x: fan * abs(distance) * 18 + side * distance * 6,
                y: distance * (14 + Double(index) * 4),
                rotation: tilt + side * distance * 5
            )
        }
    }
}

/// An era's photos, taped down and overlapping like loose prints.
struct EraCollage: View {
    private static let canvasWidth = 338.0

    let moments: [Moment]
    let tapeColor: Color

    private var slots: [CollageSlot] {
        CollageSlot.layout(
            forPhotoCount: moments.count,
            firstPhotoAspectRatio: moments.first?.photoAspectRatio ?? 1
        )
    }

    private var canvasHeight: Double {
        (slots.map { $0.y + $0.height }.max() ?? 0) + 6
    }

    var body: some View {
        Color.clear
            .aspectRatio(Self.canvasWidth / max(canvasHeight, 1), contentMode: .fit)
            .overlay(alignment: .topLeading) {
                GeometryReader { geometry in
                    let scale = geometry.size.width / Self.canvasWidth
                    ForEach(Array(zip(slots.indices, slots)), id: \.0) { index, slot in
                        print(of: moments[index], in: slot, scale: scale)
                            .modifier(DriftingPrint(tilt: slot.tilt, drift: slot.drift(index: index)))
                            .position(
                                x: (slot.x + slot.width / 2) * scale,
                                y: (slot.y + slot.height / 2) * scale
                            )
                            .zIndex(slot.stacking)
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel("\(moments.count) photos")
    }

    private func print(of moment: Moment, in slot: CollageSlot, scale: Double) -> some View {
        let size = CGSize(width: slot.width * scale, height: slot.height * scale)
        return PhotoThumbnail(
            assetIdentifier: moment.photoAssetIdentifier,
            seed: "\(moment.date.timeIntervalSince1970)",
            size: size
        )
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.cream, lineWidth: 6)
            }
            .compositingGroup()
            .shadow(color: Theme.shadow.opacity(0.3), radius: 8, y: 6)
            .overlay(alignment: .topLeading) {
                if let tape = slot.tape {
                    tapeColor
                        .frame(width: 72, height: 22)
                        .rotationEffect(.degrees(tape.rotation))
                        .offset(x: tape.x * scale, y: tape.y * scale)
                }
            }
    }
}
