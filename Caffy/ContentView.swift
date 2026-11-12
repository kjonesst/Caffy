import SwiftData
import SwiftUI

/// The app's root view: Home and Library, with Caffy's floating controls on top.
struct ContentView: View {
    /// The SwiftData context provided by `.modelContainer` in `CaffyApp`.
    @Environment(\.modelContext) private var modelContext
    @Environment(PermissionsManager.self) private var permissions
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: AppTab = .home
    /// Keeps eras in step with the photo library, once Caffy may read it.
    @State private var librarySync: LibrarySync?

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
            await showEras()
        }
        // Photo access granted later, say from Settings: switch to the real library.
        .onChange(of: permissions.photos) { _, access in
            if access.isGranted {
                Task { await showEras() }
            }
        }
        // The user may have changed access in Settings while away, and has
        // probably listened to something. Each read of the music library
        // narrows down when those plays happened, so record on every return,
        // and sync if anything new was played.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await permissions.refresh() }
                Task {
                    guard let librarySync, let summary = await librarySync.recordListening(), summary.newPlays > 0 else { return }
                    await librarySync.sync()
                }
            }
        }
    }

    /// With photo access, syncs the real library (and keeps syncing as it
    /// changes). Without it, shows the sample eras instead.
    private func showEras() async {
        if permissions.photos.isGranted {
            let sync = librarySync ?? LibrarySync.live(context: modelContext)
            librarySync = sync
            switch await sync.sync() {
            case .synced, .queued:
                await sync.observeLibraryChanges()
                return
            case .noAccess:
                // PhotoKit disagrees with the app's permission state (DEBUG's
                // `-fakePermissions` can do this), so fall back to samples.
                break
            case .failed(let reason):
                print("Library sync failed: \(reason)")
                return
            }
        }
        await loadSampleDataIfNeeded()
    }

    /// Adds example eras when there are none yet, so the app has something to
    /// show before photo access is granted.
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
        .environment(PermissionsManager(client: PreviewPermissionsClient.nothingGranted))
}
