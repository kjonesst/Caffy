import SwiftData
import SwiftUI

@main struct CaffyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Creates the on-device database for these models and makes it
        // available to every view through the environment.
        .modelContainer(for: [Place.self, Moment.self, CaffyPlaylist.self])
    }
}
