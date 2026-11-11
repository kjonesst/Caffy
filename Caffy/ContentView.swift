import SwiftData
import SwiftUI

/// The app's root view: Home and Library, with Caffy's floating controls on top.
struct ContentView: View {
    /// The SwiftData context provided by `.modelContainer` in `CaffyApp`.
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: AppTab = .home

    var body: some View {
        // The system tab bar is hidden in favour of `FloatingTabBar`, but
        // `TabView` still keeps each tab's scroll position when switching.
        TabView(selection: $selectedTab) {
            HomeView()
                .tag(AppTab.home)
                .toolbarVisibility(.hidden, for: .tabBar)
            LibraryView()
                .tag(AppTab.library)
                .toolbarVisibility(.hidden, for: .tabBar)
        }
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $selectedTab)
                .padding(.bottom, 4)
        }
        .overlay(alignment: .topTrailing) {
            ProfileButton()
                .padding(.trailing, 14)
                .padding(.top, 4)
        }
        .tint(Theme.ink)
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
            try await SampleData.insertIfNeeded(into: modelContext)
        } catch {
            print("Failed to load sample data: \(error)")
        }
    }
}

#Preview(traits: .sampleData) {
    ContentView()
}
