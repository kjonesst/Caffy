import SwiftData
import SwiftUI

/// The Library tab: how the user's listening has moved, as a river of genres
/// with each era's print sitting on top.
struct LibraryView: View {
    @Query(sort: \Era.startDate, order: .reverse) private var eras: [Era]

    /// The era whose sheet is open.
    @State private var selectedEra: Era?

    /// Where each print rests, in turn: its position across the river on a
    /// 390-point width, and its tilt in degrees.
    private static let resting: [(x: Double, tilt: Double)] = [(244, 3), (56, -3), (246, 2), (52, -2)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("library")
                        .font(Theme.display(44, relativeTo: .largeTitle))
                        .tracking(-1.76)
                        .accessibilityAddTraits(.isHeader)
                    Text("How your listening has moved. Tap an era to open its music.")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.softInk)
                }
                .foregroundStyle(Theme.ink)
                .padding(.leading, 18)
                .padding(.trailing, 84)
                .padding(.top, 8)
                .padding(.bottom, 18)

                if !eras.isEmpty {
                    river
                }
            }
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PaperBackground())
        }
        .scrollIndicators(.hidden)
        .background(Theme.cream)
        .overlay {
            if eras.isEmpty {
                ContentUnavailableView(
                    "No Eras Yet",
                    systemImage: "waveform.path",
                    description: Text("Your listening river appears as Caffy finds eras.")
                )
            }
        }
        .sheet(item: $selectedEra) { era in
            EraSheet(era: era)
        }
    }

    private var river: some View {
        let layout = RiverLayout(eraDates: eras.map(\.startDate), now: .now)

        return GeometryReader { geometry in
            let scale = geometry.size.width / 390

            ZStack(alignment: .topLeading) {
                GenreRiverView(river: .sample, layout: layout, stamps: eras.map(stamp))

                ForEach(Array(eras.enumerated()), id: \.element.id) { index, era in
                    let resting = Self.resting[index % Self.resting.count]
                    EraPrint(era: era, isSelected: selectedEra == era) {
                        selectedEra = era
                    }
                    .modifier(DriftingPrint(tilt: resting.tilt, drift: Self.drift(tilt: resting.tilt)))
                    .offset(
                        x: resting.x * scale,
                        y: layout.notches[index] - RiverLayout.notchOffset + 14
                    )
                }
            }
        }
        .frame(height: layout.height)
    }

    /// How a print sways on scroll, mirroring the design's Library motion.
    private nonisolated static func drift(tilt: Double) -> DriftingPrint.Drift {
        { distance in
            let side: Double = tilt > 0 ? 1 : -1
            return (x: side * distance * 8, y: distance * 26, rotation: tilt + side * distance * 6)
        }
    }

    /// The ruler's date stamp for an era, such as "Apr\n2026".
    private func stamp(for era: Era) -> String {
        let month = era.startDate.formatted(.dateTime.month(.abbreviated))
        let year = era.startDate.formatted(.dateTime.year())
        return "\(month)\n\(year)"
    }
}

#Preview(traits: .sampleData) {
    LibraryView()
}
