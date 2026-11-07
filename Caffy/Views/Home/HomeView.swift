import SwiftData
import SwiftUI

/// The Home tab: one card per era, newest first.
struct HomeView: View {
    /// `@Query` fetches from SwiftData and re-renders the view when the data
    /// changes.
    @Query(sort: \Era.startDate, order: .reverse) private var eras: [Era]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("caffy")
                        .font(Theme.display(56, weight: .heavy, relativeTo: .largeTitle))
                        .tracking(-2.2)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your photos, with the music of the time.")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.softInk)
                }
                .padding(.horizontal, 6)

                ForEach(Array(eras.enumerated()), id: \.element.id) { index, era in
                    EraCard(era: era, number: eras.count - index)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 120)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .background(PaperBackground())
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
}

#Preview(traits: .sampleData) {
    HomeView()
}
