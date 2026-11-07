import SwiftUI

/// Cream paper with a fine grain, tiled so it scrolls with the content.
struct PaperBackground: View {
    var body: some View {
        Theme.cream
            .overlay {
                Image("PaperGrain")
                    .resizable(resizingMode: .tile)
            }
            // Runs past both ends so the grain continues under the status bar
            // and when the content is pulled past its edge.
            .padding(.vertical, -400)
            .accessibilityHidden(true)
    }
}
