import SwiftData
import SwiftUI

@main struct CaffyApp: App {
    init() {
        Theme.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Creates the on-device database for these models and makes it
        // available to every view through the environment.
        .modelContainer(for: [Era.self, Moment.self, Place.self, CaffyPlaylist.self])
    }
}
