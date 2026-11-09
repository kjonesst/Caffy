import SwiftData
import SwiftUI

@main struct CaffyApp: App {
    /// Set by "Open Caffy" on the last onboarding step, so onboarding shows once.
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    /// Apple Music and Photos access, shared by onboarding and the main app.
    @State private var permissions = PermissionsManager.forLaunch()

    init() {
        Theme.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasOnboarded {
                    ContentView()
                        .transition(.opacity)
                } else {
                    OnboardingView(startingAt: .launchStep) {
                        withAnimation(.easeInOut(duration: 0.4)) { hasOnboarded = true }
                    }
                    .transition(.opacity)
                }
            }
            .environment(permissions)
        }
        // Creates the on-device database for these models and makes it
        // available to every view through the environment.
        .modelContainer(for: [Era.self, Moment.self, Place.self, CaffyPlaylist.self])
    }
}
