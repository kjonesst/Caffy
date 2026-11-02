import SwiftData
import SwiftUI

/// The app's root view: a tab bar with Home and Library.
struct ContentView: View {
    /// The SwiftData context provided by `.modelContainer` in `CaffyApp`.
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeView()
            }
            Tab("Library", systemImage: "square.stack") {
                LibraryView()
            }
        }
        // `.task` runs async work when the view appears, and cancels it if
        // the view goes away first.
        .task {
            await loadSampleDataIfNeeded()
        }
    }

    /// Adds example data on first launch. Remove this once PhotoKit and
    /// MusicKit provide real moments.
    private func loadSampleDataIfNeeded() async {
        do {
            try await SampleData.insertIfNeeded(into: modelContext, using: MockMusicProvider())
        } catch {
            print("Failed to load sample data: \(error)")
        }
    }
}

#Preview(traits: .sampleData) {
    ContentView()
}
