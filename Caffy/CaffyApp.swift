import SwiftData
import SwiftUI

@main struct CaffyApp: App {
    /// Set by "Open Caffy" on the last onboarding step, so onboarding shows once.
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    /// Apple Music and Photos access, shared by onboarding and the main app.
    @State private var permissions = PermissionsManager.forLaunch()
    /// The on-device database: eras and moments in one store, recorded
    /// listening history in another (see `CaffyStore`).
    private let container: ModelContainer

    init() {
        Theme.registerFonts()
        do {
            container = try CaffyStore.makeContainer()
        } catch {
            fatalError("Couldn't open Caffy's database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            // The steaming-cup splash plays over everything on each launch, then
            // flies the title to Home's "caffy" heading (or fades it during onboarding).
            CaffyLaunchContainer {
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
            }
            .environment(permissions)
        }
        // Makes the database available to every view through the environment.
        .modelContainer(container)
    }
}
